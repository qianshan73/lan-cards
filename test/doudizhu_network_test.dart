import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/core/game_rules.dart';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/doudizhu/patterns.dart';
import 'package:lan_cards/games/doudizhu/rules.dart';
import 'package:lan_cards/network/room_client.dart';
import 'package:lan_cards/network/room_server.dart';

Future<void> waitFor(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('state sync');
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  test('old clients are rejected before taking a Dou Dizhu seat', () async {
    final room = Room(
      name: '新版本牌桌',
      hostName: '房主',
      rules: DoudizhuRules(),
      capacity: 3,
    );
    final server = RoomServer(room);
    await server.start();
    addTearDown(server.close);
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/play',
    );
    final first = socket.first;
    socket.add(
      jsonEncode({
        'type': 'hello',
        'protocol': 1,
        'roomId': room.id,
        'name': '旧客户端',
      }),
    );
    final response = jsonDecode(await first as String) as Map;
    expect(response['code'], 'unsupported_game');
    expect(room.members, hasLength(1));
    await socket.close();
  });
  test(
    'three real clients bid, play, pause, restore hidden hand and finish next round',
    () async {
      final room = Room(
        name: '联机斗地主',
        hostName: '房主',
        rules: DoudizhuRules(),
        capacity: 3,
        random: Random(7),
      );
      final server = RoomServer(room);
      await server.start();
      final clients = <String, RoomClient>{};
      final all = <RoomClient>[];
      addTearDown(() async {
        for (final client in all) {
          await client.dispose();
        }
        await server.close();
      });
      final host = RoomClient();
      all.add(host);
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
          isHost: true,
        ),
      );
      clients[room.host.id] = host;
      for (final name in ['朋友甲', '朋友乙']) {
        final c = RoomClient();
        all.add(c);
        final ticket = await c.connect(
          host: '127.0.0.1',
          port: server.port,
          roomId: room.id,
          name: name,
        );
        clients[ticket.playerId] = c;
      }
      for (final client in clients.values) {
        await client.command('ready', {'ready': true});
      }
      await host.command('start');
      while ((room.game as DoudizhuState).stage == DdzStage.bidding) {
        final g = room.game as DoudizhuState;
        await clients[g.turnPlayer]!.command('play', {
          'type': 'bid',
          'bid': g.callerId == null ? 'call' : 'pass',
          'roundId': room.roundId,
        });
      }
      await waitFor(
        () => clients.values.every(
          (c) => (c.view?['game'] as Map?)?['stage'] == 'playing',
        ),
      );
      final game = room.game as DoudizhuState;
      for (final entry in clients.entries) {
        final view = entry.value.view!['game'] as Map;
        expect(view['hand'], hasLength(entry.key == game.landlordId ? 20 : 17));
        expect(view['bottomCards'], hasLength(3));
        expect(view.containsKey('hands'), false);
      }
      final guest = clients.entries.firstWhere((e) => e.key != room.host.id);
      final ticket = guest.value.ticket!;
      final oldHand = List<int>.from(
        (guest.value.view!['game'] as Map)['hand'] as List,
      );
      await guest.value.disconnect();
      await waitFor(() => room.phase == RoomPhase.paused);
      final actor = room.game!.turnPlayer!;
      if (actor != guest.key) {
        await expectLater(
          clients[actor]!.command('play', {
            'roundId': room.roundId,
            'type': 'play',
            'cards': [(room.game as DoudizhuState).hands[actor]!.first],
          }),
          throwsA(isA<RuleError>()),
        );
      }
      final restored = RoomClient();
      all.add(restored);
      await restored.connect(
        host: '127.0.0.1',
        port: server.port,
        roomId: room.id,
        resume: ticket,
      );
      clients[guest.key] = restored;
      await waitFor(() => room.phase == RoomPhase.playing);
      expect((restored.view!['game'] as Map)['hand'], oldHand);
      var turns = 0;
      while (!room.game!.finished) {
        final g = room.game as DoudizhuState;
        final hand = suggestPlay(g.hands[g.turnPlayer]!, g.lastPlay?.cards);
        await clients[g.turnPlayer]!.command('play', {
          'roundId': room.roundId,
          'type': hand.isEmpty ? 'pass' : 'play',
          if (hand.isNotEmpty) 'cards': hand,
        });
        expect(++turns, lessThan(200));
      }
      await waitFor(
        () => clients.values.every(
          (c) => (c.view?['game'] as Map?)?['finished'] == true,
        ),
      );
      expect(room.members.map((m) => m.points).reduce((a, b) => a + b), 0);
      final oldRound = room.roundId;
      for (final client in clients.values) {
        await client.command('ready', {'ready': true});
      }
      await host.command('start');
      expect(room.roundId, isNot(oldRound));
      expect((room.game as DoudizhuState).stage, DdzStage.bidding);
    },
  );
}
