import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/app_controller.dart';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/round_robin.dart';
import 'package:lan_cards/ui/app.dart';
import 'helpers.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(320, 568),
    const Size(844, 390),
  ]) {
    testWidgets('home and room fit $size without layout exceptions', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(
        store: MemoryStore(),
        discovery: FakeDiscovery(),
      );
      await tester.pumpWidget(LanCardsApp(controller: app, showIntro: false));
      await tester.pumpAndSettle();
      expect(find.text('创建房间'), findsOneWidget);
      expect(find.text('搜索房间'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final room = Room(
        name: '朋友的房间',
        hostName: '小明',
        rules: RoundRobinRules(),
      );
      final guest = room.join('小红');
      room.join('一位昵称比较长的朋友');
      for (final m in room.members) {
        room.execute(m.id, 'ready-${m.id}', 'ready', {'ready': true});
      }
      room.execute(room.host.id, 'start', 'start', {});
      room.disconnect(guest.id);
      app.client.view = room.viewFor(room.host.id);
      app.client.connected = true;
      app.page = AppPage.room;
      app.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('离线 · 保留座位'), findsOneWidget);
      expect(find.textContaining('有参与者离线'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('startup notice and discovery entry work', (tester) async {
    final app = AppController(store: MemoryStore(), discovery: FakeDiscovery());
    await tester.pumpWidget(LanCardsApp(controller: app));
    await tester.pumpAndSettle();
    expect(find.text('一起玩得更顺畅'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索房间'));
    await tester.pumpAndSettle();
    expect(find.text('暂时没有发现房间'), findsOneWidget);
    expect(find.text('备用：手动输入地址'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create dialog defaults to three-player Dou Dizhu', (
    tester,
  ) async {
    final app = AppController(store: MemoryStore(), discovery: FakeDiscovery());
    await tester.pumpWidget(LanCardsApp(controller: app, showIntro: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建房间'));
    await tester.pumpAndSettle();
    expect(find.text('摆好一张牌桌'), findsOneWidget);
    expect(find.text('经典斗地主 · 三人'), findsOneWidget);
    expect(find.textContaining('固定三人'), findsOneWidget);
    await tester.tap(find.text('经典斗地主 · 三人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('轮流出牌 · 框架测试').last);
    await tester.pumpAndSettle();
    expect(find.text('6 个座位'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small phone supports enlarged system text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = AppController(store: MemoryStore(), discovery: FakeDiscovery());
    await tester.pumpWidget(LanCardsApp(controller: app, showIntro: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
