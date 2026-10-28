import 'cards.dart';

enum DdzKind {
  single,
  pair,
  triple,
  tripleSingle,
  triplePair,
  straight,
  pairRun,
  tripleRun,
  airplaneSingle,
  airplanePair,
  fourSingles,
  fourPairs,
  bomb,
  rocket,
}

class DdzPattern {
  const DdzPattern(
    this.kind,
    this.length,
    this.mainRank, [
    this.chainLength = 1,
  ]);
  final DdzKind kind;
  final int length;
  final int mainRank;
  final int chainLength;
  String get name => switch (kind) {
    DdzKind.single => '单张',
    DdzKind.pair => '对子',
    DdzKind.triple => '三张',
    DdzKind.tripleSingle => '三带一',
    DdzKind.triplePair => '三带一对',
    DdzKind.straight => '顺子',
    DdzKind.pairRun => '连对',
    DdzKind.tripleRun => '飞机',
    DdzKind.airplaneSingle => '飞机带单',
    DdzKind.airplanePair => '飞机带对',
    DdzKind.fourSingles => '四带两单',
    DdzKind.fourPairs => '四带两对',
    DdzKind.bomb => '炸弹',
    DdzKind.rocket => '王炸',
  };
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'name': name,
    'length': length,
    'mainRank': mainRank,
    'chainLength': chainLength,
  };
}

Map<int, List<int>> _groups(Iterable<int> cards) {
  final result = <int, List<int>>{};
  for (final card in sortCards(cards, descending: false)) {
    result.putIfAbsent(rankOf(card), () => []).add(card);
  }
  return result;
}

bool _consecutive(List<int> ranks) {
  if (ranks.isEmpty || ranks.last > 14) return false;
  for (var i = 1; i < ranks.length; i++) {
    if (ranks[i] != ranks[i - 1] + 1) return false;
  }
  return true;
}

/// Recognizes a documented common three-player ruleset, without wild cards.
/// Wings may contain a pair as two singles, but never both jokers, triples,
/// a bomb, or any rank already used by the airplane body.
DdzPattern? classifyPlay(List<int> cards) {
  if (cards.isEmpty ||
      cards.length > 20 ||
      cards.toSet().length != cards.length ||
      cards.any((c) => c < 0 || c > 53)) {
    return null;
  }
  final groups = _groups(cards);
  final ranks = groups.keys.toList();
  final counts = groups.map((rank, values) => MapEntry(rank, values.length));
  final n = cards.length;
  if (n == 2 && cards.contains(52) && cards.contains(53)) {
    return const DdzPattern(DdzKind.rocket, 2, 17);
  }
  if (groups.length == 1) {
    final kind = switch (n) {
      1 => DdzKind.single,
      2 => DdzKind.pair,
      3 => DdzKind.triple,
      4 => DdzKind.bomb,
      _ => null,
    };
    if (kind != null) return DdzPattern(kind, n, ranks.first);
  }
  int? triple;
  for (final rank in ranks) {
    if (counts[rank] == 3) triple = rank;
  }
  if (n == 4 && triple != null) {
    return DdzPattern(DdzKind.tripleSingle, n, triple);
  }
  if (n == 5 && triple != null && counts.values.contains(2)) {
    return DdzPattern(DdzKind.triplePair, n, triple);
  }
  if (_consecutive(ranks)) {
    if (n >= 5 && counts.values.every((c) => c == 1)) {
      return DdzPattern(DdzKind.straight, n, ranks.last, ranks.length);
    }
    if (ranks.length >= 3 && counts.values.every((c) => c == 2)) {
      return DdzPattern(DdzKind.pairRun, n, ranks.last, ranks.length);
    }
    if (ranks.length >= 2 && counts.values.every((c) => c == 3)) {
      return DdzPattern(DdzKind.tripleRun, n, ranks.last, ranks.length);
    }
  }
  for (final entry in counts.entries.where((e) => e.value == 4)) {
    final remaining = {...counts}..remove(entry.key);
    if (n == 6 && !(remaining.containsKey(16) && remaining.containsKey(17))) {
      return DdzPattern(DdzKind.fourSingles, n, entry.key);
    }
    if (n == 8 &&
        remaining.length == 2 &&
        remaining.values.every((c) => c == 2)) {
      return DdzPattern(DdzKind.fourPairs, n, entry.key);
    }
  }
  for (final pairWings in [false, true]) {
    final unit = pairWings ? 5 : 4;
    if (n % unit != 0 || n ~/ unit < 2) continue;
    final k = n ~/ unit;
    for (var start = 3; start + k - 1 <= 14; start++) {
      final body = List.generate(k, (i) => start + i);
      if (!body.every((r) => counts[r] == 3)) continue;
      final wings = {...counts}..removeWhere((r, _) => body.contains(r));
      if (pairWings) {
        if (wings.length != k || !wings.values.every((c) => c == 2)) continue;
      } else {
        if (wings.values.fold<int>(0, (a, b) => a + b) != k ||
            wings.values.any((c) => c > 2) ||
            (wings.containsKey(16) && wings.containsKey(17))) {
          continue;
        }
      }
      return DdzPattern(
        pairWings ? DdzKind.airplanePair : DdzKind.airplaneSingle,
        n,
        body.last,
        k,
      );
    }
  }
  return null;
}

