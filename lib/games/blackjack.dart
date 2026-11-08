import 'dart:math';

import '../core/game_rules.dart';

const blackjackGameId = 'blackjack_v1';

/// Uses the shared 0–51 card encoding, without jokers. Aces count as 1
/// unless upgrading one ace to 11 stays at or below 21.
({int total, bool soft, bool natural}) blackjackValue(List<int> hand) {
  var total = 0;
  var hasAce = false;
  for (final card in hand) {
    final rank = card % 13 + 1;
    total += min(rank, 10);
    hasAce |= rank == 1;
  }
  final soft = hasAce && total + 10 <= 21;
  if (soft) total += 10;
  return (total: total, soft: soft, natural: hand.length == 2 && total == 21);
}

enum BlackjackOutcome {
  natural('天生 21 点', 3),
  win('胜', 2),
  push('平局', 0),
  loss('负', -2),
  bust('爆牌', -2);

  const BlackjackOutcome(this.label, this.points);
  final String label;
  final int points;
}

class BlackjackState extends GameState {
  BlackjackState({
    required List<String> players,
    required Map<String, List<int>> hands,
    required List<int> dealer,
    required List<int> deck,
    this.turn = 0,
    this.voided = false,
    Map<String, BlackjackOutcome> outcomes = const {},
  }) : participants = List.unmodifiable(players),
       hands = Map.unmodifiable({
         for (final entry in hands.entries)
           entry.key: List<int>.unmodifiable(entry.value),
       }),
       dealer = List.unmodifiable(dealer),
       deck = List.unmodifiable(deck),
       outcomes = Map.unmodifiable(outcomes);

  @override
  final List<String> participants;
  final Map<String, List<int>> hands;
  final List<int> dealer;
  final List<int> deck;
  final int turn;
  final bool voided;
  final Map<String, BlackjackOutcome> outcomes;

  @override
  bool get finished => voided || outcomes.isNotEmpty;
  @override
  String? get turnPlayer => finished ? null : participants[turn];
  // Players compete against the dealer, not each other; no single winner.
  @override
  String? get winner => null;
  @override
  String? get resultMessage => voided
      ? '有参与者离开，21 点本局作废、不计分。'
      : finished
      ? '21 点已结算，可以准备下一局。'
      : null;
  @override
  Map<String, int> get scores => {
    for (final entry in outcomes.entries) entry.key: entry.value.points,
  };

  BlackjackState copy({
    Map<String, List<int>>? hands,
    List<int>? dealer,
    List<int>? deck,
    int? turn,
    bool? voided,
    Map<String, BlackjackOutcome>? outcomes,
  }) => BlackjackState(
    players: participants,
    hands: hands ?? this.hands,
    dealer: dealer ?? this.dealer,
    deck: deck ?? this.deck,
    turn: turn ?? this.turn,
    voided: voided ?? this.voided,
    outcomes: outcomes ?? this.outcomes,
  );
}

class BlackjackRules implements GameRules {
  @override
  String get id => blackjackGameId;
  @override
  String get title => '21 点';
  @override
  int get minPlayers => 2;
  @override
  int get maxPlayers => 6;

  @override
  BlackjackState create(List<String> players, Random random) {
    if (players.length < minPlayers ||
        players.length > maxPlayers ||
        players.toSet().length != players.length) {
      throw const RuleError('player_count', '21 点需要 2–6 位不同的玩家');
    }
    final deck = List.generate(52, (i) => i)..shuffle(random);
    final hands = {for (final player in players) player: <int>[]};
    final dealer = <int>[];
    for (var deal = 0; deal < 2; deal++) {
      for (final player in players) {
        hands[player]!.add(deck.removeLast());
      }
      dealer.add(deck.removeLast());
    }
    final game = BlackjackState(
      players: players,
      hands: hands,
      dealer: dealer,
      deck: deck,
    );
    return blackjackValue(dealer).natural ? _settle(game) : _advance(game, 0);
  }

  @override
  BlackjackState apply(
    GameState state,
    String playerId,
    Map<String, dynamic> action,
  ) {
    final game = state as BlackjackState;
    if (game.finished) throw const RuleError('finished', '本局已结束');
    if (game.turnPlayer != playerId) {
      throw const RuleError('not_your_turn', '还没有轮到你');
    }
    switch (action['type']) {
      case 'hit':
        final deck = game.deck.toList();
        final hand = [...game.hands[playerId]!, deck.removeLast()];
        final next = game.copy(
          hands: {...game.hands, playerId: hand},
          deck: deck,
        );
        return blackjackValue(hand).total >= 21
            ? _advance(next, game.turn + 1)
            : next;
      case 'stand':
        return _advance(game, game.turn + 1);
      default:
        throw const RuleError('invalid_action', '请选择要牌或停牌');
    }
  }

  BlackjackState _advance(BlackjackState game, int start) {
    for (var i = start; i < game.participants.length; i++) {
      if (blackjackValue(game.hands[game.participants[i]]!).total < 21) {
        return game.copy(turn: i);
      }
    }
    return _settle(game);
  }

  BlackjackState _settle(BlackjackState game) {
    final dealer = game.dealer.toList();
    final deck = game.deck.toList();
    while (blackjackValue(dealer).total < 17) {
      dealer.add(deck.removeLast());
    }
    final house = blackjackValue(dealer);
    BlackjackOutcome compare(List<int> cards) {
      final hand = blackjackValue(cards);
      if (hand.total > 21) return BlackjackOutcome.bust;
      if (house.natural) {
        return hand.natural ? BlackjackOutcome.push : BlackjackOutcome.loss;
      }
      if (hand.natural) return BlackjackOutcome.natural;
      if (house.total > 21 || hand.total > house.total) {
        return BlackjackOutcome.win;
      }
      return hand.total == house.total
          ? BlackjackOutcome.push
          : BlackjackOutcome.loss;
    }

    return game.copy(
      dealer: dealer,
      deck: deck,
      outcomes: {
        for (final entry in game.hands.entries) entry.key: compare(entry.value),
      },
    );
  }

  @override
  BlackjackState onDeparture(GameState state, String playerId) {
    final game = state as BlackjackState;
    if (game.finished || !game.participants.contains(playerId)) return game;
    return game.copy(voided: true);
  }

  @override
  Map<String, dynamic> playerView(GameState state, String playerId) {
    final game = state as BlackjackState;
    final hand = game.hands[playerId] ?? const <int>[];
    final reveal = game.outcomes.isNotEmpty;
    final dealer = reveal ? game.dealer : [game.dealer.first];
    return {
      'gameId': id,
      'title': title,
      'participants': game.participants,
      'turnPlayer': game.turnPlayer,
      'hand': hand,
      'total': blackjackValue(hand).total,
      'natural': blackjackValue(hand).natural,
      'handCounts': {
        for (final entry in game.hands.entries) entry.key: entry.value.length,
      },
      'dealerCards': dealer,
      'dealerTotal': blackjackValue(dealer).total,
      'dealerHidden': !reveal,
      'availableActions': game.turnPlayer == playerId
          ? ['hit', 'stand']
          : <String>[],
      'finished': game.finished,
      'voided': game.voided,
      'outcomes': {
        for (final entry in game.outcomes.entries)
          entry.key: {'label': entry.value.label, 'points': entry.value.points},
      },
      'waitingNextRound': !game.participants.contains(playerId),
    };
  }
}
