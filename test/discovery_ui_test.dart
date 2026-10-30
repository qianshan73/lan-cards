import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/app_controller.dart';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/doudizhu/rules.dart';
import 'package:lan_cards/network/discovery_service.dart';
import 'package:lan_cards/ui/app.dart';
import 'package:lan_cards/ui/discovery_diagnostics.dart';
import 'package:nsd/nsd.dart' as nsd;

import 'helpers.dart';

class ProbeDiagnosticsFixture extends FakeDiscovery {
  @override
  DiscoveryDiagnostics get diagnostics => DiscoveryDiagnostics(
    search: DiscoveryStage.active,
    servicesSeen: 2,
    servicesChecked: 2,
    probeFailures: const {
      ProbeFailure.timeout: 1,
      ProbeFailure.invalidResponse: 1,
    },
    manualProbeFailure: ProbeFailure.network,
  );
}

void main() {
  testWidgets(
    'HTTP failures show concrete next steps and separate manual outcome',
    (tester) async {
      final app = AppController(
        store: MemoryStore(),
        discovery: ProbeDiagnosticsFixture(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiscoveryDiagnosticsPanel(app: app),
            ),
          ),
        ),
      );
      expect(find.textContaining('HTTP 房间检查失败'), findsOneWidget);
      expect(find.textContaining('热点或访客网络是否隔离设备'), findsOneWidget);
      expect(find.textContaining('相同版本 App'), findsOneWidget);
      expect(find.textContaining('手动地址检查：连接失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(app.shutdown);
    },
  );

  testWidgets(
    'search startup failure gives retry and sanitized copy, recovers in place',
    (tester) async {
      tester.view.physicalSize = const Size(667, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeDiscoveryBackend()
        ..startError = nsd.NsdError(
          nsd.ErrorCause.securityIssue,
          'SECRET-DO-NOT-COPY',
        );
      final discovery = DiscoveryService(backend: backend);
      final app = AppController(store: MemoryStore(), discovery: discovery);
      await tester.pumpWidget(LanCardsApp(controller: app, showIntro: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索房间'));
      await tester.pumpAndSettle();
      expect(find.textContaining('搜索启动失败'), findsOneWidget);
      expect(find.textContaining('系统报告权限问题'), findsOneWidget);
      await tester.tap(find.byTooltip('局域网诊断'));
      await tester.pumpAndSettle();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('复制脱敏诊断'));
      await tester.pump();
      expect(copied, contains('search_failure=permission'));
      expect(copied, isNot(contains('SECRET-DO-NOT-COPY')));
      backend.startError = null;
      await tester.tap(find.text('重新搜索'));
      await tester.pumpAndSettle();
      expect(backend.startCalls, 2);
      expect(discovery.diagnostics.search, DiscoveryStage.active);
      expect(find.textContaining('不能据此判断是否处于同一网络'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.runAsync(app.shutdown);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'address-resolution failures are visible without displaying service names',
    (tester) async {
      final backend = FakeDiscoveryBackend();
      backend.discovery.add(const nsd.Service(name: 'SECRET-SERVICE-TXT'));
      final discovery = DiscoveryService(backend: backend);
      final app = AppController(store: MemoryStore(), discovery: discovery);
      addTearDown(app.shutdown);
      await discovery.startSearch();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiscoveryDiagnosticsPanel(app: app),
            ),
          ),
        ),
      );
      expect(find.textContaining('1 个服务未取得可用地址'), findsOneWidget);
      expect(find.textContaining('备用地址'), findsOneWidget);
      expect(find.textContaining('SECRET-SERVICE-TXT'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.runAsync(app.shutdown);
    },
  );

  testWidgets(
    'Dou Dizhu exposes persistent publication failure and diagnostics without game changes',
    (tester) async {
      tester.view.physicalSize = const Size(667, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeDiscoveryBackend()
        ..registerError = nsd.NsdError(
          nsd.ErrorCause.internalError,
          'SECRET-NATIVE',
        );
      final discovery = DiscoveryService(backend: backend);
      await expectLater(
        discovery.publish('fixture-room', 12345),
        throwsA(isA<nsd.NsdError>()),
      );
      final app = AppController(store: MemoryStore(), discovery: discovery);
      final room = Room(
        name: '测试牌桌',
        hostName: '朋友',
        rules: DoudizhuRules(),
        capacity: 3,
      );
      app.client.view = room.viewFor(room.host.id);
      app.client.connected = true;
      app.page = AppPage.room;
      await tester.pumpWidget(LanCardsApp(controller: app, showIntro: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('房间发布失败 · 局域网诊断'));
      await tester.pumpAndSettle();
      expect(find.textContaining('房间发布失败，朋友可能搜索不到'), findsOneWidget);
      expect(find.textContaining('SECRET-NATIVE'), findsNothing);
      expect(room.members, hasLength(1));
      expect(room.game, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
