import 'dart:math';
import '../../core/game_rules.dart';
import 'cards.dart';
import 'patterns.dart';

enum DdzStage { bidding, playing, finished, redeal }

class DdzPlay {
  DdzPlay(this.playerId, List<int> cards, this.pattern)
    : cards = List.unmodifiable(cards);
  final String playerId;
  final List<int> cards;
  final DdzPattern pattern;
  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'cards': cards,
    ...pattern.toJson(),
  };
}

class DoudizhuState extends GameState {
  DoudizhuState({
    required List<String> players,
    required Map<String, List<int>> hands,
    required List<int> bottom,
    required this.turn,
    this.stage = DdzStage.bidding,
    this.callerId,
    this.candidateId,
    this.landlordId,
    this.finalChance = false,
    Set<String> callingPasses = const {},
    List<String> pendingBidders = const [],
    Map<String, String> bidActions = const {},
    List<Map<String, dynamic>> bidHistory = const [],
    this.multiplier = 1,
    this.lastPlay,
    this.passes = 0,
    Map<String, Map<String, dynamic>> lastActions = const {},
    Map<String, int> playCounts = const {},
    List<String> winnerIds = const [],
    Map<String, int> scoreDelta = const {},
    this.resultText,
    this.spring = false,
  }) : participants = List.unmodifiable(players),
       hands = Map.unmodifiable(
         hands.map((id, cards) => MapEntry(id, List<int>.unmodifiable(cards))),
       ),
       bottom = List.unmodifiable(bottom),
       callingPasses = Set.unmodifiable(callingPasses),
       pendingBidders = List.unmodifiable(pendingBidders),
       bidActions = Map.unmodifiable(bidActions),
       bidHistory = List.unmodifiable(bidHistory),
       lastActions = Map.unmodifiable(lastActions),
       playCounts = Map.unmodifiable(playCounts),
       winnerIds = List.unmodifiable(winnerIds),
       scoreDelta = Map.unmodifiable(scoreDelta);

  @override
  final List<String> participants;
  final Map<String, List<int>> hands;
  final List<int> bottom;
  final int turn;
  final DdzStage stage;
  final String? callerId;
  final String? candidateId;
  final String? landlordId;
  final Set<String> callingPasses;
  final List<String> pendingBidders;
  final bool finalChance;
  final Map<String, String> bidActions;
  final List<Map<String, dynamic>> bidHistory;
  final int multiplier;
  final DdzPlay? lastPlay;
  final int passes;
  final Map<String, Map<String, dynamic>> lastActions;
  final Map<String, int> playCounts;
  final List<String> winnerIds;
  final Map<String, int> scoreDelta;
  final String? resultText;
  final bool spring;
  @override
  bool get finished => stage == DdzStage.finished;
  @override
  bool get redealRequested => stage == DdzStage.redeal;
  @override
  String? get resultMessage => resultText;
  @override
  Map<String, int> get scores => scoreDelta;
  @override
  String? get winner => winnerIds.isEmpty ? null : winnerIds.first;
  @override
  String? get turnPlayer =>
      finished || redealRequested ? null : participants[turn];

  DoudizhuState copy({
    Map<String, List<int>>? hands,
    int? turn,
    DdzStage? stage,
    String? callerId,
    String? candidateId,
    String? landlordId,
    Set<String>? callingPasses,
    List<String>? pendingBidders,
    bool? finalChance,
    Map<String, String>? bidActions,
    List<Map<String, dynamic>>? bidHistory,
    int? multiplier,
    DdzPlay? lastPlay,
    bool clearLastPlay = false,
    int? passes,
    Map<String, Map<String, dynamic>>? lastActions,
    Map<String, int>? playCounts,
    List<String>? winnerIds,
    Map<String, int>? scoreDelta,
    String? resultText,
    bool? spring,
  }) => DoudizhuState(
    players: participants,
    hands: hands ?? this.hands,
    bottom: bottom,
    turn: turn ?? this.turn,
    stage: stage ?? this.stage,
    callerId: callerId ?? this.callerId,
    candidateId: candidateId ?? this.candidateId,
    landlordId: landlordId ?? this.landlordId,
    finalChance: finalChance ?? this.finalChance,
    callingPasses: callingPasses ?? this.callingPasses,
    pendingBidders: pendingBidders ?? this.pendingBidders,
    bidActions: bidActions ?? this.bidActions,
    bidHistory: bidHistory ?? this.bidHistory,
    multiplier: multiplier ?? this.multiplier,
    lastPlay: clearLastPlay ? null : lastPlay ?? this.lastPlay,
    passes: passes ?? this.passes,
    lastActions: lastActions ?? this.lastActions,
    playCounts: playCounts ?? this.playCounts,
    winnerIds: winnerIds ?? this.winnerIds,
    scoreDelta: scoreDelta ?? this.scoreDelta,
    resultText: resultText ?? this.resultText,
    spring: spring ?? this.spring,
  );
}

