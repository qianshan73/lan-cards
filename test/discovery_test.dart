import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/network/discovery_service.dart';
import 'package:nsd/nsd.dart' as nsd;

import 'helpers.dart';

const privateMarker = 'PRIVATE-ROOM-TOKEN-HAND-DO-NOT-REPORT';
const metadata = {
  'protocol': 1,
  'roomId': privateMarker,
  'name': privateMarker,
  'occupied': 1,
  'capacity': 3,
  // Even unexpected fields must never end up in diagnostic output.
  'token': privateMarker,
  'hand': [privateMarker],
};

class PendingBackend extends FakeDiscoveryBackend {
  final pendingStart = Completer<nsd.Discovery>();
  final pendingRegistration = Completer<nsd.Registration>();
  @override
  Future<nsd.Discovery> start() => pendingStart.future;
  @override
  Future<nsd.Registration> register(nsd.Service service) =>
      pendingRegistration.future;
}

void main() {
  for (final entry in {
    nsd.ErrorCause.securityIssue: DiscoveryFailure.permission,
    nsd.ErrorCause.operationNotSupported: DiscoveryFailure.unsupported,
    nsd.ErrorCause.maxLimit: DiscoveryFailure.busy,
    nsd.ErrorCause.internalError: DiscoveryFailure.platform,
  }.entries) {
    test(
      'DNS-SD startup classifies ${entry.key.name}, retry clears failure',
      () async {
        final backend = FakeDiscoveryBackend()
          ..startError = nsd.NsdError(entry.key, privateMarker);
        final service = DiscoveryService(backend: backend);
        addTearDown(service.shutdown);
        await service.startSearch();
        expect(service.diagnostics.search, DiscoveryStage.failed);
        expect(service.diagnostics.searchFailure, entry.value);
        expect(
          service.diagnostics.safeReport(),
          isNot(contains(privateMarker)),
        );
        backend.startError = null;
        await service.startSearch();
        expect(service.diagnostics.search, DiscoveryStage.active);
        expect(service.diagnostics.searchFailure, isNull);
        expect(service.diagnostics.servicesSeen, 0);
        await service.stopSearch();
        expect(service.diagnostics.search, DiscoveryStage.idle);
      },
    );
  }

  test(
    'registration failure is separate from search and retry clears it',
    () async {
      final backend = FakeDiscoveryBackend()
        ..registerError = nsd.NsdError(
          nsd.ErrorCause.securityIssue,
          privateMarker,
        );
      final service = DiscoveryService(backend: backend);
      addTearDown(service.shutdown);
      await service.startSearch();
      await expectLater(
        service.publish(privateMarker, 12345),
        throwsA(isA<nsd.NsdError>()),
      );
      expect(service.published, false);
      expect(service.diagnostics.publication, DiscoveryStage.failed);
      expect(
        service.diagnostics.publicationFailure,
        DiscoveryFailure.permission,
      );
      expect(service.diagnostics.search, DiscoveryStage.active);
      backend.registerError = null;
      await service.publish(privateMarker, 12345);
      expect(service.published, true);
      expect(service.diagnostics.publication, DiscoveryStage.active);
      expect(service.diagnostics.publicationFailure, isNull);
      await service.unpublish();
      expect(service.diagnostics.publication, DiscoveryStage.idle);
      expect(backend.unregisterCalls, 1);
    },
  );

  test(
    'late native results after stop cannot revive search or publication',
    () async {
      final backend = PendingBackend();
      final service = DiscoveryService(backend: backend);
      addTearDown(service.shutdown);
      final start = service.startSearch();
      expect(service.diagnostics.search, DiscoveryStage.starting);
      await service.stopSearch();
      backend.pendingStart.complete(backend.discovery);
      await start;
      expect(service.diagnostics.search, DiscoveryStage.idle);
      expect(backend.stopCalls, 1);
      final publish = service.publish(privateMarker, 12345);
      await Future<void>.delayed(Duration.zero);
      expect(service.diagnostics.publication, DiscoveryStage.starting);
      await service.unpublish();
      backend.pendingRegistration.complete(
        nsd.Registration('late', const nsd.Service(name: privateMarker)),
      );
      await publish;
      expect(service.published, false);
      expect(service.diagnostics.publication, DiscoveryStage.idle);
      expect(backend.unregisterCalls, 1);
    },
  );

  test(
    'addressless/unusable services are counted, recover and disappear without stale counts',
    () async {
      final backend = FakeDiscoveryBackend();
      const empty = nsd.Service(name: privateMarker);
      const wildcard = nsd.Service(
        name: 'wildcard',
        host: '0.0.0.0',
        port: 12345,
      );
      const badPort = nsd.Service(name: 'bad-port', host: '192.0.2.1', port: 0);
      backend.discovery.add(empty);
      backend.discovery.add(wildcard);
      backend.discovery.add(badPort);
      final service = DiscoveryService(backend: backend);
      addTearDown(service.shutdown);
      await service.startSearch();
      expect(service.diagnostics.servicesSeen, 3);
      expect(service.diagnostics.noUsableAddress, 3);
      expect(service.diagnostics.failedProbes, 0);
      expect(service.rooms, isEmpty);
      backend.discovery.remove(empty);
      backend.discovery.remove(wildcard);
      backend.discovery.remove(badPort);
      await service.refresh();
      // A coalesced refresh follows notifications received during a probe.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(service.diagnostics.noUsableAddress, 0);
      expect(service.diagnostics.servicesSeen, 0);
    },
  );

  test(
    'native resolution failure is address stage, not HTTP or startup failure',
    () async {
      final backend = FakeDiscoveryBackend()
        ..resolveError = nsd.NsdError(
          nsd.ErrorCause.internalError,
          privateMarker,
        );
      backend.discovery.add(const nsd.Service(name: privateMarker));
      final service = DiscoveryService(backend: backend);
      addTearDown(service.shutdown);
      await service.startSearch();
      expect(service.diagnostics.search, DiscoveryStage.active);
      expect(service.diagnostics.noUsableAddress, 1);
      expect(service.diagnostics.failedProbes, 0);
    },
  );

  late HttpServer http;
  late DiscoveryService service;
  late FakeDiscoveryBackend backend;
  group('real local HTTP room probes', () {
    setUp(() async {
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      backend = FakeDiscoveryBackend();
      service = DiscoveryService(
        backend: backend,
        operationTimeout: const Duration(milliseconds: 200),
      );
    });
    tearDown(() async {
      await service.shutdown();
      await http.close(force: true);
    });

    test(
      'successful resolved service recovers; report excludes all remote data and endpoints',
      () async {
        http.listen((request) async {
          request.response.write(jsonEncode(metadata));
          await request.response.close();
        });
        backend.discovery.add(const nsd.Service(name: privateMarker));
        await service.startSearch();
        expect(service.diagnostics.noUsableAddress, 1);
        expect(service.rooms, isEmpty);
        backend.resolved = nsd.Service(host: '127.0.0.1', port: http.port);
        await service.refresh();
        expect(service.rooms, hasLength(1));
        expect(service.diagnostics.roomsReachable, 1);
        expect(service.diagnostics.noUsableAddress, 0);
        final report = service.diagnostics.safeReport();
        expect(report, contains('rooms_reachable=1'));
        expect(report, isNot(contains(privateMarker)));
        expect(report, isNot(contains('127.0.0.1')));
        expect(report, isNot(contains(http.port.toString())));
        await service.refresh();
        expect(service.diagnostics.roomsReachable, 1);
        expect(backend.resolveCalls, 2);
        expect(
          () => service.diagnostics.probeFailures[ProbeFailure.network] = 9,
          throwsUnsupportedError,
        );
      },
    );

    for (final reason in [
      ProbeFailure.httpStatus,
      ProbeFailure.invalidResponse,
      ProbeFailure.tooLarge,
      ProbeFailure.timeout,
    ]) {
      test('${reason.name} is actionable, retry clears manual failure', () async {
        var broken = true;
        http.listen((request) async {
          if (!broken) {
            request.response.write(jsonEncode(metadata));
          } else {
            switch (reason) {
              case ProbeFailure.httpStatus:
                request.response.statusCode = 503;
                request.response.write(privateMarker);
              case ProbeFailure.invalidResponse:
                request.response.write(
                  '{"protocol":99,"secret":"$privateMarker"}',
                );
              case ProbeFailure.tooLarge:
                request.response.write(privateMarker * 400);
              case ProbeFailure.timeout:
                // Leave response open until teardown, without a delayed test timer.
                return;
              default:
                throw StateError('unexpected test case');
            }
          }
          await request.response.close();
        });
        expect(await service.probe('127.0.0.1', http.port), isNull);
        expect(service.diagnostics.manualProbeFailure, reason);
        expect(
          service.diagnostics.safeReport(),
          isNot(contains(privateMarker)),
        );
        broken = false;
        expect(await service.probe('127.0.0.1', http.port), isNotNull);
        expect(service.diagnostics.manualProbeFailure, isNull);
      });
    }

    test(
      'automatic probe failure counts reset on success, manual results stay separate',
      () async {
        var healthy = false;
        http.listen((request) async {
          request.response.statusCode = healthy ? 200 : 403;
          request.response.write(jsonEncode(metadata));
          await request.response.close();
        });
        backend.discovery.add(
          nsd.Service(name: privateMarker, host: '127.0.0.1', port: http.port),
        );
        await service.startSearch();
        expect(service.diagnostics.probeFailures, {ProbeFailure.httpStatus: 1});
        expect(service.diagnostics.manualProbeFailure, isNull);
        await service.refresh();
        expect(service.diagnostics.failedProbes, 1); // Not an accumulating log.
        healthy = true;
        await service.refresh();
        expect(service.diagnostics.failedProbes, 0);
        expect(service.rooms, hasLength(1));
      },
    );

    test(
      'HTTP redirects are rejected rather than followed to another endpoint',
      () async {
        var requests = 0;
        http.listen((request) async {
          requests++;
          request.response.statusCode = 302;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/secret-$privateMarker',
          );
          await request.response.close();
        });
        expect(await service.probe('127.0.0.1', http.port), isNull);
        expect(requests, 1);
        expect(service.diagnostics.manualProbeFailure, ProbeFailure.httpStatus);
      },
    );

    test('invalid JSON/UTF-8 is not a generic connectivity failure', () async {
      http.listen((request) async {
        request.response.add([0xff]);
        await request.response.close();
      });
      await service.probe('127.0.0.1', http.port);
      expect(
        service.diagnostics.manualProbeFailure,
        ProbeFailure.invalidResponse,
      );
    });

    test(
      'connection refusal and invalid endpoint have distinct codes',
      () async {
        // Windows can take >200 ms to report ECONNREFUSED. Only explicit
        // timeout tests should use the short deadline.
        await service.shutdown();
        service = DiscoveryService(
          backend: backend,
          operationTimeout: const Duration(seconds: 4),
        );
        final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = unused.port;
        await unused.close();
        await service.probe('127.0.0.1', port);
        expect(service.diagnostics.manualProbeFailure, ProbeFailure.network);
        await service.probe('', 0);
        expect(
          service.diagnostics.manualProbeFailure,
          ProbeFailure.invalidEndpoint,
        );
      },
    );

    test(
      'stopped search ignores a late probe and clears previous statistics',
      () async {
        final requested = Completer<void>();
        HttpResponse? response;
        http.listen((request) {
          response = request.response;
          requested.complete();
        });
        backend.discovery.add(
          nsd.Service(name: privateMarker, host: '127.0.0.1', port: http.port),
        );
        final start = service.startSearch();
        await requested.future;
        await service.stopSearch();
        response!.write(jsonEncode(metadata));
        await response!.close();
        await start;
        expect(service.rooms, isEmpty);
        expect(service.diagnostics.search, DiscoveryStage.idle);
        expect(service.diagnostics.servicesSeen, 0);
      },
    );
  });
}
