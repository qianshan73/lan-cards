import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

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

/// DNS-SD locates endpoints; HTTP retrieves fresh, non-secret room metadata.
/// Discovery is never treated as authentication or proof of membership.
class DiscoveryService extends ChangeNotifier {
  nsd.Discovery? _discovery;
  nsd.Registration? _registration;
  Timer? _refresh;
  Future<void>? _starting;
  bool _probing = false;
  bool _closed = false;
  int _searchGeneration = 0;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2);
  List<FoundRoom> rooms = [];
  String? error;
  bool searching = false;
  bool get published => _registration != null;

  Future<void> publish(String roomId, int port) async {
    await unpublish();
    _registration = await nsd.register(
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
  }

  Future<void> unpublish() async {
    final registration = _registration;
    _registration = null;
    if (registration != null) {
      try {
        await nsd.unregister(registration);
      } catch (_) {
        /* best effort */
      }
    }
  }

  Future<void> startSearch() {
    if (_closed) return Future.value();
    if (_starting != null) return _starting!;
    if (_discovery != null) return refresh();
    final future = _start();
    _starting = future;
    return future.whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    final generation = _searchGeneration;
    searching = true;
    error = null;
    notifyListeners();
    try {
      final discovery = await nsd.startDiscovery(
        roomServiceType,
        ipLookupType: nsd.IpLookupType.any,
      );
      if (_closed || generation != _searchGeneration) {
        await nsd.stopDiscovery(discovery);
        return;
      }
      _discovery = discovery;
      discovery.addListener(_onServicesChanged);
      _refresh = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(refresh());
      });
      await refresh();
    } catch (_) {
      error = '搜索暂不可用，请检查本地网络权限，并确认已连接 Wi-Fi 或手机热点。';
    } finally {
      searching = false;
      if (!_closed) notifyListeners();
    }
  }

  void _onServicesChanged() => unawaited(refresh());

  Future<void> refresh() async {
    if (_probing || _closed) return;
    _probing = true;
    try {
      final services = _discovery?.services.toList() ?? <nsd.Service>[];
      final found = await Future.wait(
        services.take(32).map((service) async {
          String? host;
          for (final address in service.addresses ?? <InternetAddress>[]) {
            if (address.type == InternetAddressType.IPv4) {
              host = address.address;
              break;
            }
          }
          host ??= service.host;
          if (host == null || service.port == null) return null;
          return probe(host, service.port!);
        }),
      );
      final unique = <String, FoundRoom>{};
      for (final room in found.whereType<FoundRoom>()) {
        unique[room.id] = room;
      }
      rooms = unique.values.toList()..sort((a, b) => a.name.compareTo(b.name));
      if (!_closed) notifyListeners();
    } finally {
      _probing = false;
    }
  }

  Future<FoundRoom?> probe(String host, int port) async {
    try {
      if (port < 1 || port > 65535) return null;
      final request = await _http
          .getUrl(Uri(scheme: 'http', host: host, port: port, path: '/room'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 2))) {
        bytes.addAll(chunk);
        if (bytes.length > 8192) return null;
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic> ||
          data['protocol'] != 1 ||
          data['roomId'] is! String ||
          data['name'] is! String ||
          data['occupied'] is! int ||
          data['capacity'] is! int) {
        return null;
      }
      return FoundRoom(host: host, port: port, info: data);
    } catch (_) {
      return null;
    }
  }

  Future<void> stopSearch() async {
    _searchGeneration++;
    _refresh?.cancel();
    _refresh = null;
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) {
      discovery.removeListener(_onServicesChanged);
      try {
        await nsd.stopDiscovery(discovery);
      } catch (_) {
        /* best effort */
      }
    }
  }

  Future<void> shutdown() async {
    _closed = true;
    await stopSearch();
    await unpublish();
    _http.close(force: true);
  }
}
