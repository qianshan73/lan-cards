import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/core/game_rules.dart';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/round_robin.dart';

void main() {
  late Room room;
  var counter = 0;
  void command(
    Member member,
    String name, [
    Map<String, dynamic> payload = const {},
  ]) {
    room.execute(member.id, 'request-${counter++}', name, payload);
  }

  void start() {
    for (final member in room.members) {
      command(member, 'ready', {'ready': true});
    }
    command(room.host, 'start');
  }

  setUp(() {
    room = Room(
      name: '朋友的牌桌',
      hostName: '房主',
      rules: RoundRobinRules(),
      capacity: 4,
      random: Random(42),
    );
  });

  test('offline members occupy seats indefinitely, including across abort', () {
    final guest = room.join('小红');
    start();
    room.disconnect(guest.id);
    expect(room.phase, RoomPhase.paused);
    expect(room.members.length, 2);
    command(room.host, 'abort');
    expect(room.phase, RoomPhase.lobby);
    expect(room.member(guest.id)?.seat, guest.seat);
    expect(room.member(guest.id)?.online, false);
    expect(room.lastResult, contains('不计分'));
    command(room.host, 'ready', {'ready': true});
    expect(() => command(room.host, 'start'), throwsA(isA<RuleError>()));
  });

  test('full room rejects new players even if a seat is offline', () {
    final guest = room.join('A');
    room.join('B');
    room.join('C');
    room.disconnect(guest.id);
    expect(() => room.join('D'), throwsA(isA<RuleError>()));
  });

  test('resume restores the same seat and hand and automatically unpauses', () {
    final guest = room.join('小红');
    start();
    final hand = (room.viewFor(guest.id)['game'] as Map)['hand'];
    final round = room.roundId;
    room.disconnect(guest.id);
    expect(room.phase, RoomPhase.paused);
    room.resume(guest.id, guest.token);
    expect(room.phase, RoomPhase.playing);
    expect(room.roundId, round);
    expect((room.viewFor(guest.id)['game'] as Map)['hand'], hand);
    expect(room.member(guest.id)?.seat, guest.seat);
  });

  test('no early resume while another round participant remains offline', () {
    final a = room.join('A');
    final b = room.join('B');
    start();
    room.disconnect(a.id);
    room.disconnect(b.id);
    room.resume(a.id, a.token);
    expect(room.phase, RoomPhase.paused);
    room.resume(b.id, b.token);
    expect(room.phase, RoomPhase.playing);
  });

  test('player view contains only own hand and no resume credentials', () {
    final guest = room.join('小红');
    start();
    final own = room.viewFor(room.host.id);
    final other = room.viewFor(guest.id);
    final ownHand = (own['game'] as Map)['hand'] as List;
    final otherHand = (other['game'] as Map)['hand'] as List;
    expect(ownHand.length, 5);
    expect(ownHand.toSet().intersection(otherHand.toSet()), isEmpty);
    expect((own['game'] as Map).containsKey('hands'), false);
    expect(jsonEncode(own), isNot(contains(guest.token)));
    expect(jsonEncode(own), isNot(contains(room.host.token)));
  });

  test(
    'newcomer may occupy empty seat mid-round but cannot enter this hand',
    () {
      room.join('小红');
      start();
      final current = room.game!.participants.toList();
      final newcomer = room.join('小李');
      final view = room.viewFor(newcomer.id)['game'] as Map;
      expect(view['waitingNextRound'], true);
      expect(view['hand'], isEmpty);
      expect(room.game!.participants, current);
      room.disconnect(newcomer.id);
      expect(room.phase, RoomPhase.playing);
    },
  );

  test('newcomer joins next round after all members prepare', () {
    room.join('小红');
    start();
    final newcomer = room.join('小李');
    command(room.host, 'abort');
    start();
    expect(room.game!.participants, contains(newcomer.id));
    expect((room.viewFor(newcomer.id)['game'] as Map)['hand'], hasLength(5));
  });

  test('non-host cannot start, abort or kick', () {
    final guest = room.join('小红');
    for (final action in ['start', 'abort', 'kick']) {
      expect(
        () => command(guest, action, {'playerId': room.host.id}),
        throwsA(isA<RuleError>().having((e) => e.code, 'code', 'host_only')),
      );
    }
  });

  test(
    'host kick revokes token, frees seat, and delegates departure to game',
    () {
      final guest = room.join('小红');
      room.join('小李');
      start();
      room.disconnect(guest.id);
      command(room.host, 'kick', {'playerId': guest.id});
      expect(room.member(guest.id), isNull);
      expect(room.game!.participants, isNot(contains(guest.id)));
      expect(room.phase, RoomPhase.playing);
      expect(
        () => room.resume(guest.id, guest.token),
        throwsA(isA<RuleError>()),
      );
      expect(room.join('新人').seat, guest.seat);
    },
  );

  test('wrong credentials cannot claim someone else seat', () {
    final guest = room.join('小红');
    room.disconnect(guest.id);
    expect(() => room.resume(guest.id, 'wrong'), throwsA(isA<RuleError>()));
    expect(room.member(guest.id)?.online, false);
  });

  test('one command ID cannot play a card twice', () {
    room.join('小红');
    start();
    final hand = (room.viewFor(room.host.id)['game'] as Map)['hand'] as List;
    final payload = {
      'roundId': room.roundId,
      'type': 'play',
      'card': hand.first,
    };
    expect(room.execute(room.host.id, 'same-id', 'play', payload), true);
    final revision = room.revision;
    expect(room.execute(room.host.id, 'same-id', 'play', payload), false);
    expect(room.revision, revision);
    expect((room.viewFor(room.host.id)['game'] as Map)['hand'], hasLength(4));
  });

  test('stale commands cannot affect a newly started round', () {
    room.join('小红');
    start();
    final oldRound = room.roundId;
    command(room.host, 'abort');
    start();
    final hand = (room.viewFor(room.host.id)['game'] as Map)['hand'] as List;
    expect(
      () => command(room.host, 'play', {
        'roundId': oldRound,
        'type': 'play',
        'card': hand.first,
      }),
      throwsA(isA<RuleError>().having((e) => e.code, 'code', 'stale_round')),
    );
  });

  test(
    'paused round rejects plays; turn and card ownership are authoritative',
    () {
      final guest = room.join('小红');
      start();
      final guestHand = (room.viewFor(guest.id)['game'] as Map)['hand'] as List;
      expect(
        () => command(guest, 'play', {
          'roundId': room.roundId,
          'type': 'play',
          'card': guestHand.first,
        }),
        throwsA(isA<RuleError>()),
      );
      expect(
        () => command(room.host, 'play', {
          'roundId': room.roundId,
          'type': 'play',
          'card': guestHand.first,
        }),
        throwsA(isA<RuleError>()),
      );
      room.disconnect(guest.id);
      expect(
        () => command(room.host, 'play', {
          'roundId': room.roundId,
          'type': 'play',
          'card': 0,
        }),
        throwsA(isA<RuleError>()),
      );
    },
  );

  test('complete game ends and another round can start without rejoining', () {
    room.join('小红');
    start();
    var moves = 0;
    while (!room.game!.finished) {
      final actor = room.member(room.game!.turnPlayer!)!;
      final hand = (room.viewFor(actor.id)['game'] as Map)['hand'] as List;
      command(actor, 'play', {
        'roundId': room.roundId,
        'type': 'play',
        'card': hand.first,
      });
      expect(++moves, lessThan(20));
    }
    expect(room.phase, RoomPhase.finished);
    expect(room.members, hasLength(2));
    final oldRound = room.roundId;
    start();
    expect(room.roundId, isNot(oldRound));
    expect(room.phase, RoomPhase.playing);
  });
}
