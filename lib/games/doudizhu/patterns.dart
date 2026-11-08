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

// Pick a canonical suit assignment for each rank multiset. A pair can be
// two single wings, but choosing different suits is not a different hint.
Iterable<List<int>> _singleWings(
  List<List<int>> pool,
  int count, [
  int offset = 0,
]) sync* {
  if (count == 0) {
    yield const <int>[];
    return;
  }
  for (var i = offset; i < pool.length; i++) {
    final group = pool[i];
    for (var n = 1; n <= 2 && n <= group.length && n <= count; n++) {
      for (final tail in _singleWings(pool, count - n, i + 1)) {
        yield [...group.take(n), ...tail];
      }
    }
  }
}

Iterable<List<int>> _candidatesFor(
  Map<int, List<int>> groups,
  DdzKind kind, [
  int chainLength = 1,
]) sync* {
  switch (kind) {
    case DdzKind.single:
      for (final group in groups.values) {
        yield [group.first];
      }
    case DdzKind.pair:
    case DdzKind.triple:
      final n = kind == DdzKind.pair ? 2 : 3;
      for (final group in groups.values.where((g) => g.length >= n)) {
        yield group.take(n).toList();
      }
    case DdzKind.tripleSingle:
    case DdzKind.triplePair:
      final wingCount = kind == DdzKind.triplePair ? 2 : 1;
      for (final rank in groups.keys.where((r) => groups[r]!.length >= 3)) {
        for (final wing in groups.entries.where(
          (e) => e.key != rank && e.value.length >= wingCount,
        )) {
          yield [...groups[rank]!.take(3), ...wing.value.take(wingCount)];
        }
      }
    case DdzKind.straight:
      yield* _runs(groups, 1, chainLength);
    case DdzKind.pairRun:
      yield* _runs(groups, 2, chainLength);
    case DdzKind.tripleRun:
      yield* _runs(groups, 3, chainLength);
    case DdzKind.airplaneSingle:
    case DdzKind.airplanePair:
      for (final body in _runs(groups, 3, chainLength)) {
        final bodyRanks = body.map(rankOf).toSet();
        if (kind == DdzKind.airplaneSingle) {
          final pool = [
            for (final rank in groups.keys)
              if (!bodyRanks.contains(rank)) groups[rank]!,
          ];
          for (final wings in _singleWings(pool, chainLength)) {
            yield [...body, ...wings];
          }
        } else {
          final pool = groups.keys
              .where((r) => !bodyRanks.contains(r) && groups[r]!.length >= 2)
              .toList();
          for (final ranks in _choose(pool, chainLength)) {
            yield [...body, for (final rank in ranks) ...groups[rank]!.take(2)];
          }
        }
      }
    case DdzKind.fourSingles:
    case DdzKind.fourPairs:
      for (final body in groups.entries.where((e) => e.value.length == 4)) {
        if (kind == DdzKind.fourSingles) {
          final pool = [
            for (final rank in groups.keys)
              if (rank != body.key) groups[rank]!,
          ];
          for (final wings in _singleWings(pool, 2)) {
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
      yield* groups.values.where((group) => group.length == 4);
    case DdzKind.rocket:
      if (groups.containsKey(16) && groups.containsKey(17)) yield [53, 52];
  }
}

Iterable<List<int>> _ordinaryCandidates(
  Map<int, List<int>> groups,
  int handLength,
  DdzPattern? previous,
) sync* {
  if (previous != null) {
    if (previous.kind != DdzKind.bomb && previous.kind != DdzKind.rocket) {
      yield* _candidatesFor(groups, previous.kind, previous.chainLength);
    }
    return;
  }
  for (final kind in const [
    DdzKind.single,
    DdzKind.pair,
    DdzKind.triple,
    DdzKind.tripleSingle,
    DdzKind.triplePair,
    DdzKind.fourSingles,
    DdzKind.fourPairs,
  ]) {
    yield* _candidatesFor(groups, kind);
  }
  for (final (kind, cardsPerRank, minimum) in const [
    (DdzKind.straight, 1, 5),
    (DdzKind.pairRun, 2, 3),
    (DdzKind.tripleRun, 3, 2),
    (DdzKind.airplaneSingle, 4, 2),
    (DdzKind.airplanePair, 5, 2),
  ]) {
    for (var n = minimum; n <= 12 && n * cardsPerRank <= handLength; n++) {
      yield* _candidatesFor(groups, kind, n);
    }
  }
}

/// A bounded, deterministic shortlist for the local hint button. Takes only
/// the player's hand and public last play; the host still validates commands.
List<List<int>> suggestPlays(List<int> hand, List<int>? previousCards) {
  if (hand.isEmpty ||
      hand.length > 20 ||
      hand.toSet().length != hand.length ||
      hand.any((card) => card < 0 || card > 53)) {
    return [];
  }
  final following = previousCards != null && previousCards.isNotEmpty;
  final previous = classifyPlay(previousCards ?? const <int>[]);
  if (following && (previous == null || previous.kind == DdzKind.rocket)) {
    return [];
  }
  final groups = _groups(hand);
  final seen = <String>{};
  final protectedRanks = {
    for (final group in groups.entries)
      if (group.value.length == 4) group.key,
    if (groups.containsKey(16) && groups.containsKey(17)) ...{16, 17},
  };

  bool legal(DdzPattern? pattern) =>
      pattern != null && (previous == null || beatsPattern(pattern, previous));
  String rankKey(List<int> sorted) => sorted.map(rankOf).join(',');

  // Going out immediately is better than conserving a high card or trump.
  final finish = legal(classifyPlay(hand)) ? sortCards(hand) : null;
  if (finish != null) seen.add(rankKey(finish));

  final ordinary =
      <({List<int> cards, DdzPattern pattern, int cost, int order})>[];
  for (final candidate in _ordinaryCandidates(groups, hand.length, previous)) {
    final pattern = classifyPlay(candidate);
    if (pattern == null || !legal(pattern)) continue;
    final sorted = sortCards(candidate);
    if (!seen.add(rankKey(sorted))) continue;
    ordinary.add((
      cards: sorted,
      pattern: pattern,
      cost: sorted.map(rankOf).toSet().intersection(protectedRanks).length,
      order: ordinary.length,
    ));
  }
  ordinary.sort((a, b) {
    final byCost = a.cost.compareTo(b.cost);
    if (byCost != 0) return byCost;
    if (!following) {
      final byLength = b.cards.length.compareTo(a.cards.length);
      if (byLength != 0) return byLength;
    }
    final byRank = a.pattern.mainRank.compareTo(b.pattern.mainRank);
    return byRank != 0 ? byRank : a.order.compareTo(b.order);
  });

  // Reserve shortlist slots for bombs and rocket, even when there are many
  // different legal wings. They stay behind ordinary plays in the cycle.
  final trumps = <List<int>>[];
  for (final kind in [DdzKind.bomb, DdzKind.rocket]) {
    for (final candidate in _candidatesFor(groups, kind)) {
      if (!legal(classifyPlay(candidate))) continue;
      final sorted = sortCards(candidate);
      if (seen.add(rankKey(sorted))) trumps.add(sorted);
    }
  }
  const maxHints = 12;
  return [
    ?finish,
    ...ordinary
        .take(maxHints - trumps.length - (finish == null ? 0 : 1))
        .map((entry) => entry.cards),
    ...trumps,
  ];
}

/// First recommendation for callers that do not need the full shortlist.
List<int> suggestPlay(List<int> hand, List<int>? previousCards) =>
    suggestPlays(hand, previousCards).firstOrNull ?? [];
