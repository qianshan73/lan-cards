import 'dart:collection';
import 'dart:math';

import 'game_rules.dart';
import 'ids.dart';

enum RoomPhase { lobby, playing, paused, finished }

class Member {
  Member({
    required this.id,
    required this.token,
    required this.name,
    required this.seat,
    this.online = true,
  });
  final String id;
  final String token;
  final String name;
  final int seat;
  bool online;
  bool ready = false;
  final Set<String> _seen = <String>{};
  final Queue<String> _order = Queue();

  void remember(String id) {
    _seen.add(id);
    _order.add(id);
    if (_order.length > 256) _seen.remove(_order.removeFirst());
  }

  Map<String, dynamic> publicView(String hostId) => {
    'id': id,
    'name': name,
    'seat': seat,
    'online': online,
    'ready': ready,
    'isHost': id == hostId,
  };
}

class Room {
  Room({
    required String name,
    required String hostName,
    required this.rules,
    this.capacity = 6,
    Random? random,
  }) : id = newId(),
       name = _name(name, '朋友的房间'),
       random = random ?? Random.secure() {
    if (capacity < rules.minPlayers || capacity > rules.maxPlayers) {
      throw const RuleError('capacity', '座位数量不符合游戏规则');
    }
    seats = List<Member?>.filled(capacity, null);
    host = _add(hostName);
  }

  final String id;
  final String name;
  final GameRules rules;
  final int capacity;
  final Random random;
  late final List<Member?> seats;
  late final Member host;
  GameState? game;
  String? roundId;
  String? lastResult;
  int revision = 0;

  List<Member> get members => seats.whereType<Member>().toList();
  Member? member(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  RoomPhase get phase {
    if (game == null) return RoomPhase.lobby;
    if (game!.finished) return RoomPhase.finished;
    if (game!.participants.any((id) => member(id)?.online != true)) {
      return RoomPhase.paused;
    }
    return RoomPhase.playing;
  }

  Member _add(String name) {
    final seat = seats.indexOf(null);
    if (seat < 0) throw const RuleError('room_full', '座位已满，离线玩家仍保留座位');
    final m = Member(
      id: newId(),
      token: newId(32),
      name: _name(name, '朋友'),
      seat: seat,
    );
    seats[seat] = m;
    revision++;
    return m;
  }

  Member join(String name) => _add(name);

  Member resume(String playerId, String token) {
    final m = member(playerId);
    if (m == null || !_constantEquals(m.token, token)) {
      throw const RuleError('seat_revoked', '原座位已释放，或重连凭证失效');
    }
    if (!m.online) {
      m.online = true;
      revision++;
    }
    return m;
  }

  void disconnect(String playerId) {
    final m = member(playerId);
    if (m != null && m.online) {
      m.online = false;
      revision++;
    }
  }

  /// All commands are serialized by the host event loop, never by the UI.
  /// Returns false for an already applied command (idempotent retry).
  bool execute(
    String actorId,
    String commandId,
    String command,
    Map<String, dynamic> payload,
  ) {
    final actor = member(actorId);
    if (actor == null || !actor.online) {
      throw const RuleError('not_member', '请先恢复房间连接');
    }
    if (commandId.isEmpty || commandId.length > 128) {
      throw const RuleError('command_id', '操作编号无效');
    }
    if (actor._seen.contains(commandId)) return false;
    switch (command) {
      case 'ready':
        if (game != null && !game!.finished) {
          throw const RuleError('round_active', '本局结束后再准备');
        }
        actor.ready = payload['ready'] == true;
      case 'start':
        _requireHost(actorId);
        if (game != null && !game!.finished) {
          throw const RuleError('round_active', '请先结束当前这一局');
        }
        final players = members;
        if (players.length < rules.minPlayers) {
          throw RuleError('player_count', '至少需要 ${rules.minPlayers} 位玩家');
        }
        if (players.any((m) => !m.online)) {
          throw const RuleError('offline_seat', '有玩家离线，请等待恢复或手动移出座位');
        }
        if (players.any((m) => !m.ready)) {
          throw const RuleError('not_ready', '请等待所有玩家准备');
        }
        game = rules.create(players.map((m) => m.id).toList(), random);
        roundId = newId();
        lastResult = null;
        for (final m in players) {
          m.ready = false;
        }
      case 'play':
        if (payload['roundId'] != roundId || game == null) {
          throw const RuleError('stale_round', '牌局已更新，请使用当前手牌');
        }
        if (phase != RoomPhase.playing) {
          throw const RuleError('paused', '当前不能出牌，请等待对局恢复');
        }
        game = rules.apply(game!, actorId, payload);
        if (game!.finished) {
          lastResult = '${member(game!.winner!)?.name ?? '玩家'}率先出完手牌';
          for (final m in members) {
            m.ready = false;
          }
        }
      case 'abort':
        _requireHost(actorId);
        if (game == null) {
          throw const RuleError('no_round', '当前没有正在进行的牌局');
        }
        game = null;
        roundId = null;
        lastResult = '房主已结束本局，本局作废、不计分。所有座位保留。';
        for (final m in members) {
          m.ready = false;
        }
      case 'kick':
        _requireHost(actorId);
        final targetId = payload['playerId'];
        if (targetId is! String ||
            member(targetId) == null ||
            targetId == host.id) {
          throw const RuleError('invalid_target', '请选择其他玩家');
        }
        _remove(targetId);
      case 'leave':
        if (actorId == host.id) {
          throw const RuleError('host_leave', '房主离开请关闭房间');
        }
        _remove(actorId);
      default:
        throw const RuleError('unknown_command', '不支持的操作');
    }
    actor.remember(commandId);
    revision++;
    return true;
  }

  void _remove(String playerId) {
    final m = member(playerId)!;
    if (game != null &&
        !game!.finished &&
        game!.participants.contains(playerId)) {
      game = rules.onDeparture(game!, playerId);
      if (game!.finished) {
        lastResult = '有玩家离开，本局结束，剩余玩家获胜。';
        for (final m in members) {
          m.ready = false;
        }
      }
    }
    seats[m.seat] = null;
  }

  void _requireHost(String id) {
    if (id != host.id) throw const RuleError('host_only', '只有房主可以执行此操作');
  }

  Map<String, dynamic> summary() => {
    'protocol': 1,
    'roomId': id,
    'name': name,
    'gameId': rules.id,
    'gameTitle': rules.title,
    'capacity': capacity,
    'occupied': members.length,
    'online': members.where((m) => m.online).length,
    'phase': phase.name,
  };

  Map<String, dynamic> viewFor(String playerId) {
    if (member(playerId) == null) {
      throw const RuleError('not_member', '你已不在这个房间');
    }
    return {
      ...summary(),
      'revision': revision,
      'you': playerId,
      'hostId': host.id,
      'roundId': roundId,
      'lastResult': lastResult,
      'seats': seats.map((m) => m?.publicView(host.id)).toList(),
      'offlineParticipants':
          game?.participants
              .where((id) => member(id)?.online != true)
              .toList() ??
          <String>[],
      'game': game == null ? null : rules.playerView(game!, playerId),
    };
  }

  static String _name(String input, String fallback) {
    final value = input.trim();
    if (value.isEmpty) return fallback;
    return String.fromCharCodes(value.runes.take(24));
  }

  static bool _constantEquals(String a, String b) {
    var result = a.length ^ b.length;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ (i < b.length ? b.codeUnitAt(i) : 0);
    }
    return result == 0;
  }
}
