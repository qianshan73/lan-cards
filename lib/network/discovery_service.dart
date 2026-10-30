import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

import 'discovery_diagnostics.dart';
export 'discovery_diagnostics.dart';

const roomServiceType = '_lancards._tcp';

class FoundRoom {
  const FoundRoom({required this.host, required this.port, required this.info});
  final String host;
  final int port;
  final Map<String, dynamic> info;
  String get id => info['roomId'] as String;
  String get name => info['name'] as String;
  bool get full => (info['occupied'] as int) >= (info['capacity'] as int);
}

/// Small native boundary, injectable without replacing real HTTP probes.
class DiscoveryBackend {
  const DiscoveryBackend();
  // Resolve ourselves: plugin auto-resolution can discard a discovered service
  // before our UI has a chance to report a resolution/address failure.
  Future<nsd.Discovery> start() =>
      nsd.startDiscovery(roomServiceType, autoResolve: false);
  Future<nsd.Service> resolve(nsd.Service service) => nsd.resolve(service);
  Future<void> stop(nsd.Discovery discovery) => nsd.stopDiscovery(discovery);
  Future<nsd.Registration> register(nsd.Service service) =>
      nsd.register(service);
  Future<void> unregister(nsd.Registration registration) =>
      nsd.unregister(registration);
}

class _ProbeResult {
  const _ProbeResult.success(this.room) : failure = null;
  const _ProbeResult.failed(this.failure) : room = null;
  final FoundRoom? room;
  final ProbeFailure? failure;
}

/// DNS-SD locates endpoints; HTTP retrieves fresh, non-secret room metadata.
/// Discovery is never treated as authentication or proof of membership.
class DiscoveryService extends ChangeNotifier {
  DiscoveryService({
    DiscoveryBackend backend = const DiscoveryBackend(),
    this.operationTimeout = const Duration(seconds: 2),
  }) : _backend = backend {
    _http.connectionTimeout = operationTimeout;
  }

  final DiscoveryBackend _backend;
  final Duration operationTimeout;
  nsd.Discovery? _discovery;
  nsd.Registration? _registration;
  Map<nsd.Service, nsd.Service> _resolved = {};
  Timer? _refresh;
  Future<void>? _starting;
  bool _probing = false;
  bool _refreshAgain = false;
  bool _closed = false;
  int _searchGeneration = 0;
  int _publicationGeneration = 0;
  int _manualGeneration = 0;
  final HttpClient _http = HttpClient();
  List<FoundRoom> rooms = [];
  DiscoveryStage _searchStage = DiscoveryStage.idle;
  DiscoveryStage _publicationStage = DiscoveryStage.idle;
  DiscoveryFailure? _searchFailure;
  DiscoveryFailure? _publicationFailure;
  int _servicesSeen = 0;
  int _servicesChecked = 0;
  int _noUsableAddress = 0;
  Map<ProbeFailure, int> _probeFailures = {};
  ProbeFailure? _manualProbeFailure;
  bool searching = false;
  bool get published => _registration != null;
  DiscoveryDiagnostics get diagnostics => DiscoveryDiagnostics(
    search: _searchStage,
    publication: _publicationStage,
    searchFailure: _searchFailure,
    publicationFailure: _publicationFailure,
    servicesSeen: _servicesSeen,
    servicesChecked: _servicesChecked,
    noUsableAddress: _noUsableAddress,
    roomsReachable: rooms.length,
    probeFailures: _probeFailures,
    manualProbeFailure: _manualProbeFailure,
  );

  void _changed() {
    if (!_closed) notifyListeners();
  }

  DiscoveryFailure _nativeFailure(Object error) {
    if (error is nsd.NsdError) {
      return switch (error.cause) {
        nsd.ErrorCause.securityIssue => DiscoveryFailure.permission,
        nsd.ErrorCause.operationNotSupported => DiscoveryFailure.unsupported,
        nsd.ErrorCause.maxLimit ||
        nsd.ErrorCause.alreadyActive => DiscoveryFailure.busy,
        _ => DiscoveryFailure.platform,
      };
    }
    // Never stringify platform exceptions: messages may contain service/TXT data.
    return DiscoveryFailure.platform;
  }

