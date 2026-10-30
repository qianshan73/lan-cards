import 'package:lan_cards/network/discovery_service.dart';
import 'package:lan_cards/network/room_client.dart';
import 'package:lan_cards/storage/local_store.dart';
import 'package:nsd/nsd.dart' as nsd;

class MemoryStore extends LocalStore {
  ResumeTicket? ticket;
  String name = '小明';
  @override
  Future<ResumeTicket?> loadTicket() async => ticket;
  @override
  Future<void> saveTicket(ResumeTicket value) async {
    ticket = value;
  }

  @override
  Future<void> clearTicket() async {
    ticket = null;
  }

  @override
  Future<String> loadNickname() async => name;
  @override
  Future<void> saveNickname(String value) async {
    name = value;
  }
}

/// Native DNS-SD itself must be tested on physical Android/iOS devices.
/// Real sockets are intentionally NOT mocked in controller/network tests.
class FakeDiscovery extends DiscoveryService {
  @override
  Future<void> publish(String roomId, int port) async {}
  @override
  Future<void> unpublish() async {}
  @override
  Future<void> startSearch() async {}
  @override
  Future<void> stopSearch() async {}
}

/// Injects only the native boundary. HTTP is still exercised by real sockets.
class FakeDiscoveryBackend extends DiscoveryBackend {
  final discovery = nsd.Discovery('test-only');
  Object? startError;
  Object? registerError;
  Object? resolveError;
  nsd.Service? resolved;
  int startCalls = 0;
  int resolveCalls = 0;
  int stopCalls = 0;
  int unregisterCalls = 0;

  @override
  Future<nsd.Discovery> start() async {
    startCalls++;
    if (startError case final error?) throw error;
    return discovery;
  }

  @override
  Future<nsd.Service> resolve(nsd.Service service) async {
    resolveCalls++;
    if (resolveError case final error?) throw error;
    return resolved ?? service;
  }

  @override
  Future<void> stop(nsd.Discovery discovery) async {
    stopCalls++;
  }

  @override
  Future<nsd.Registration> register(nsd.Service service) async {
    if (registerError case final error?) throw error;
    return nsd.Registration('test-only', service);
  }

  @override
  Future<void> unregister(nsd.Registration registration) async {
    unregisterCalls++;
  }
}
