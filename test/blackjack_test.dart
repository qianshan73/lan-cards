import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/core/game_rules.dart';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/blackjack.dart';

BlackjackState fixture({List<String> players = const ['a', 'b']}) =>
    BlackjackState(
      players: players,
      hands: {
        players[0]: [8, 21],
        players[1]: [2, 15],
      },
      dealer: [0, 5],
      deck: [9],
    );

void main() {
  final rules = BlackjackRules();

  test('aces adapt between one and eleven; only two cards are natural', () {
    expect(blackjackValue([0, 13, 8]), (total: 21, soft: true, natural: false));
    expect(blackjackValue([0, 8, 9]), (total: 20, soft: false, natural: false));
    expect(blackjackValue([0, 12]), (total: 21, soft: true, natural: true));
  });

  test('six players and the dealer draw from one deck without jokers', () {
    final players = List.generate(6, (i) => 'p$i');
    final game = rules.create(players, Random(23));
    expect(game.hands.values.every((cards) => cards.length == 2), isTrue);
    final dealt = [
      ...game.hands.values.expand((cards) => cards),
      ...game.dealer,
      ...game.deck,
    ];
    expect(dealt, unorderedEquals(List.generate(52, (i) => i)));
  });

  test('only your hand and dealer upcard are exposed before settlement', () {
    final game = fixture();
    final view = rules.playerView(game, 'a');
    expect(view['hand'], [8, 21]);
    expect(view['handCounts'], {'a': 2, 'b': 2});
    expect(view['dealerCards'], [0]);
    expect(view['dealerHidden'], isTrue);
    expect(view['dealerTotal'], 11);
    expect(view.containsKey('deck'), isFalse);
    expect(view.containsKey('hands'), isFalse);
    expect(rules.playerView(game, 'late')['hand'], isEmpty);
    expect(rules.playerView(game, 'late')['availableActions'], isEmpty);
  });

  test(
    'out-of-turn commands are rejected; bust advances; dealer stands on soft 17',
    () {
      final game = fixture();
      expect(
        () => rules.apply(game, 'b', {'type': 'hit'}),
        throwsA(
          isA<RuleError>().having((e) => e.code, 'code', 'not_your_turn'),
        ),
      );
      final next = rules.apply(game, 'a', {'type': 'hit'});
      expect(game.deck, [9]);
      expect(next.turnPlayer, 'b');
      final done = rules.apply(next, 'b', {'type': 'stand'});
      expect(done.dealer, [0, 5]);
      expect(done.outcomes, {
        'a': BlackjackOutcome.bust,
        'b': BlackjackOutcome.loss,
      });
      expect(done.scores, {'a': -2, 'b': -2});
      expect(rules.playerView(done, 'a')['dealerCards'], [0, 5]);
    },
  );

  test('natural wins over a three-card 21; ordinary 21 pushes', () {
    final game = BlackjackState(
      players: const ['a', 'b', 'c'],
      hands: const {
        'a': [0, 12],
        'b': [9, 16, 19],
        'c': [3, 4],
      },
      dealer: const [6, 5],
      deck: const [7],
      turn: 2,
    );
    final done = rules.apply(game, 'c', {'type': 'stand'});
    expect(done.dealer, [6, 5, 7]);
    expect(done.outcomes, {
      'a': BlackjackOutcome.natural,
      'b': BlackjackOutcome.push,
      'c': BlackjackOutcome.loss,
    });
    expect(done.scores, {'a': 3, 'b': 0, 'c': -2});
  });

  test(
    'a participant departure voids the round without revealing hidden cards',
    () {
      final game = fixture();
      expect(rules.onDeparture(game, 'late'), same(game));
      final done = rules.onDeparture(game, 'b');
      expect(done.finished, isTrue);
      expect(done.scores, isEmpty);
      expect(rules.playerView(done, 'a')['dealerHidden'], isTrue);
    },
  );

  test('room applies settlement from the initial deal exactly once', () {
    final seed = Iterable<int>.generate(512).firstWhere(
      (seed) =>
          blackjackValue(rules.create(['a', 'b'], Random(seed)).dealer).natural,
    );
    final room = Room(
      name: '21 点',
      hostName: '房主',
      rules: rules,
      capacity: 2,
      random: Random(seed),
    );
    final guest = room.join('朋友');
    final host = room.host;
    room.execute(host.id, 'ready-host', 'ready', {'ready': true});
    room.execute(guest.id, 'ready-guest', 'ready', {'ready': true});
    expect(room.execute(host.id, 'start', 'start', {}), isTrue);
    expect(room.phase, RoomPhase.finished);
    expect(room.lastResult, contains('已结算'));
    final scores = room.game!.scores;
    expect(host.points, scores[host.id]);
    expect(guest.points, scores[guest.id]);
    expect(room.execute(host.id, 'start', 'start', {}), isFalse);
    expect(guest.points, scores[guest.id]);
  });

  test('disconnect pauses 21 and resume restores the original hand', () {
    final room = Room(name: '21 点', hostName: '房主', rules: rules, capacity: 3);
    final host = room.host;
    final guest = room.join('朋友');
    room.game = fixture(players: [host.id, guest.id]);
    room.roundId = 'round-fixture';
    room.disconnect(guest.id);
    expect(room.phase, RoomPhase.paused);
    expect(
      () => room.execute(host.id, 'hit', 'play', {
        'type': 'hit',
        'roundId': room.roundId,
      }),
      throwsA(isA<RuleError>()),
    );
    room.resume(guest.id, guest.token);
    expect(room.phase, RoomPhase.playing);
    expect((room.viewFor(guest.id)['game'] as Map)['hand'], [2, 15]);
    room.execute(host.id, 'end', 'abort', {});
    expect(room.members, hasLength(2));
    expect(room.members.every((player) => player.points == 0), isTrue);
  });
}
