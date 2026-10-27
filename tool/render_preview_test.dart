import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/app_controller.dart';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/round_robin.dart';
import 'package:lan_cards/ui/app.dart';
import '../test/helpers.dart';

void main() {
  testWidgets('render actual Flutter UI previews', (tester) async {
    final fonts = [
      File(
        '${Platform.environment['WINDIR'] ?? 'C:\\Windows'}\\Fonts\\msyh.ttc',
      ),
      File('/System/Library/Fonts/PingFang.ttc'),
    ];
    for (final font in fonts) {
      if (font.existsSync()) {
        for (final family in ['Roboto', 'Microsoft YaHei']) {
          final loader = FontLoader(family);
          loader.addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          );
          await loader.load();
        }
        break;
      }
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppController(store: MemoryStore(), discovery: FakeDiscovery());
    final key = GlobalKey();
    await tester.pumpWidget(
      DefaultTextStyle(
        style: const TextStyle(fontFamily: 'PreviewChinese'),
        child: RepaintBoundary(
          key: key,
          child: LanCardsApp(controller: app, showIntro: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final file = File('docs/$name.png');
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('preview-home');
    final room = Room(
      name: '周末出游的牌桌',
      hostName: '小明',
      rules: RoundRobinRules(),
    );
    final a = room.join('小红');
    final b = room.join('小李');
    for (final m in room.members) {
      room.execute(m.id, 'ready-${m.id}', 'ready', {'ready': true});
    }
    room.execute(room.host.id, 'start', 'start', {});
    room.disconnect(b.id);
    app.client.view = room.viewFor(a.id);
    app.client.connected = true;
    app.page = AppPage.room;
    app.onForeground();
    await tester.pumpAndSettle();
    await capture('preview-room');
    expect(tester.takeException(), isNull);
  });
}
