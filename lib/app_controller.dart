import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'core/game_rules.dart';
import 'core/room.dart';
import 'games/registry.dart';
import 'network/discovery_service.dart';
import 'network/room_client.dart';
import 'network/room_server.dart';
import 'storage/local_store.dart';

enum AppPage { home, search, room, reconnect }

class AppController extends ChangeNotifier {
  AppController({
    LocalStore? store,
    DiscoveryService? discovery,
    RoomClient? client,
  }) : store = store ?? const LocalStore(),
       discovery = discovery ?? DiscoveryService(),
       client =
           client ?? RoomClient(supportedGames: gameRegistry.keys.toSet()) {
    this.discovery.addListener(_changed);
    _events = this.client.events.listen(_onEvent);
  }

  final LocalStore store;
  final DiscoveryService discovery;
  final RoomClient client;
  late final StreamSubscription<Map<String, dynamic>> _events;
  RoomServer? server;
  AppPage page = AppPage.home;
  String nickname = '朋友';
  String? message;
  bool busy = false;
  bool _disposed = false;
  bool _retrying = false;
  bool _publishing = false;
  int _session = 0;
  Timer? _retry;
  ResumeTicket? _ticket;
  Map<String, dynamic>? get view => client.view;
  bool get isHost => server != null;
  bool get connected => client.connected;
  List<FoundRoom> get foundRooms => discovery.rooms;

  Future<void> initialize() async {
    busy = true;
    try {
      nickname = await store.loadNickname();
      _ticket = await store.loadTicket();
      if (_ticket?.isHost == true) {
        _ticket = null;
        await store.clearTicket();
        message = '上次由你创建的房间已结束，可以重新开房。';
      } else if (_ticket != null) {
        page = AppPage.reconnect;
        _beginRetry();
      }
    } catch (_) {
      message = '本地恢复信息读取失败，你仍可以创建或加入新房间。';
    } finally {
      busy = false;
    }
    _changed();
  }

  Future<void> setNickname(String value) async {
    nickname = value.trim().isEmpty ? '朋友' : value.trim();
    await store.saveNickname(nickname);
    _changed();
  }

  Future<void> createRoom(
    String name,
    int seats, {
    String gameId = 'round_robin_v1',
  }) async {
    if (busy || hasRecovery || server != null || _disposed) return;
    _session++;
    busy = true;
    message = null;
    _stopRetry();
    _changed();
    try {
      // A fresh host process always gets a fresh room ID. No fake recovery.
      final room = Room(
        name: name,
        hostName: nickname,
        rules: resolveGame(gameId),
        capacity: seats,
      );
      final host = RoomServer(room);
      await host.start();
      server = host;
      final resume = ResumeTicket(
        roomId: room.id,
        playerId: room.host.id,
        token: room.host.token,
        host: '127.0.0.1',
        port: host.port,
        roomName: room.name,
        isHost: true,
      );
      await _connect(resume.host, resume.port, room.id, resume: resume);
      await retryPublication();
    } catch (error) {
      await server?.close();
      server = null;
      message = _describe(error, '创建房间失败，请检查网络权限后重试');
      page = AppPage.home;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> search() async {
    page = AppPage.search;
    message = null;
    _changed();
    await discovery.startSearch();
    _changed();
  }

  Future<void> join(FoundRoom room) async {
    if (busy || _disposed) return;
    if (server != null || (_ticket != null && _ticket!.roomId != room.id)) {
      message = '请先离开原房间，再加入其他房间。';
      _changed();
      return;
    }
    _session++;
    busy = true;
    message = null;
    _stopRetry();
    _changed();
    try {
      final previous = _ticket;
      await _connect(
        room.host,
        room.port,
        room.id,
        resume: previous?.roomId == room.id ? previous : null,
      );
    } catch (error) {
      message = _describe(error, '暂时无法加入，请刷新房间或检查网络');
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> joinAddress(String input) async {
    try {
      final uri = Uri.parse(input.contains('://') ? input : 'http://$input');
      if (uri.host.isEmpty || !uri.hasPort || uri.userInfo.isNotEmpty) {
        throw const RuleError('address', '请输入房主显示的完整地址，例如 192.168.1.2:54321');
      }
      final found = await discovery.probe(uri.host, uri.port);
      if (found == null) {
        throw const RuleError('address', '没有连接到房间，请检查地址和网络');
      }
      await join(found);
    } catch (error) {
      message = _describe(error, '地址格式不正确，请检查后重试');
      _changed();
    }
  }

  Future<void> _connect(
    String host,
    int port,
    String roomId, {
    ResumeTicket? resume,
  }) async {
    final generation = _session;
    final ticket = await client.connect(
      host: host,
      port: port,
      roomId: roomId,
      name: nickname,
      resume: resume,
    );
    if (generation != _session || _disposed) return;
    _ticket = ticket;
    try {
      await store.saveTicket(ticket);
    } catch (_) {
      message = '本局可以继续，但恢复凭证未能保存，关闭 App 后可能无法找回座位。';
    }
    if (generation != _session || _disposed) return;
    page = AppPage.room;
    _stopRetry();
    unawaited(discovery.stopSearch());
    if (!client.connected) _beginRetry();
    _changed();
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'disconnected':
        if (_ticket != null) {
          page = client.view == null ? AppPage.reconnect : AppPage.room;
          _beginRetry();
        }
      case 'removed':
      case 'room_closed':
      case 'replaced':
        _session++;
        _stopRetry();
        _ticket = null;
        unawaited(store.clearTicket());
        page = AppPage.home;
        message = event['message'] as String?;
      case 'state':
      case 'welcome':
        // The host only publishes the resumed player as online together with
        // an authoritative view; no optimistic local continuation is allowed.
        break;
    }
    _changed();
  }

  void _beginRetry() {
    if (_ticket == null || _disposed) return;
    _retry ??= Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_tryResume());
    });
    unawaited(_tryResume());
  }