class DoudizhuRules implements GameRules {
  @override
  String get id => 'doudizhu_v1';
  @override
  String get title => '经典斗地主';
  @override
  int get minPlayers => 3;
  @override
  int get maxPlayers => 3;

  @override
  DoudizhuState create(List<String> players, Random random) {
    if (players.length != 3 || players.toSet().length != 3) {
      throw const RuleError('player_count', '斗地主需要三位不同的玩家');
    }
    final deck = List.generate(54, (i) => i)..shuffle(random);
    return DoudizhuState(
      players: players,
      hands: {
        for (var i = 0; i < 3; i++)
          players[i]: sortCards(deck.sublist(i * 17, i * 17 + 17)),
      },
      bottom: deck.sublist(51),
      turn: random.nextInt(3),
    );
  }

  @override
  DoudizhuState apply(
    GameState state,
    String playerId,
    Map<String, dynamic> action,
  ) {
    final game = state as DoudizhuState;
    if (game.finished || game.redealRequested) {
      throw const RuleError('finished', '本局已经结束或正在重新发牌');
    }
    if (game.turnPlayer != playerId) {
      throw const RuleError('not_your_turn', '还没有轮到你操作');
    }
    if (game.stage == DdzStage.bidding) return _bid(game, playerId, action);
    if (action['type'] == 'pass') return _pass(game, playerId);
    if (action['type'] != 'play') {
      throw const RuleError('invalid_action', '当前应当出牌或不出');
    }
    final raw = action['cards'];
    if (raw is! List ||
        raw.isEmpty ||
        raw.length > 20 ||
        raw.any((c) => c is! int)) {
      throw const RuleError('invalid_cards', '请先选择要出的牌');
    }
    final cards = raw.cast<int>();
    final pattern = classifyPlay(cards);
    if (pattern == null) {
      throw const RuleError('invalid_pattern', '这些牌不能组成有效牌型');
    }
    if (!cards.every(game.hands[playerId]!.contains)) {
      throw const RuleError('not_owned', '只能打出自己手里的牌');
    }
    if (game.lastPlay != null &&
        !beatsPattern(pattern, game.lastPlay!.pattern)) {
      throw const RuleError('too_small', '需要相同牌型且更大，或使用炸弹 / 王炸');
    }
    final hands = {...game.hands};
    hands[playerId] = game.hands[playerId]!
        .where((c) => !cards.contains(c))
        .toList();
    final play = DdzPlay(playerId, sortCards(cards), pattern);
    final next = game.copy(
      hands: hands,
      turn: (game.turn + 1) % 3,
      passes: 0,
      lastPlay: play,
      multiplier:
          game.multiplier *
          ((pattern.kind == DdzKind.bomb || pattern.kind == DdzKind.rocket)
              ? 2
              : 1),
      playCounts: {
        ...game.playCounts,
        playerId: (game.playCounts[playerId] ?? 0) + 1,
      },
      lastActions: {
        if (game.lastPlay != null) ...game.lastActions,
        playerId: {'type': 'play', 'cards': play.cards, 'name': pattern.name},
      },
    );
    return hands[playerId]!.isEmpty ? _finish(next, playerId) : next;
  }

  DoudizhuState _bid(
    DoudizhuState game,
    String playerId,
    Map<String, dynamic> action,
  ) {
    final bid = action['bid'];
    final calling = game.callerId == null;
    if (action['type'] != 'bid' ||
        (calling
            ? !['call', 'pass'].contains(bid)
            : !['rob', 'pass'].contains(bid))) {
      throw const RuleError('invalid_bid', '请按当前阶段选择叫地主、抢地主或放弃');
    }
    final text = bid == 'call'
        ? '叫地主'
        : bid == 'rob'
        ? '抢地主'
        : calling
        ? '不叫'
        : '不抢';
    var next = game.copy(
      bidActions: {...game.bidActions, playerId: text},
      bidHistory: [
        ...game.bidHistory,
        {'playerId': playerId, 'bid': bid, 'text': text},
      ],
    );
    if (calling) {
      if (bid == 'pass') {
        final passed = {...game.callingPasses, playerId};
        return next.copy(
          callingPasses: passed,
          turn: (game.turn + 1) % 3,
          stage: passed.length == 3 ? DdzStage.redeal : DdzStage.bidding,
        );
      }
      final queue = [
        for (var i = 1; i < 3; i++) game.participants[(game.turn + i) % 3],
      ].where((id) => !game.callingPasses.contains(id)).toList();
      next = next.copy(
        callerId: playerId,
        candidateId: playerId,
        pendingBidders: queue,
      );
      return queue.isEmpty
          ? _assignLandlord(next)
          : next.copy(turn: game.participants.indexOf(queue.first));
    }
    final queue = [...game.pendingBidders];
    if (queue.isEmpty || queue.first != playerId) {
      throw const RuleError('invalid_bidder', '叫抢顺序已经更新');
    }
    queue.removeAt(0);
    if (bid == 'rob') {
      next = next.copy(candidateId: playerId, multiplier: game.multiplier * 2);
    }
    if (queue.isNotEmpty) {
      return next.copy(
        pendingBidders: queue,
        turn: game.participants.indexOf(queue.first),
      );
    }
    if (!game.finalChance && next.candidateId != next.callerId) {
      return next.copy(
        pendingBidders: [next.callerId!],
        finalChance: true,
        turn: game.participants.indexOf(next.callerId!),
      );
    }
    return _assignLandlord(next.copy(pendingBidders: []));
  }