bool beatsPattern(DdzPattern challenger, DdzPattern previous) {
  if (previous.kind == DdzKind.rocket) return false;
  if (challenger.kind == DdzKind.rocket) return true;
  if (challenger.kind == DdzKind.bomb && previous.kind != DdzKind.bomb) {
    return true;
  }
  return challenger.kind == previous.kind &&
      challenger.length == previous.length &&
      challenger.chainLength == previous.chainLength &&
      challenger.mainRank > previous.mainRank;
}

bool beats(List<int> challenger, List<int> previous) {
  final a = classifyPlay(challenger);
  final b = classifyPlay(previous);
  return a != null && b != null && beatsPattern(a, b);
}

Iterable<List<int>> _choose(
  List<int> items,
  int count, [
  int offset = 0,
]) sync* {
  if (count == 0) {
    yield <int>[];
    return;
  }
  for (var i = offset; i <= items.length - count; i++) {
    for (final tail in _choose(items, count - 1, i + 1)) {
      yield [items[i], ...tail];
    }
  }
}

Iterable<List<int>> _runs(
  Map<int, List<int>> groups,
  int repeat,
  int length,
) sync* {
  for (var start = 3; start + length - 1 <= 14; start++) {
    final ranks = List.generate(length, (i) => start + i);
    if (ranks.every((r) => (groups[r]?.length ?? 0) >= repeat)) {
      yield [for (final rank in ranks) ...groups[rank]!.take(repeat)];
    }
  }
}

Iterable<List<int>> _sameTypeCandidates(
  List<int> hand,
  DdzPattern previous,
) sync* {
  final groups = _groups(hand);
  final triples = groups.keys.where((r) => groups[r]!.length >= 3).toList();
  switch (previous.kind) {
    case DdzKind.single:
      for (final group in groups.values) {
        yield [group.first];
      }
    case DdzKind.pair:
    case DdzKind.triple:
      final n = previous.kind == DdzKind.pair ? 2 : 3;
      for (final group in groups.values.where((g) => g.length >= n)) {
        yield group.take(n).toList();
      }
    case DdzKind.tripleSingle:
    case DdzKind.triplePair:
      final wingCount = previous.kind == DdzKind.triplePair ? 2 : 1;
      for (final rank in triples) {
        for (final wing in groups.entries.where(
          (e) => e.key != rank && e.value.length >= wingCount,
        )) {
          yield [...groups[rank]!.take(3), ...wing.value.take(wingCount)];
        }
      }
    case DdzKind.straight:
      yield* _runs(groups, 1, previous.chainLength);
    case DdzKind.pairRun:
      yield* _runs(groups, 2, previous.chainLength);
    case DdzKind.tripleRun:
      yield* _runs(groups, 3, previous.chainLength);
    case DdzKind.airplaneSingle:
    case DdzKind.airplanePair:
      for (final body in _runs(groups, 3, previous.chainLength)) {
        final bodyRanks = body.map(rankOf).toSet();
        if (previous.kind == DdzKind.airplaneSingle) {
          final pool = sortCards(
            hand.where((c) => !bodyRanks.contains(rankOf(c))),
            descending: false,
          );
          for (final wings in _choose(pool, previous.chainLength)) {
            yield [...body, ...wings];
          }
        } else {
          final pool = groups.keys
              .where((r) => !bodyRanks.contains(r) && groups[r]!.length >= 2)
              .toList();
          for (final ranks in _choose(pool, previous.chainLength)) {
            yield [...body, for (final rank in ranks) ...groups[rank]!.take(2)];
          }
        }
      }
    case DdzKind.fourSingles:
    case DdzKind.fourPairs:
      for (final body in groups.entries.where((e) => e.value.length == 4)) {
        if (previous.kind == DdzKind.fourSingles) {
          final pool = hand.where((c) => rankOf(c) != body.key).toList();
          for (final wings in _choose(pool, 2)) {
            yield [...body.value, ...wings];
          }
        } else {
          final pool = groups.keys
              .where((r) => r != body.key && groups[r]!.length >= 2)
              .toList();
          for (final ranks in _choose(pool, 2)) {
            yield [
              ...body.value,
              for (final rank in ranks) ...groups[rank]!.take(2),
            ];
          }
        }
      }
    case DdzKind.bomb:
    case DdzKind.rocket:
      break;
  }
}

/// A deterministic legal suggestion, not an auto-player. Never mutates hand.
List<int> suggestPlay(List<int> hand, List<int>? previousCards) {
  if (hand.isEmpty) return [];
  if (previousCards == null || previousCards.isEmpty) {
    if (classifyPlay(hand) != null) return sortCards(hand);
    final groups = _groups(hand);
    for (var length = 12; length >= 5; length--) {
      for (final run in _runs(groups, 1, length)) {
        return sortCards(run);
      }
    }
    for (var length = 6; length >= 3; length--) {
      for (final run in _runs(groups, 2, length)) {
        return sortCards(run);
      }
    }
    return [sortCards(hand, descending: false).first];
  }
  final previous = classifyPlay(previousCards);
  if (previous == null || previous.kind == DdzKind.rocket) return [];
  for (final candidate in _sameTypeCandidates(hand, previous)) {
    final pattern = classifyPlay(candidate);
    if (pattern != null && beatsPattern(pattern, previous)) {
      return sortCards(candidate);
    }
  }
  for (final group in _groups(hand).values.where((g) => g.length == 4)) {
    final pattern = classifyPlay(group)!;
    if (beatsPattern(pattern, previous)) return sortCards(group);
  }
  return hand.contains(52) && hand.contains(53) ? [53, 52] : [];
}
