import 'dart:io';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/round_robin.dart';
import 'package:lan_cards/network/room_server.dart';

/// Headless protocol harness, not a replacement for mobile Bonjour/NSD tests.
Future<void> main(List<String> args) async {
  final room = Room(name: '协议调试房间', hostName: '调试房主', rules: RoundRobinRules());
  final server = RoomServer(room);
  await server.start(port: args.isEmpty ? 0 : int.parse(args.first));
  stdout.writeln('Headless host: http://127.0.0.1:${server.port}/room');
  stdout.writeln(
    'This harness does not publish DNS-SD or seat a playing host.',
  );
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    exit(0);
  });
}