  Future<void> publish(String roomId, int port) async {
    await unpublish();
    if (_closed) return;
    final generation = _publicationGeneration;
    _publicationStage = DiscoveryStage.starting;
    _publicationFailure = null;
    _changed();
    try {
      final registration = await _backend.register(
        nsd.Service(
          name: 'lancards-${roomId.substring(0, 8)}',
          type: roomServiceType,
          port: port,
          txt: {
            'room': Uint8List.fromList(utf8.encode(roomId)),
            'v': Uint8List.fromList(utf8.encode('1')),
          },
        ),
      );
      if (_closed || generation != _publicationGeneration) {
        await _unregister(registration);
        return;
      }
      _registration = registration;
      _publicationStage = DiscoveryStage.active;
    } catch (error) {
      if (_closed || generation != _publicationGeneration) return;
      _publicationStage = DiscoveryStage.failed;
      _publicationFailure = _nativeFailure(error);
      rethrow;
    } finally {
      _changed();
    }
  }

  Future<void> _unregister(nsd.Registration registration) async {
    try {
      await _backend.unregister(registration);
    } catch (_) {
      /* best effort; no raw plugin logging */
    }
  }

  Future<void> unpublish() async {
    _publicationGeneration++;
    final registration = _registration;
    _registration = null;
    _publicationStage = DiscoveryStage.idle;
    _publicationFailure = null;
    _changed();
    if (registration != null) await _unregister(registration);
  }

  Future<void> startSearch() {
    if (_closed) return Future.value();
    if (_starting != null) return _starting!;
    if (_discovery != null) return refresh();
    final future = _start();
    _starting = future;
    return future.whenComplete(() {
      if (identical(_starting, future)) _starting = null;
    });
  }