  Future<void> _tryResume() async {
    final generation = _session;
    final ticket = _ticket;
    if (_retrying || ticket == null || client.connected || _disposed) return;
    _retrying = true;
    try {
      try {
        await _connect(ticket.host, ticket.port, ticket.roomId, resume: ticket);
      } on RuleError catch (error) {
        if (generation != _session || _disposed) return;
        if (error.code == 'seat_revoked' ||
            error.code == 'room_gone' ||
            error.code == 'protocol' ||
            error.code == 'unsupported_game') {
          await forgetRecovery();
          message = error.message;
          _changed();
          return;
        }
        rethrow;
      }
    } catch (_) {
      if (generation != _session || _disposed) return;
      // Addresses can change after reconnecting Wi-Fi; search by stable room ID.
      await discovery.startSearch();
      if (_ticket == null || _disposed || generation != _session) return;
      for (final found in discovery.rooms) {
        if (found.id == ticket.roomId) {
          _ticket = ticket.at(found.host, found.port);
          break;
        }
      }
    } finally {
      _retrying = false;
      _changed();
    }
  }

  /// Invoked on foreground resume, never treats a background transition as leave.
  void onForeground() {
    if (!connected && _ticket != null) _beginRetry();
    if (page == AppPage.search) unawaited(discovery.startSearch());
    if (server != null && !discovery.published) {
      // iOS may reject the first Bonjour call before permission is answered.
      // Give the permission transition time to settle, then retry publication.
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 600), () async {
          if (!_disposed && server != null && !discovery.published) {
            await retryPublication();
          }
        }),
      );
    }
    _changed();
  }

  Future<void> retryPublication() async {
    final host = server;
    if (host == null || _publishing || _disposed) return;
    _publishing = true;
    try {
      await discovery.publish(host.room.id, host.port);
      if (server != host || _disposed) {
        await discovery.unpublish();
      } else {
        message = null;
      }
    } catch (_) {
      if (!_disposed && server == host) {
        message = '房间已创建，但暂时无法被搜索到。允许本地网络权限后，可点击“重新发布房间”。';
      }
    } finally {
      _publishing = false;
      _changed();
    }
  }

  Future<void> command(
    String command, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (busy) return;
    busy = true;
    message = null;
    _changed();
    try {
      await client.command(command, payload);
    } catch (error) {
      message = _describe(error, '操作未完成，请检查连接');
    } finally {
      busy = false;
      _changed();
    }
  }

  /// Returning to home retains the ticket; explicit leaving releases a seat.
  void home() {
    page = AppPage.home;
    if (_ticket == null) unawaited(discovery.stopSearch());
    _changed();
  }

  void retryRecovery() {
    if (_ticket != null) {
      page = connected ? AppPage.room : AppPage.reconnect;
      if (!connected) _beginRetry();
      _changed();
    }
  }

  bool get hasRecovery => _ticket != null;
  String get recoveryRoomName => _ticket?.roomName ?? '原房间';

  Future<void> forgetRecovery() async {
    _session++;
    _stopRetry();
    _ticket = null;
    await client.disconnect();
    await store.clearTicket();
    page = AppPage.home;
    _changed();
  }

  Future<void> leave() async {
    _stopRetry();
    if (server != null) {
      await discovery.unpublish();
      await server!.close();
      server = null;
    } else if (connected) {
      try {
        await client.command('leave');
      } catch (_) {
        /* connection gone */
      }
    }
    await forgetRecovery();
    message = null;
    _changed();
  }

  Future<List<String>> hostAddresses() async {
    if (server == null) return [];
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback) '${a.address}:${server!.port}',
    ];
  }

  void _stopRetry() {
    _retry?.cancel();
    _retry = null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  String _describe(Object error, String fallback) =>
      error is RuleError ? error.message : fallback;

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    _session++;
    _stopRetry();
    discovery.removeListener(_changed);
    await _events.cancel();
    await client.dispose();
    await server?.close();
    await discovery.shutdown();
  }
}
