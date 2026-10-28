import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/app_controller.dart';
import 'package:lan_cards/games/doudizhu/patterns.dart';
import 'package:lan_cards/games/doudizhu/rules.dart';
import 'package:lan_cards/ui/app.dart';
import '../test/doudizhu_ui_test.dart'
    show TableController, makeRoom, chooseLandlord;
import '../test/helpers.dart';

void main() {
  testWidgets('render landscape Dou Dizhu states', (tester) async {
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = oldShadows);
    final font = File(
      '${Platform.environment['WINDIR'] ?? 'C:\\Windows'}\\Fonts\\msyh.ttc',
    );
    if (font.existsSync()) {
      for (final family in ['Roboto', 'Microsoft YaHei']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await loader.load();
      }
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var key = GlobalKey();
    final home = AppController(
      store: MemoryStore(),
      discovery: FakeDiscovery(),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: LanCardsApp(controller: home, showIntro: false),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('docs/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('ddz-home');
    final room = makeRoom();
    final table = TableController(room);
    key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: LanCardsApp(controller: table, showIntro: false),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/ddz_countryside.png'),
        key.currentContext!,
      );
    });
    await capture('ddz-lobby');
    for (final member in room.members) {
      table.remote(member.id, 'ready', {'ready': true});
    }
    table.remote(room.host.id, 'start');
    room.game = (room.game as DoudizhuState).copy(turn: 0);
    table.refresh();
    await capture('ddz-bidding');
    chooseLandlord(table);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ddz-hint')));
    await tester.pumpAndSettle();
    await capture('ddz-playing');
    room.disconnect(room.members[1].id);
    table.refresh();
    await capture('ddz-paused');
    room.resume(room.members[1].id, room.members[1].token);
    table.refresh();
    while (!room.game!.finished) {
      final game = room.game as DoudizhuState;
      final actor = game.turnPlayer!;
      final suggested = suggestPlay(game.hands[actor]!, game.lastPlay?.cards);
      table.remote(actor, 'play', {
        'roundId': room.roundId,
        'type': suggested.isEmpty ? 'pass' : 'play',
        if (suggested.isNotEmpty) 'cards': suggested,
      });
    }
    await capture('ddz-result');
    debugDisableShadows = oldShadows;
    expect(tester.takeException(), isNull);
  });
}
