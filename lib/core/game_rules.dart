import 'dart:math';

class RuleError implements Exception {
  const RuleError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

abstract class GameState {
  List<String> get participants;
  String? get turnPlayer;
  bool get finished;
  String? get winner;
  bool get redealRequested => false;
  String? get resultMessage => null;
  Map<String, int> get scores => const {};
}

/// Pure rules: no sockets, widgets, timers, or device APIs.
abstract class GameRules {
  String get id;
  String get title;
  int get minPlayers;
  int get maxPlayers;
  GameState create(List<String> players, Random random);
  GameState apply(
    GameState state,
    String playerId,
    Map<String, dynamic> action,
  );
  GameState onDeparture(GameState state, String playerId);
  Map<String, dynamic> playerView(GameState state, String playerId);
}