  Future<void> _start() async {
    final generation = _searchGeneration;
    searching = true;
    _searchStage = DiscoveryStage.starting;
    _searchFailure = null;
    _changed();
    try {
      final discovery = await _backend.start();
      if (_closed || generation != _searchGeneration) {
        await _stop(discovery);
        return;
      }
      _discovery = discovery;
      _searchStage = DiscoveryStage.active;
      discovery.addListener(_onServicesChanged);
      _refresh = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(refresh());
      });
      await refresh();
    } catch (error) {
      if (!_closed && generation == _searchGeneration) {
        _searchStage = DiscoveryStage.failed;
        _searchFailure = _nativeFailure(error);
      }
    } finally {
      if (generation == _searchGeneration) searching = false;
      _changed();
    }
  }

  void _onServicesChanged() => unawaited(refresh());

  static String? _usableHost(String? value) {
    final host = value?.trim();
    if (host == null ||
        host.isEmpty ||
        host.contains(RegExp(r'[\s/@?#]')) ||
        host.contains('://')) {
      return null;
    }
    final address = InternetAddress.tryParse(host);
    if (address != null) {
      if (address.address == '0.0.0.0' ||
          address.address == '::' ||
          address.isMulticast) {
        return null;
      }
      // IPv6 link-local addresses need an interface scope to be usable.
      if (address.type == InternetAddressType.IPv6 &&
          address.isLinkLocal &&
          !host.contains('%')) {
        return null;
      }
    }
    return host;
  }

  static String? _host(nsd.Service service) {
    final addresses = service.addresses ?? <InternetAddress>[];
    for (final type in [InternetAddressType.IPv4, InternetAddressType.IPv6]) {
      for (final address in addresses.where((a) => a.type == type)) {
        final host = _usableHost(address.address);
        if (host != null) return host;
      }
    }
    return _usableHost(service.host);
  }

  Future<void> refresh() async {
    if (_closed || _discovery == null) return;
    if (_probing) {
      _refreshAgain = true;
      return;
    }
    final generation = _searchGeneration;
    _probing = true;
    _refreshAgain = false;
    try {
      final services = _discovery!.services.toList();
      var noAddress = 0;
      final failures = <ProbeFailure, int>{};
      final nextResolved = <nsd.Service, nsd.Service>{};
      final found = await Future.wait(
        services.take(32).map((service) async {
          var resolved = _resolved[service] ?? service;
          if (_host(resolved) == null || resolved.port == null) {
            try {
              resolved = await _backend
                  .resolve(service)
                  .timeout(operationTimeout);
            } catch (_) {
              noAddress++;
              return null;
            }
          }
          final host = _host(resolved);
          final port = resolved.port;
          if (host == null || port == null || port < 1 || port > 65535) {
            noAddress++;
            return null;
          }
          final result = await _probe(host, port);
          if (result.failure case final reason?) {
            failures.update(reason, (n) => n + 1, ifAbsent: () => 1);
          } else {
            // Successful endpoints need only HTTP refresh, not a new native
            // resolution every 3s. Loss or probe failure invalidates this cache.
            nextResolved[service] = resolved;
          }
          return result.room;
        }),
      );
      if (_closed || generation != _searchGeneration) return;
      final unique = <String, FoundRoom>{};
      for (final room in found.whereType<FoundRoom>()) {
        unique[room.id] = room;
      }
      rooms = unique.values.toList()..sort((a, b) => a.name.compareTo(b.name));
      _servicesSeen = services.length;
      _servicesChecked = services.take(32).length;
      _noUsableAddress = noAddress;
      _probeFailures = failures;
      _resolved = nextResolved;
      _changed();
    } finally {
      _probing = false;
      // Service add/remove during a slow probe must not leave a stale list.
      if (_refreshAgain && !_closed && _discovery != null) {
        unawaited(refresh());
      }
    }
  }

  /// Manual fallback uses the same probe but keeps its outcome separate from
  /// the latest automatic-discovery pass. Never retains the entered endpoint.
  Future<FoundRoom?> probe(String host, int port) async {
    if (_closed) return null;
    final generation = ++_manualGeneration;
    final result = await _probe(host, port);
    if (!_closed && generation == _manualGeneration) {
      _manualProbeFailure = result.failure;
      _changed();
    }
    return result.room;
  }

  Future<_ProbeResult> _probe(String host, int port) async {
    if (_usableHost(host) == null || port < 1 || port > 65535) {
      return const _ProbeResult.failed(ProbeFailure.invalidEndpoint);
    }
    // A total deadline also bounds slow trickles; abort cancels late HTTP work.
    HttpClientRequest? request;
    var cancelled = false;
    Future<_ProbeResult> perform() async {
      request = await _http.getUrl(
        Uri(scheme: 'http', host: host, port: port, path: '/room'),
      );
      if (cancelled) {
        request!.abort();
        return const _ProbeResult.failed(ProbeFailure.timeout);
      }
      request!.followRedirects = false;
      final response = await request!.close();
      if (response.statusCode != HttpStatus.ok) {
        request!.abort();
        return const _ProbeResult.failed(ProbeFailure.httpStatus);
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 8192) {
          request!.abort();
          return const _ProbeResult.failed(ProbeFailure.tooLarge);
        }
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic> ||
          data['protocol'] != 1 ||
          data['roomId'] is! String ||
          data['name'] is! String ||
          data['occupied'] is! int ||
          data['capacity'] is! int ||
          (data['capacity'] as int) < 1 ||
          (data['occupied'] as int) < 0 ||
          (data['occupied'] as int) > (data['capacity'] as int)) {
        return const _ProbeResult.failed(ProbeFailure.invalidResponse);
      }
      return _ProbeResult.success(
        FoundRoom(host: host, port: port, info: data),
      );
    }

    try {
      return await perform().timeout(operationTimeout);
    } on TimeoutException {
      cancelled = true;
      request?.abort();
      return const _ProbeResult.failed(ProbeFailure.timeout);
    } on FormatException {
      return const _ProbeResult.failed(ProbeFailure.invalidResponse);
    } catch (_) {
      return const _ProbeResult.failed(ProbeFailure.network);
    }
  }

  Future<void> _stop(nsd.Discovery discovery) async {
    try {
      await _backend.stop(discovery);
    } catch (_) {
      /* best effort */
    }
  }

  Future<void> stopSearch() async {
    _searchGeneration++;
    _starting = null;
    _manualGeneration++;
    _refresh?.cancel();
    _refresh = null;
    final discovery = _discovery;
    _discovery = null;
    searching = false;
    _searchStage = DiscoveryStage.idle;
    _searchFailure = null;
    _servicesSeen = _servicesChecked = _noUsableAddress = 0;
    _probeFailures = {};
    _resolved = {};
    _manualProbeFailure = null;
    rooms = [];
    _changed();
    if (discovery != null) {
      discovery.removeListener(_onServicesChanged);
      await _stop(discovery);
    }
  }

  Future<void> shutdown() async {
    _closed = true;
    await stopSearch();
    await unpublish();
    _http.close(force: true);
  }
}
