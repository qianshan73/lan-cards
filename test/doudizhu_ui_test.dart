import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cards/app_controller.dart';
import 'package:lan_cards/core/game_rules.dart';
import 'package:lan_cards/core/room.dart';
import 'package:lan_cards/games/doudizhu/rules.dart';
import 'package:lan_cards/ui/app.dart';
import 'helpers.dart';

class TableController extends AppController {
  TableController(this.room, {String? viewer})
    : viewer = viewer ?? room.host.id,
      super(store: MemoryStore(), discovery: FakeDiscovery()) {
    refresh();
  }
  final Room room;
  String viewer;
  int serial = 0;
  @override
  bool get isHost => viewer == room.host.id;
  void refresh() {
    client.view = room.viewFor(viewer);
    client.connected = true;
    notifyListeners();
  }

  @override
  Future<void> initialize() async {
    page = AppPage.room;
    refresh();
  }

  @override
  Future<void> command(
    String command, [
    Map<String, dynamic> payload = const {},
  ]) async {
    try {
      room.execute(viewer, 'ui-${serial++}', command, payload);
      message = null;
    } on RuleError catch (e) {
      message = e.message;
    }
    refresh();
  }

  void remote(
    String player,
    String action, [
    Map<String, dynamic> payload = const {},
  ]) {
    room.execute(player, 'ui-${serial++}', action, payload);
    refresh();
  }
}

Room makeRoom({bool started = false}) {
  final room = Room(
    name: '朋友的斗地主',
    hostName: '小明',
    rules: DoudizhuRules(),
    capacity: 3,
    random: Random(7),
  );
  room.join('小红:旅行');
  room.join('小李');
  if (started) {
    for (final m in room.members) {
      room.execute(m.id, 'ready-${m.id}', 'ready', {'ready': true});
    }
    room.execute(room.host.id, 'start', 'start', {});
    room.game = (room.game as DoudizhuState).copy(turn: 0);
  }
  return room;
}

void chooseLandlord(TableController app) {
  while ((app.room.game as DoudizhuState).stage == DdzStage.bidding) {
    final g = app.room.game as DoudizhuState;
    app.remote(g.turnPlayer!, 'play', {
      'type': 'bid',
      'bid': g.callerId == null ? 'call' : 'pass',
      'roundId': app.room.roundId,
    });
  }
}

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'tap and swipe select exposed cards without skipping intermediate cards',
    (tester) async {
      setSize(tester, const Size(844, 390));
      final room = makeRoom(started: true);
      final table = TableController(room);
      chooseLandlord(table);
      await tester.pumpWidget(LanCardsApp(controller: table, showIntro: false));
      await tester.pumpAndSettle();
      final hand = (room.game as DoudizhuState).hands[room.host.id]!;
      final first = find.byKey(ValueKey('hand-card-${hand.first}'));
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(first).properties.selected, true);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(first).properties.selected, false);
      final fifth = find.byKey(ValueKey('hand-card-${hand[4]}'));
      final start = tester.getCenter(first), end = tester.getCenter(fifth);
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(end);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      for (final card in hand.take(5)) {
        expect(
          tester
              .widget<Semantics>(find.byKey(ValueKey('hand-card-$card')))
              .properties
              .selected,
          true,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [
    const Size(667, 320),
    const Size(844, 390),
    const Size(1024, 768),
  ]) {
    testWidgets('Dou Dizhu lobby/bidding/20-card hand/pause/result fit $size', (
      tester,
    ) async {
      setSize(tester, size);
      final room = makeRoom();
      final app = TableController(room);
      await tester.pumpWidget(LanCardsApp(controller: app, showIntro: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ddz-ready')), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final m in room.members) {
        app.remote(m.id, 'ready', {'ready': true});
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ddz-start')));
      await tester.pumpAndSettle();
      room.game = (room.game as DoudizhuState).copy(turn: 0);
      app.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ddz-bid-call')), findsOneWidget);
      expect(tester.takeException(), isNull);
      chooseLandlord(app);
      await tester.pumpAndSettle();
      final game = room.game as DoudizhuState;
      expect(game.hands[room.host.id], hasLength(20));
      for (final card in game.hands[room.host.id]!) {
        expect(find.byKey(ValueKey('hand-card-$card')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      room.disconnect(room.members[1].id);
      app.refresh();
      await tester.pumpAndSettle();
      expect(find.textContaining('对局暂停'), findsOneWidget);
      expect(find.byKey(const ValueKey('ddz-host-menu')), findsOneWidget);
      expect(tester.takeException(), isNull);
      app.remote(room.host.id, 'abort');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ddz-ready')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('call/rob buttons send correct round-scoped host commands', (
    tester,
  ) async {
    setSize(tester, const Size(844, 390));
    final room = makeRoom(started: true);
    final table = TableController(room);
    await tester.pumpWidget(LanCardsApp(controller: table, showIntro: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ddz-bid-call')));
    await tester.pumpAndSettle();
    table.viewer = room.members[1].id;
    table.refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ddz-bid-rob')));
    await tester.pumpAndSettle();
    expect((room.game as DoudizhuState).multiplier, 2);
    table.remote(room.members[2].id, 'play', {
      'type': 'bid',
      'bid': 'pass',
      'roundId': room.roundId,
    });
    table.viewer = room.host.id;
    table.refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ddz-bid-rob')));
    await tester.pumpAndSettle();
    expect((room.game as DoudizhuState).landlordId, room.host.id);
    expect((room.game as DoudizhuState).multiplier, 4);
  });

  testWidgets('hand selection and hint submit only selected legal cards', (
    tester,
  ) async {
    setSize(tester, const Size(844, 390));
    final room = makeRoom(started: true);
    final table = TableController(room);
    chooseLandlord(table);
    await tester.pumpWidget(LanCardsApp(controller: table, showIntro: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ddz-hint')));
    await tester.pumpAndSettle();
    final before = (room.game as DoudizhuState).hands[room.host.id]!.length;
    final playButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('ddz-play')),
    );
    expect(playButton.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('ddz-play')));
    await tester.pumpAndSettle();
    expect(
      (room.game as DoudizhuState).hands[room.host.id]!.length,
      lessThan(before),
    );
    expect(table.message, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finished round offers readiness and host can start next deal', (
    tester,
  ) async {
    setSize(tester, const Size(844, 390));
    final room = makeRoom(started: true);
    final ids = room.members.map((m) => m.id).toList();
    room.game = DoudizhuState(
      players: ids,
      hands: {
        ids[0]: [2],
        ids[1]: [3],
        ids[2]: [4],
      },
      bottom: [],
      turn: 0,
      stage: DdzStage.playing,
      landlordId: ids[0],
    );
    final table = TableController(room);
    table.remote(ids[0], 'play', {
      'type': 'play',
      'cards': [2],
      'roundId': room.roundId,
    });
    await tester.pumpWidget(LanCardsApp(controller: table, showIntro: false));
    await tester.pumpAndSettle();
    expect(find.text('胜利！'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ddz-ready')));
    await tester.pumpAndSettle();
    table.remote(ids[1], 'ready', {'ready': true});
    table.remote(ids[2], 'ready', {'ready': true});
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ddz-start')));
    await tester.pumpAndSettle();
    expect((room.game as DoudizhuState).stage, DdzStage.bidding);
    expect(room.host.points, 4);
    expect(room.members, hasLength(3));
    expect(tester.takeException(), isNull);
  });
}
