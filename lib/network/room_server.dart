import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/game_rules.dart';
import '../core/room.dart';

/// One authoritative, in-process host. No external account or cloud service.
class RoomServer {
  RoomServer(this.room, {this.heartbeat = const Duration(seconds: 4)});
  final Room room;
  final Duration heartbeat;
  final Map<String, _Peer> _members = {};
  final Set<_Peer> _connections = {};
  HttpServer? _http;
  bool _closed = false;
  void Function()? onChanged;
  int get port => _http!.port;

  Future<void> start({InternetAddress? address, int port = 0}) async {
    _http = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _http!.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_closed) {
      await request.response.close();
      return;
    }
    try {
      if (request.uri.path == '/room' && request.method == 'GET') {
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'no-store',
        );
        request.response.write(jsonEncode(room.summary()));
        await request.response.close();
      } else if (request.uri.path == '/play' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        if (_connections.length >= room.capacity + 12) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        socket.pingInterval = heartbeat;
        final peer = _Peer(socket);
        _connections.add(peer);
        peer.deadline = Timer(const Duration(seconds: 8), () {
          if (peer.playerId == null) socket.close(1008, 'handshake timeout');
        });
        socket.listen(
          (data) => _receive(peer, data),
          onDone: () => _disconnected(peer),
          onError: (Object error) => _disconnected(peer),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {
        /* already upgraded */
      }
    }
  }

  void _receive(_Peer peer, dynamic data) {
    if (_closed) return;
    String? requestId;
    try {
      if (data is! String || data.length > 16384) {
        throw const RuleError('bad_message', '消息格式不正确');
      }
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        throw const RuleError('bad_message', '消息格式不正确');
      }
      requestId = decoded['requestId'] is String ? decoded['requestId'] : null;
      if (peer.playerId == null) {
        _authenticate(peer, decoded);
        return;
      }
      if (decoded['type'] != 'command' ||
          requestId == null ||
          decoded['command'] is! String ||
          decoded['payload'] is! Map) {
        throw const RuleError('bad_message', '操作格式不正确');
      }
      room.execute(
        peer.playerId!,
        requestId,
        decoded['command'] as String,
        Map<String, dynamic>.from(decoded['payload'] as Map),
      );
      peer.send({'type': 'ack', 'requestId': requestId});
      _broadcast();
    } on RuleError catch (error) {
      peer.send({
        'type': 'error',
        'code': error.code,
        'message': error.message,
        'requestId': requestId,
      });
      if (peer.playerId == null) {
        unawaited(peer.socket.close(1008, error.code));
      }
    } catch (_) {
      peer.send({
        'type': 'error',
        'code': 'bad_message',
        'message': '消息格式不正确',
        'requestId': requestId,
      });
    }
  }

  void _authenticate(_Peer peer, Map<String, dynamic> message) {
    if (message['type'] != 'hello' || message['protocol'] != 1) {
      throw const RuleError('protocol', '软件协议版本不一致，请使用相同版本');
    }
    if (message['roomId'] != room.id) {
      throw const RuleError('room_gone', '原房间已经结束');
    }
    final supported = message['supportedGames'];
    final legacyTestClient =
        supported == null && room.rules.id == 'round_robin_v1';
    if (!legacyTestClient &&
        (supported is! List || !supported.contains(room.rules.id))) {
      throw const RuleError('unsupported_game', '当前版本不支持这个房间的玩法，请更新软件');
    }
    final String playerId;
    final String token;
    if (message['playerId'] != null) {
      if (message['playerId'] is! String || message['token'] is! String) {
        throw const RuleError('seat_revoked', '重连凭证失效');
      }
      playerId = message['playerId'] as String;
      token = message['token'] as String;
      room.resume(playerId, token);
    } else {
      if (message['name'] is! String) {
        throw const RuleError('name', '请输入昵称');
      }
      final member = room.join(message['name'] as String);
      playerId = member.id;
      token = member.token;
    }
    peer.deadline?.cancel();
    peer.playerId = playerId;
    final old = _members[playerId];
    // Install the new connection before closing the old one: an old onDone
    // callback must never mark a successfully resumed player offline.
    _members[playerId] = peer;
    if (old != null && old != peer) {
      old.send({'type': 'replaced', 'message': '座位已在新连接恢复'});
      unawaited(old.socket.close(1000, 'replaced'));
    }
    peer.send({
      'type': 'welcome',
      'roomId': room.id,
      'playerId': playerId,
      'token': token,
      'view': room.viewFor(playerId),
    });
    _broadcast();
  }

  void _broadcast() {
    for (final entry in _members.entries.toList()) {
      if (room.member(entry.key) == null) {
        entry.value.send({'type': 'removed', 'message': '你已离开房间或被房主移出'});
        _members.remove(entry.key);
        unawaited(entry.value.socket.close(1000, 'removed'));
      } else {
        entry.value.send({'type': 'state', 'view': room.viewFor(entry.key)});
      }
    }
    onChanged?.call();
  }

  void _disconnected(_Peer peer) {
    peer.deadline?.cancel();
    _connections.remove(peer);
    final id = peer.playerId;
    if (!_closed && id != null && _members[id] == peer) {
      _members.remove(id);
      room.disconnect(id);
      _broadcast();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final peer in _connections.toList()) {
      peer.deadline?.cancel();
      peer.send({'type': 'room_closed', 'message': '房主已关闭房间，请重新组房'});
      unawaited(peer.socket.close(1001, 'room closed'));
    }
    _members.clear();
    await _http?.close(force: true);
    _connections.clear();
  }
}

class _Peer {
  _Peer(this.socket);
  final WebSocket socket;
  String? playerId;
  Timer? deadline;
  void send(Map<String, dynamic> message) {
    if (socket.readyState != WebSocket.open) return;
    try {
      socket.add(jsonEncode(message));
    } on StateError {
      // The sink can close before readyState/onDone reflect the transition.
    } on SocketException {
      // The stream's disconnect handler will update membership.
    }
  }
}
