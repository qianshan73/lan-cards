import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/room_client.dart';

abstract class TicketStore {
  Future<ResumeTicket?> loadTicket();
  Future<void> saveTicket(ResumeTicket ticket);
  Future<void> clearTicket();
}

class LocalStore implements TicketStore {
  const LocalStore();
  static const _secure = FlutterSecureStorage();
  static const _ticketKey = 'lan_cards.resume.v1';

  @override
  Future<ResumeTicket?> loadTicket() async {
    final raw = await _secure.read(key: _ticketKey);
    if (raw == null) return null;
    try {
      return ResumeTicket.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clearTicket();
      return null;
    }
  }

  @override
  Future<void> saveTicket(ResumeTicket ticket) =>
      _secure.write(key: _ticketKey, value: jsonEncode(ticket.toJson()));
  @override
  Future<void> clearTicket() => _secure.delete(key: _ticketKey);

  Future<String> loadNickname() async {
    return (await SharedPreferences.getInstance()).getString('nickname') ??
        '朋友';
  }

  Future<void> saveNickname(String name) async {
    await (await SharedPreferences.getInstance()).setString('nickname', name);
  }
}
