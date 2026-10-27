import 'package:lan_cards/network/discovery_service.dart';
import 'package:lan_cards/network/room_client.dart';
import 'package:lan_cards/storage/local_store.dart';

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