  DoudizhuState _assignLandlord(DoudizhuState game) {
    final landlord = game.candidateId!;
    return game.copy(
      stage: DdzStage.playing,
      landlordId: landlord,
      turn: game.participants.indexOf(landlord),
      pendingBidders: [],
      hands: {
        ...game.hands,
        landlord: sortCards([...game.hands[landlord]!, ...game.bottom]),
      },
    );
  }

  DoudizhuState _pass(DoudizhuState game, String playerId) {
    if (game.lastPlay == null || game.lastPlay!.playerId == playerId) {
      throw const RuleError('must_lead', '新一轮由你领出，不能不出');
    }
    final passes = game.passes + 1;
    return game.copy(
      passes: passes == 2 ? 0 : passes,
      turn: passes == 2
          ? game.participants.indexOf(game.lastPlay!.playerId)
          : (game.turn + 1) % 3,
      clearLastPlay: passes == 2,
      lastActions: {
        ...game.lastActions,
        playerId: {'type': 'pass', 'cards': <int>[], 'name': '不出'},
      },
    );
  }

  DoudizhuState _finish(
    DoudizhuState game,
    String finisher, {
    bool forfeit = false,
  }) {
    final landlordWins = finisher == game.landlordId;
    final winners = landlordWins
        ? [game.landlordId!]
        : game.participants.where((id) => id != game.landlordId).toList();
    final spring =
        !forfeit &&
        (landlordWins
            ? game.participants
                  .where((id) => id != game.landlordId)
                  .every((id) => (game.playCounts[id] ?? 0) == 0)
            : (game.playCounts[game.landlordId] ?? 0) == 1);
    final multiplier = game.multiplier * (spring ? 2 : 1);
    return game.copy(
      stage: DdzStage.finished,
      winnerIds: winners,
      spring: spring,
      multiplier: multiplier,
      scoreDelta: {
        for (final id in game.participants)
          id:
              (winners.contains(id) ? 1 : -1) *
              (id == game.landlordId ? 2 : 1) *
              multiplier,
      },
      resultText:
          '${landlordWins ? '地主' : '农民'}获胜${forfeit
              ? ' · 对方弃权'
              : spring
              ? landlordWins
                    ? ' · 春天'
                    : ' · 反春'
              : ''} · $multiplier 倍',
    );
  }

  @override
  DoudizhuState onDeparture(GameState state, String playerId) {
    final game = state as DoudizhuState;
    if (game.finished || !game.participants.contains(playerId)) return game;
    if (game.landlordId == null) {
      return game.copy(
        stage: DdzStage.finished,
        resultText: '有玩家退出，叫抢地主已取消，本局不计分。',
      );
    }
    final winner = playerId == game.landlordId
        ? game.participants.firstWhere((id) => id != playerId)
        : game.landlordId!;
    return _finish(game, winner, forfeit: true);
  }

  @override
  Map<String, dynamic> playerView(GameState state, String playerId) {
    final game = state as DoudizhuState;
    final bidding = game.stage == DdzStage.bidding;
    return {
      'gameId': id,
      'title': title,
      'stage': game.stage.name,
      'participants': game.participants,
      'turnPlayer': game.turnPlayer,
      'hand': game.hands[playerId] ?? <int>[],
      'handCounts': {
        for (final entry in game.hands.entries) entry.key: entry.value.length,
      },
      'bottomCards': game.landlordId == null ? <int>[] : game.bottom,
      'bottomCount': 3,
      'landlordId': game.landlordId,
      'bidMode': game.callerId == null ? 'calling' : 'robbing',
      'availableBids': bidding && game.turnPlayer == playerId
          ? game.callerId == null
                ? ['call', 'pass']
                : ['rob', 'pass']
          : <String>[],
      'bidHistory': game.bidHistory,
      'bidActions': game.bidActions,
      'multiplier': game.multiplier,
      'lastPlay': game.lastPlay?.toJson(),
      'lastActions': game.lastActions,
      'canPass':
          game.stage == DdzStage.playing &&
          game.turnPlayer == playerId &&
          game.lastPlay != null &&
          game.lastPlay!.playerId != playerId,
      'finished': game.finished,
      'winner': game.winner,
      'winnerIds': game.winnerIds,
      'resultText': game.resultText,
      'scoreDelta': game.scoreDelta,
      'spring': game.spring,
      'waitingNextRound': !game.participants.contains(playerId),
    };
  }
}
