import 'dart:math';

import '../core/game_rules.dart';

/// A deliberately small game that exercises dealing, privacy, turns and replay.
/// It is not Dou Dizhu or Blackjack. First player to empty their hand wins.
class RoundRobinRules implements GameRules {
  @override
  String get id => 'round_robin_v1';
  @override
  String get title => '轮流出牌 · 框架测试';
  @override
  int get minPlayers => 2;
  @override
  int get maxPlayers => 6;

  @override
  TestGameState create(List<String> players, Random random) {
    if (players.length < minPlayers || players.length > maxPlayers) {
      throw const RuleError('player_count', '测试游戏需要 2–6 位玩家');
    }
    final deck = List.generate(52, (i) => i)..shuffle(random);
    return TestGameState(
      participants: List.unmodifiable(players),
      hands: {
        for (var i = 0; i < players.length; i++)
          players[i]: List.unmodifiable(deck.sublist(i * 5, i * 5 + 5)),
      },
      turn: 0,
      table: const [],
    );
  }

  @override
  TestGameState apply(
    GameState state,
    String playerId,
    Map<String, dynamic> action,
  ) {
    final game = state as TestGameState;
    if (game.finished) {
      throw const RuleError('finished', '本局已经结束');
    }
    if (game.turnPlayer != playerId) {
      throw const RuleError('not_your_turn', '还没有轮到你出牌');
    }
    final card = action['card'];
    if (action['type'] != 'play' ||
        card is! int ||
        !game.hands[playerId]!.contains(card)) {
      throw const RuleError('invalid_card', '请选择自己手里的一张牌');
    }
    final hands = {...game.hands};
    hands[playerId] = List.unmodifiable(
      game.hands[playerId]!.where((value) => value != card),
    );
    return TestGameState(
      participants: game.participants,
      hands: hands,
      turn: (game.turn + 1) % game.participants.length,
      table: [
        ...game.table,
        {'playerId': playerId, 'card': card},
      ],
      winner: hands[playerId]!.isEmpty ? playerId : null,
    );
  }

  @override
  TestGameState onDeparture(GameState state, String playerId) {
    final game = state as TestGameState;
    if (!game.participants.contains(playerId) || game.finished) return game;
    final next = [...game.participants]..remove(playerId);
    // Advance to the next surviving player, without skipping an unrelated turn.
    var nextTurn = game.turnPlayer;
    if (nextTurn == playerId && next.isNotEmpty) {
      nextTurn = game.participants[(game.turn + 1) % game.participants.length];
    }
    return TestGameState(
      participants: next,
      hands: {...game.hands}..remove(playerId),
      turn: next.isEmpty ? 0 : max(0, next.indexOf(nextTurn!)),
      table: game.table,
      winner: next.length == 1 ? next.first : null,
    );
  }

  @override
  Map<String, dynamic> playerView(GameState state, String playerId) {
    final game = state as TestGameState;
    return {
      'gameId': id,
      'title': title,
      'participants': game.participants,
      'turnPlayer': game.turnPlayer,
      'hand': game.hands[playerId] ?? <int>[],
      'handCounts': {
        for (final entry in game.hands.entries) entry.key: entry.value.length,
      },
      'table': game.table,
      'finished': game.finished,
      'winner': game.winner,
      'waitingNextRound': !game.participants.contains(playerId),
    };
  }
}

class TestGameState implements GameState {
  TestGameState({
    required List<String> participants,
    required Map<String, List<int>> hands,
    required this.turn,
    required List<Map<String, dynamic>> table,
    this.winner,
  }) : participants = List.unmodifiable(participants),
       hands = Map.unmodifiable(hands),
       table = List.unmodifiable(table);

  @override
  final List<String> participants;
  final Map<String, List<int>> hands;
  final int turn;
  final List<Map<String, dynamic>> table;
  @override
  final String? winner;
  @override
  bool get finished => winner != null;
  @override
  String? get turnPlayer => finished || participants.isEmpty
      ? null
      : participants[turn % participants.length];
}
