/// The original 52-card encoding is preserved; 52/53 are the two jokers.
int rankOf(int card) {
  if (card < 0 || card > 53) throw RangeError.range(card, 0, 53);
  if (card >= 52) return card == 52 ? 16 : 17;
  final rank = card % 13;
  return rank == 0
      ? 14
      : rank == 1
      ? 15
      : rank + 1;
}

List<int> sortCards(Iterable<int> cards, {bool descending = true}) {
  final result = cards.toList()
    ..sort((a, b) {
      final difference = rankOf(a).compareTo(rankOf(b));
      return difference == 0 ? a.compareTo(b) : difference;
    });
  return descending ? result.reversed.toList() : result;
}

String rankName(int rank) => switch (rank) {
  11 => 'J',
  12 => 'Q',
  13 => 'K',
  14 => 'A',
  15 => '2',
  16 => '小王',
  17 => '大王',
  _ => '$rank',
};
