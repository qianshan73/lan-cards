import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/app_controller.dart';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/round_robin.dart';
import 'package:lan_cards/network/discovery_service.dart';
import 'package:lan_cards/network/room_client.dart';
import 'package:lan_cards/network/room_server.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'helpers.dart';

Future<void> eventually(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test(
    'publication failure leaves host playable and diagnostics survive commands',
    () async {
      final backend = FakeDiscoveryBackend()
        ..registerError = nsd.NsdError(
          nsd.ErrorCause.securityIssue,
          'private-native-data',
        );
      final discovery = DiscoveryService(backend: backend);
      final app = AppController(store: MemoryStore(), discovery: discovery);
      addTearDown(app.shutdown);
      await app.initialize();
      await app.createRoom('诊断测试', 3, gameId: 'doudizhu_v1');
      expect(app.connected, true);
      expect(app.page, AppPage.room);
      expect(discovery.diagnostics.publication, DiscoveryStage.failed);
      final host = app.server;
      await app.command('ready', {'ready': true});
      expect(app.message, isNull);
      expect(
        discovery.diagnostics.publicationFailure,
        DiscoveryFailure.permission,
      );
      backend.registerError = null;
      await app.retryPublication();
      expect(app.server, same(host));
      expect(discovery.published, true);
      expect(discovery.diagnostics.publicationFailure, isNull);
    },
  );

  test(
    'host creation is single-room; explicit leave releases all resources',
    () async {
      final store = MemoryStore();
      final app = AppController(store: store, discovery: FakeDiscovery());
      addTearDown(app.shutdown);
      await app.initialize();
      await app.createRoom('朋友的牌桌', 4);
      expect(app.connected, true);
      expect(app.page, AppPage.room);
      expect(store.ticket!.isHost, true);
      final original = app.server;
      await app.createRoom('不应该新建', 4);
      expect(app.server, same(original));
      await app.leave();
      expect(app.server, isNull);
      expect(store.ticket, isNull);
      expect(app.hasRecovery, false);
      expect(app.page, AppPage.home);
    },
  );

  test('host cold start does not pretend to resurrect a dead room', () async {
    final store = MemoryStore()
      ..ticket = const ResumeTicket(
        roomId: 'old-room',
        playerId: 'old-host',
        token: 'old-secret',
        host: '127.0.0.1',
        port: 54321,
        roomName: '旧房间',
        isHost: true,
      );
    final app = AppController(store: store, discovery: FakeDiscovery());
    addTearDown(app.shutdown);
    await app.initialize();
    expect(app.hasRecovery, false);
    expect(store.ticket, isNull);
    expect(app.page, AppPage.home);
    expect(app.message, contains('房间已结束'));
  });

  test('guest app cold start automatically restores persisted seat', () async {
    final room = Room(name: '原房间', hostName: '房主', rules: RoundRobinRules());
    final server = RoomServer(room);
    await server.start();
    addTearDown(server.close);
    final firstClient = RoomClient();
    final ticket = await firstClient.connect(
      host: '127.0.0.1',
      port: server.port,
      roomId: room.id,
      name: '小红',
    );
    await firstClient.dispose();
    await eventually(() => room.member(ticket.playerId)?.online == false);
    final store = MemoryStore()..ticket = ticket;
    final app = AppController(store: store, discovery: FakeDiscovery());
    addTearDown(app.shutdown);
    await app.initialize();
    await eventually(() => app.connected && app.page == AppPage.room);
    expect(app.view!['you'], ticket.playerId);
    expect(room.members, hasLength(2));
  });

  test(
    'revoked recovery clears itself, does not repeatedly retry a kicked seat',
    () async {
      final room = Room(name: '原房间', hostName: '房主', rules: RoundRobinRules());
      final server = RoomServer(room);
      await server.start();
      addTearDown(server.close);
      final store = MemoryStore()
        ..ticket = ResumeTicket(
          roomId: room.id,
          playerId: 'no-such-player',
          token: 'wrong',
          host: '127.0.0.1',
          port: server.port,
          roomName: room.name,
        );
      final app = AppController(store: store, discovery: FakeDiscovery());
      addTearDown(app.shutdown);
      await app.initialize();
      await eventually(() => !app.hasRecovery);
      expect(app.page, AppPage.home);
    },
  );

  test('cannot join another room while an original seat is reserved', () async {
    final app = AppController(store: MemoryStore(), discovery: FakeDiscovery());
    addTearDown(app.shutdown);
    await app.initialize();
    await app.createRoom('第一个房间', 4);
    final id = app.view!['roomId'];
    await app.join(
      const FoundRoom(
        host: '127.0.0.1',
        port: 1,
        info: {
          'roomId': 'another',
          'name': '另一个房间',
          'occupied': 1,
          'capacity': 4,
        },
      ),
    );
    expect(app.view!['roomId'], id);
    expect(app.message, contains('先离开'));
  });
}
