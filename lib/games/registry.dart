import '../core/game_rules.dart';
import 'blackjack.dart';
import 'round_robin.dart';
import 'doudizhu/rules.dart';

/// Register rules here; network and room code remain independent of game types.
final Map<String, GameRules> gameRegistry = Map.unmodifiable({
  'doudizhu_v1': DoudizhuRules(),
  blackjackGameId: BlackjackRules(),
  'round_robin_v1': RoundRobinRules(),
});

GameRules resolveGame(String id) =>
    gameRegistry[id] ??
    (throw const RuleError('unknown_game', '当前版本尚未安装这个游戏规则'));
