import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/game_rules.dart';
import '../core/ids.dart';

class ResumeTicket {
  const ResumeTicket({
    required this.roomId,
    required this.playerId,
    required this.token,
    required this.host,
    required this.port,
    required this.roomName,
    this.isHost = false,
  });
  final String roomId;
  final String playerId;
  final String token;
  final String host;
  final int port;
  final String roomName;
  final bool isHost;

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'playerId': playerId,
    'token': token,
    'host': host,
    'port': port,
    'roomName': roomName,
    'isHost': isHost,
  };
  factory ResumeTicket.fromJson(Map<String, dynamic> json) => ResumeTicket(
    roomId: json['roomId'] as String,
    playerId: json['playerId'] as String,
    token: json['token'] as String,
    host: json['host'] as String,
    port: json['port'] as int,
    roomName: json['roomName'] as String,
    isHost: json['isHost'] == true,
  );
  ResumeTicket at(String host, int port) => ResumeTicket(
    roomId: roomId,
    playerId: playerId,
    token: token,
    host: host,
    port: port,
    roomName: roomName,
    isHost: isHost,
  );
}

class RoomClient {
  final StreamController<Map<String, dynamic>> _events =
      StreamController.broadcast(sync: true);
  Stream<Map<String, dynamic>> get events => _events.stream;
  WebSocket? _socket;
  final Map<String, Completer<void>> _pending = {};
  int _generation = 0;
  bool connected = false;
  bool _disposed = false;
  ResumeTicket? ticket;
  Map<String, dynamic>? view;

  Future<ResumeTicket> connect({
    required String host,
    required int port,
    required String roomId,
    String name = '朋友',
    ResumeTicket? resume,
  }) async {
    final generation = ++_generation;
    connected = false;
    final previous = _socket;
    _socket = null;
    if (previous != null) unawaited(previous.close());
    var expired = false;
    final opening =
        WebSocket.connect(
          Uri(scheme: 'ws', host: host, port: port, path: '/play').toString(),
        ).then((socket) {
          // A timeout does not cancel the underlying OS connection attempt.
          // Close late arrivals so failed retries cannot leave orphan connections.
          if (expired || generation != _generation || _disposed) {
            unawaited(socket.close());
          }
          return socket;
        });
    final socket = await opening.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        expired = true;
        throw const RuleError('timeout', '连接暂未建立，请确认房主仍在原网络中');
      },
    );
    if (generation != _generation || _disposed) {
      await socket.close();
      throw const RuleError('cancelled', '连接已取消');
    }
    _socket = socket;
    socket.pingInterval = const Duration(seconds: 4);
    final welcome = Completer<ResumeTicket>();
    void ended() {
      if (generation != _generation || _disposed) return;
      connected = false;
      if (!welcome.isCompleted) {
        welcome.completeError(const RuleError('disconnected', '房间连接已中断'));
      }
      _failPending(const RuleError('disconnected', '连接已中断，请等待重连'));
      _emit({'type': 'disconnected'});
    }

    socket.listen(
      (dynamic data) {
        if (generation != _generation || _disposed) return;
        try {
          if (data is! String || data.length > 262144) return;
          final message = jsonDecode(data) as Map<String, dynamic>;
          switch (message['type']) {
            case 'welcome':
              view = Map<String, dynamic>.from(message['view'] as Map);
              ticket = ResumeTicket(
                roomId: message['roomId'] as String,
                playerId: message['playerId'] as String,
                token: message['token'] as String,
                host: host,
                port: port,
                roomName: view!['name'] as String,
                isHost: resume?.isHost ?? false,
              );
              connected = true;
              if (!welcome.isCompleted) welcome.complete(ticket);
            case 'state':
              view = Map<String, dynamic>.from(message['view'] as Map);
            case 'ack':
              _pending.remove(message['requestId'])?.complete();
            case 'error':
              final error = RuleError(
                message['code'] as String,
                message['message'] as String,
              );
              final pending = _pending.remove(message['requestId']);
              if (pending != null) pending.completeError(error);
              if (!welcome.isCompleted) welcome.completeError(error);
            case 'room_closed':
            case 'removed':
            case 'replaced':
              connected = false;
              ticket = null;
              _failPending(const RuleError('room_gone', '当前连接已结束'));
          }
          _emit(message);
        } catch (_) {
          /* ignore malformed remote frames, never execute them */
        }
      },
      onDone: ended,
      onError: (Object error) => ended(),
    );
    try {
      socket.add(
        jsonEncode({
          'type': 'hello',
          'protocol': 1,
          'roomId': roomId,
          'name': name,
          if (resume != null) ...{
            'playerId': resume.playerId,
            'token': resume.token,
          },
        }),
      );
      return await welcome.future.timeout(const Duration(seconds: 6));
    } catch (_) {
      if (generation == _generation) {
        ++_generation;
        connected = false;
        _socket = null;
      }
      unawaited(socket.close());
      rethrow;
    }
  }

  Future<void> command(
    String command, [
    Map<String, dynamic> payload = const {},
  ]) {
    if (!connected || _socket == null) {
      return Future.error(const RuleError('disconnected', '请等待连接恢复'));
    }
    final requestId = newId();
    final completer = Completer<void>();
    _pending[requestId] = completer;
    try {
      _socket!.add(
        jsonEncode({
          'type': 'command',
          'requestId': requestId,
          'command': command,
          'payload': payload,
        }),
      );
    } on StateError {
      _pending.remove(requestId);
      connected = false;
      completer.completeError(const RuleError('disconnected', '连接已中断，请等待重连'));
      _emit({'type': 'disconnected'});
    } on SocketException {
      _pending.remove(requestId);
      connected = false;
      completer.completeError(const RuleError('disconnected', '连接已中断，请等待重连'));
      _emit({'type': 'disconnected'});
    }
    return completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () {
        _pending.remove(requestId);
        throw const RuleError('timeout', '尚未收到确认，请等待状态同步后再操作');
      },
    );
  }

  /// Disconnect transport only; deliberately does NOT release the seat.
  Future<void> disconnect() async {
    ++_generation;
    connected = false;
    _failPending(const RuleError('disconnected', '连接已断开'));
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  void _failPending(RuleError error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  void _emit(Map<String, dynamic> event) {
    if (!_disposed) _events.add(event);
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _events.close();
  }
}
