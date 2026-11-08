import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/core/game_rules.dart';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/doudizhu/cards.dart';
import 'package:lan_cards/games/doudizhu/patterns.dart';
import 'package:lan_cards/games/doudizhu/rules.dart';

List<int> cards(List<int> ranks) {
  final counts = <int, int>{};
  return [
    for (final r in ranks)
      r >= 16
          ? r == 16
                ? 52
                : 53
          : ((counts.update(r, (n) => n + 1, ifAbsent: () => 0)) * 13 +
                (r == 14
                    ? 0
                    : r == 15
                    ? 1
                    : r - 1)),
  ];
}

DoudizhuState playing({
  List<int>? a,
  List<int>? b,
  List<int>? c,
  int turn = 0,
  Map<String, int> counts = const {},
  int multiplier = 1,
}) => DoudizhuState(
  players: const ['a', 'b', 'c'],
  hands: {
    'a': cards(a ?? [3, 4]),
    'b': cards(b ?? [5, 6]),
    'c': cards(c ?? [7, 8]),
  },
  bottom: const [],
  turn: turn,
  stage: DdzStage.playing,
  landlordId: 'a',
  playCounts: counts,
  multiplier: multiplier,
);

void main() {
  final rules = DoudizhuRules();
  DoudizhuState bid(DoudizhuState g, String choice) =>
      rules.apply(g, g.turnPlayer!, {'type': 'bid', 'bid': choice});

  group('all supported patterns', () {
    final examples = <DdzKind, List<int>>{
      DdzKind.single: [15],
      DdzKind.pair: [14, 14],
      DdzKind.triple: [8, 8, 8],
      DdzKind.tripleSingle: [7, 7, 7, 3],
      DdzKind.triplePair: [9, 9, 9, 4, 4],
      DdzKind.straight: [10, 11, 12, 13, 14],
      DdzKind.pairRun: [3, 3, 4, 4, 5, 5],
      DdzKind.tripleRun: [3, 3, 3, 4, 4, 4],
      DdzKind.airplaneSingle: [3, 3, 3, 4, 4, 4, 8, 9],
      DdzKind.airplanePair: [3, 3, 3, 4, 4, 4, 8, 8, 9, 9],
      DdzKind.fourSingles: [6, 6, 6, 6, 9, 9],
      DdzKind.fourPairs: [6, 6, 6, 6, 9, 9, 10, 10],
      DdzKind.bomb: [15, 15, 15, 15],
      DdzKind.rocket: [16, 17],
    };
    for (final entry in examples.entries) {
      test('recognizes ${entry.key.name}', () {
        expect(classifyPlay(cards(entry.value))?.kind, entry.key);
      });
    }
    test('single-wing airplane allows a pair but not both jokers', () {
      expect(
        classifyPlay(cards([3, 3, 3, 4, 4, 4, 8, 8]))?.kind,
        DdzKind.airplaneSingle,
      );
      expect(classifyPlay(cards([3, 3, 3, 4, 4, 4, 16, 17])), isNull);
    });
    test(
      'rejects duplicate IDs, invalid cards and disconnected or 2-containing runs',
      () {
        for (final hand in [
          <int>[],
          [0, 0],
          [-1],
          [54],
          cards([3, 4, 5, 6]),
          cards([3, 4, 5, 6, 8]),
          cards([11, 12, 13, 14, 15]),
          cards([13, 13, 13, 14, 14, 14, 15, 15, 15]),
        ]) {
          expect(classifyPlay(hand), isNull, reason: '$hand');
        }
      },
    );
    test('four cards of body rank cannot become an airplane wing', () {
      expect(classifyPlay(cards([3, 3, 3, 3, 4, 4, 4, 8])), isNull);
      expect(classifyPlay(cards([3, 3, 3, 3, 4, 4, 4, 4])), isNull);
    });
    test(
      'rocket beats bombs; bombs beat normal types; equal plays never beat',
      () {
        expect(beats(cards([16, 17]), cards([15, 15, 15, 15])), true);
        expect(beats(cards([3, 3, 3, 3]), cards([14, 14])), true);
        expect(beats(cards([4, 4, 4, 4]), cards([3, 3, 3, 3])), true);
        expect(beats(cards([15, 15, 15, 15]), cards([16, 17])), false);
        expect(beats(cards([5, 5]), cards([5, 5])), false);
        expect(beats(cards([5, 5]), cards([4])), false);
        expect(beats(cards([4, 5, 6, 7, 8, 9]), cards([3, 4, 5, 6, 7])), false);
      },
    );
    test('rank encoding is 3...A,2,small joker,big joker', () {
      expect(
        sortCards(cards([16, 3, 15, 14, 17]), descending: false).map(rankOf),
        [3, 14, 15, 16, 17],
      );
    });
  });

  group('local hint shortlist', () {
    test(
      'keeps ordinary replies before bombs and avoids spending trumps first',
      () {
        final hand = cards([4, 4, 4, 4, 7, 8, 16, 17]);
        final original = List<int>.of(hand);
        final previous = cards([3]);
        final hints = suggestPlays(hand, previous);
        expect(hints.first.map(rankOf), [7]);
        expect(
          hints.map((play) => classifyPlay(play)!.kind).skip(hints.length - 2),
          [DdzKind.bomb, DdzKind.rocket],
        );
        expect(hints.every((play) => beats(play, previous)), isTrue);
        expect(suggestPlays(hand.reversed.toList(), previous), hints);
        expect(hand, original);
      },
    );

    test(
      'only one hint per rank multiset, including a pair as single wings',
      () {
        final hand = cards([4, 4, 4, 5, 5, 5, 8, 8, 9, 9]);
        final previous = cards([3, 3, 3, 4, 4, 4, 6, 7]);
        final hints = suggestPlays(hand, previous);
        expect(hints, hasLength(3));
        expect(
          hints.map((play) => play.map(rankOf).join(',')).toSet(),
          hasLength(3),
        );
        expect(hints.every((play) => beats(play, previous)), isTrue);
      },
    );

    test('many wings do not crowd bombs and rocket out of the shortlist', () {
      final hand = cards([
        4,
        4,
        4,
        5,
        5,
        5,
        7,
        7,
        7,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
      ]);
      final previous = cards([3, 3, 3, 4, 4, 4, 6, 6]);
      final hints = suggestPlays(hand, previous);
      expect(hints, hasLength(12));
      expect(
        hints.every(
          (play) => play.every(hand.contains) && beats(play, previous),
        ),
        isTrue,
      );
      expect(classifyPlay(hints[10])?.kind, DdzKind.bomb);
      expect(classifyPlay(hints.last)?.kind, DdzKind.rocket);
    });

    test(
      'finishes immediately when possible and never suggests against rocket',
      () {
        final hand = cards([4, 5, 6, 7, 8]);
        expect(suggestPlays(hand, null).first, sortCards(hand));
        expect(suggestPlays(hand, cards([16, 17])), isEmpty);
        expect(suggestPlays([2, 2], null), isEmpty);
      },
    );
  });

  group('calling and robbing', () {
    test('deal is 17/17/17 plus 3 unique hidden bottom cards', () {
      final game = rules.create(['a', 'b', 'c'], Random(7));
      expect(game.hands.values.every((h) => h.length == 17), true);
      expect({
        ...game.hands.values.expand((h) => h),
        ...game.bottom,
      }, hasLength(54));
      for (final p in game.participants) {
        final view = rules.playerView(game, p);
        expect(view['bottomCards'], isEmpty);
        expect(view.containsKey('hands'), false);
        expect(
          view['availableBids'],
          game.turnPlayer == p ? ['call', 'pass'] : isEmpty,
        );
      }
    });
    test('caller gets final rob opportunity, each rob doubles', () {
      var game = rules.create(['a', 'b', 'c'], Random(7));
      final caller = game.turnPlayer!;
      game = bid(game, 'call');
      game = bid(game, 'rob');
      game = bid(game, 'pass');
      expect(game.turnPlayer, caller);
      expect(game.finalChance, true);
      game = bid(game, 'rob');
      expect(game.landlordId, caller);
      expect(game.multiplier, 4);
      expect(game.stage, DdzStage.playing);
      expect(game.hands[caller], hasLength(20));
      expect(game.turnPlayer, caller);
      expect(rules.playerView(game, 'b')['bottomCards'], hasLength(3));
    });
    test('both opponents decline, no unnecessary final rob', () {
      var game = rules.create(['a', 'b', 'c'], Random(9));
      final caller = game.turnPlayer;
      game = bid(bid(bid(game, 'call'), 'pass'), 'pass');
      expect(game.landlordId, caller);
      expect(game.multiplier, 1);
    });
    test('a player who declined calling cannot later rob', () {
      var game = rules.create(['a', 'b', 'c'], Random(1)).copy(turn: 0);
      game = bid(game, 'pass');
      game = bid(game, 'call');
      expect(game.pendingBidders, ['c']);
      game = bid(game, 'rob');
      expect(game.pendingBidders, ['b']);
      game = bid(game, 'pass');
      expect(game.landlordId, 'c');
    });
    test('all-pass redeals at room boundary with a new round nonce', () {
      final room = Room(
        name: '斗地主',
        hostName: 'a',
        rules: rules,
        capacity: 3,
        random: Random(17),
      );
      room.join('b');
      room.join('c');
      var command = 0;
      for (final m in room.members) {
        room.execute(m.id, '${command++}', 'ready', {'ready': true});
      }
      room.execute(room.host.id, '${command++}', 'start', {});
      final nonce = room.roundId;
      final old = (room.game as DoudizhuState).hands.values
          .expand((h) => h)
          .toList();
      for (var i = 0; i < 3; i++) {
        room.execute(room.game!.turnPlayer!, '${command++}', 'play', {
          'roundId': room.roundId,
          'type': 'bid',
          'bid': 'pass',
        });
      }
      expect(room.roundId, isNot(nonce));
      expect(room.phase, RoomPhase.playing);
      expect((room.game as DoudizhuState).stage, DdzStage.bidding);
      expect(
        (room.game as DoudizhuState).hands.values.expand((h) => h).toList(),
        isNot(old),
      );
      expect(room.lastResult, contains('重新洗牌'));
    });
    test('wrong-turn and wrong-stage bids are rejected', () {
      final game = rules.create(['a', 'b', 'c'], Random(7));
      final other = game.participants.firstWhere((p) => p != game.turnPlayer);
      expect(
        () => rules.apply(game, other, {'type': 'bid', 'bid': 'call'}),
        throwsA(isA<RuleError>()),
      );
      expect(() => bid(game, 'rob'), throwsA(isA<RuleError>()));
      expect(
        () => rules.apply(playing(), 'a', {'type': 'bid', 'bid': 'call'}),
        throwsA(isA<RuleError>()),
      );
    });
  });

  group('playing, teams and results', () {
    test(
      'cannot pass on lead; two passes reset trick to last winning player',
      () {
        var game = playing();
        expect(
          () => rules.apply(game, 'a', {'type': 'pass'}),
          throwsA(isA<RuleError>()),
        );
        game = rules.apply(game, 'a', {
          'type': 'play',
          'cards': cards([3]),
        });
        game = rules.apply(game, 'b', {'type': 'pass'});
        game = rules.apply(game, 'c', {'type': 'pass'});
        expect(game.turnPlayer, 'a');
        expect(game.lastPlay, isNull);
        expect(rules.playerView(game, 'a')['canPass'], false);
      },
    );
    test('checks card ownership, pattern size and turn on host', () {
      final game = playing(a: [8, 9], b: [3, 4]);
      expect(
        () => rules.apply(game, 'a', {
          'type': 'play',
          'cards': cards([3]),
        }),
        throwsA(isA<RuleError>()),
      );
      expect(
        () => rules.apply(game, 'a', {
          'type': 'play',
          'cards': [
            cards([8]).first,
            cards([8]).first,
          ],
        }),
        throwsA(isA<RuleError>()),
      );
      final next = rules.apply(game, 'a', {
        'type': 'play',
        'cards': cards([8]),
      });
      expect(
        () => rules.apply(next, 'b', {
          'type': 'play',
          'cards': cards([3]),
        }),
        throwsA(isA<RuleError>()),
      );
    });
    test('landlord spring is zero-sum with two winning shares', () {
      final game = rules.apply(playing(a: [3]), 'a', {
        'type': 'play',
        'cards': cards([3]),
      });
      expect(game.finished, true);
      expect(game.spring, true);
      expect(game.winnerIds, ['a']);
      expect(game.scoreDelta, {'a': 4, 'b': -2, 'c': -2});
    });
    test('farmer win includes both farmers and reverse spring', () {
      final game = rules.apply(
        playing(b: [5], turn: 1, counts: {'a': 1}),
        'b',
        {
          'type': 'play',
          'cards': cards([5]),
        },
      );
      expect(game.winnerIds, ['b', 'c']);
      expect(game.spring, true);
      expect(game.scoreDelta, {'a': -4, 'b': 2, 'c': 2});
    });
    test('bomb doubles but four-with-two is not a bomb', () {
      final bomb = rules.apply(playing(a: [3, 3, 3, 3, 4]), 'a', {
        'type': 'play',
        'cards': cards([3, 3, 3, 3]),
      });
      expect(bomb.multiplier, 2);
      final attachment = rules.apply(playing(a: [3, 3, 3, 3, 4, 5, 6]), 'a', {
        'type': 'play',
        'cards': cards([3, 3, 3, 3, 4, 5]),
      });
      expect(attachment.multiplier, 1);
    });
    test(
      'departure during bidding voids hand; playing departure forfeits team',
      () {
        final cancelled = rules.onDeparture(
          rules.create(['a', 'b', 'c'], Random(7)),
          'b',
        );
        expect(cancelled.finished, true);
        expect(cancelled.scoreDelta, isEmpty);
        final landlordLeaves = rules.onDeparture(playing(), 'a');
        expect(landlordLeaves.winnerIds, ['b', 'c']);
        expect(landlordLeaves.spring, false);
        expect(rules.onDeparture(playing(), 'b').winnerIds, ['a']);
      },
    );
    test('points are applied once and abort never changes points', () {
      final room = Room(name: '斗地主', hostName: 'a', rules: rules, capacity: 3);
      final b = room.join('b');
      final c = room.join('c');
      room.game = DoudizhuState(
        players: [room.host.id, b.id, c.id],
        hands: {
          room.host.id: cards([3]),
          b.id: cards([4]),
          c.id: cards([5]),
        },
        bottom: [],
        turn: 0,
        stage: DdzStage.playing,
        landlordId: room.host.id,
      );
      room.roundId = 'fixture';
      final payload = {
        'roundId': 'fixture',
        'type': 'play',
        'cards': cards([3]),
      };
      room.execute(room.host.id, 'win', 'play', payload);
      room.execute(room.host.id, 'win', 'play', payload);
      expect(room.host.points, 4);
      expect(b.points, -2);
      expect(c.points, -2);
      room.execute(room.host.id, 'abort', 'abort', {});
      expect(room.host.points, 4);
    });
  });

  for (var seed = 0; seed < 20; seed++) {
    test('legal suggestions complete a real deal, seed $seed', () {
      var game = rules.create(['a', 'b', 'c'], Random(seed));
      game = bid(game, 'call');
      while (game.stage == DdzStage.bidding) {
        game = bid(game, 'pass');
      }
      var steps = 0;
      while (!game.finished) {
        final actor = game.turnPlayer!;
        final hand = game.hands[actor]!;
        final suggestion = suggestPlay(hand, game.lastPlay?.cards);
        if (suggestion.isNotEmpty) {
          expect(suggestion.every(hand.contains), true);
          expect(classifyPlay(suggestion), isNotNull);
          if (game.lastPlay != null) {
            expect(beats(suggestion, game.lastPlay!.cards), true);
          }
        }
        game = rules.apply(
          game,
          actor,
          suggestion.isEmpty
              ? {'type': 'pass'}
              : {'type': 'play', 'cards': suggestion},
        );
        expect(++steps, lessThan(200));
      }
      expect(game.scoreDelta.values.reduce((a, b) => a + b), 0);
      expect(game.winnerIds.length, anyOf(1, 2));
    });
  }
}
