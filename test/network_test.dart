import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/core/game_rules.dart';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/round_robin.dart';
import 'package:lan_cards/network/room_client.dart';
import 'package:lan_cards/network/room_server.dart';

Future<void> until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('state not received');
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  late Room room;
  late RoomServer server;
  late RoomClient host;
  final clients = <RoomClient>[];
  Future<RoomClient> join(String name) async {
    final client = RoomClient();
    clients.add(client);
    await client.connect(
      host: '127.0.0.1',
      port: server.port,
      roomId: room.id,
      name: name,
    );
    return client;
  }

  setUp(() async {
    room = Room(
      name: '网络测试',
      hostName: '房主',
      rules: RoundRobinRules(),
      capacity: 4,
    );
    server = RoomServer(room);
    await server.start(address: InternetAddress.loopbackIPv4);
    host = RoomClient();
    clients.add(host);
    await host.connect(
      host: '127.0.0.1',
      port: server.port,
      roomId: room.id,
      resume: ResumeTicket(
        roomId: room.id,
        playerId: room.host.id,
        token: room.host.token,
        host: '127.0.0.1',
        port: server.port,
        roomName: room.name,
      ),
    );
  });
  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
    await server.close();
  });

  test('HTTP discovery metadata contains no credentials or hands', () async {
    final http = HttpClient();
    try {
      final request = await http.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/room'),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      expect(jsonDecode(body)['roomId'], room.id);
      expect(body, isNot(contains(room.host.token)));
      expect(body, isNot(contains('hand')));
    } finally {
      http.close(force: true);
    }
  });

  test(
    'real sockets: join, deal privately, pause, restart guest client, auto resume',
    () async {
      final guest = await join('小红');
      await host.command('ready', {'ready': true});
      await guest.command('ready', {'ready': true});
      await host.command('start');
      await until(() => guest.view?['game'] != null);
      final ticketJson = jsonEncode(guest.ticket!.toJson());
      final hand = List<int>.from((guest.view!['game'] as Map)['hand'] as List);
      final roundId = guest.view!['roundId'];
      await guest.disconnect();
      await until(() => host.view?['phase'] == 'paused');
      expect(room.members, hasLength(2));
      final resumed = RoomClient();
      clients.add(resumed);
      final ticket = ResumeTicket.fromJson(
        jsonDecode(ticketJson) as Map<String, dynamic>,
      );
      await resumed.connect(
        host: '127.0.0.1',
        port: server.port,
        roomId: room.id,
        resume: ticket,
      );
      await until(() => host.view?['phase'] == 'playing');
      expect(resumed.view!['you'], ticket.playerId);
      expect(resumed.view!['roundId'], roundId);
      expect((resumed.view!['game'] as Map)['hand'], hand);
      expect((host.view!['game'] as Map).containsKey('hands'), false);
    },
  );

  test(
    'replacing old transport does not mark the new connection offline',
    () async {
      final guest = await join('小红');
      final replacement = RoomClient();
      clients.add(replacement);
      final ticket = guest.ticket!;
      await replacement.connect(
        host: '127.0.0.1',
        port: server.port,
        roomId: room.id,
        resume: ticket,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(room.member(ticket.playerId)?.online, true);
      expect(replacement.connected, true);
    },
  );

  test(
    'kick revokes credentials and disallows automatic seat reclaim',
    () async {
      final guest = await join('小红');
      final ticket = guest.ticket!;
      await host.command('kick', {'playerId': ticket.playerId});
      await until(() => guest.ticket == null);
      final retry = RoomClient();
      clients.add(retry);
      await expectLater(
        retry.connect(
          host: '127.0.0.1',
          port: server.port,
          roomId: room.id,
          resume: ticket,
        ),
        throwsA(isA<RuleError>()),
      );
    },
  );

  test(
    'guest cannot impersonate the host with command payload fields',
    () async {
      final guest = await join('小红');
      await expectLater(
        guest.command('kick', {
          'playerId': room.host.id,
          'actorId': room.host.id,
        }),
        throwsA(isA<RuleError>()),
      );
      expect(room.member(room.host.id), isNotNull);
    },
  );

  test(
    'malformed websocket messages do not crash host or allocate seats',
    () async {
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/play',
      );
      final messages = StreamIterator(socket);
      socket.add('not json');
      expect(await messages.moveNext(), true);
      expect(jsonDecode(messages.current as String)['type'], 'error');
      expect(room.members, hasLength(1));
      await socket.close();
      await messages.cancel();
      final guest = await join('still works');
      expect(guest.connected, true);
    },
  );

  test('host closure invalidates room instead of migrating it', () async {
    final guest = await join('小红');
    await server.close();
    await until(() => guest.ticket == null);
    expect(guest.connected, false);
  });
}
