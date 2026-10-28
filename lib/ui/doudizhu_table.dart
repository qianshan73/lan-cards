// Based on a Kimi K2.6 frontend draft; layout, lifecycle and input reviewed locally.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../games/doudizhu/patterns.dart';
import 'ddz_cards.dart';

const _gold = Color(0xFFFFD780);
const _white = Color(0xFFFFFBEC);

class DoudizhuTable extends StatefulWidget {
  const DoudizhuTable({
    super.key,
    required this.app,
    required this.onLeave,
    required this.onKick,
    required this.onAbort,
  });
  final AppController app;
  final Future<void> Function() onLeave;
  final Future<void> Function(String id, String name) onKick;
  final Future<void> Function() onAbort;
  @override
  State<DoudizhuTable> createState() => _DoudizhuTableState();
}

class _DoudizhuTableState extends State<DoudizhuTable> {
  final _selected = <int>{};
  final _dragged = <int>{};
  bool _dragSelect = true;
  double _dragAnchor = 0;
  int _lastDragIndex = 0;
  String? _round;
  String? _hintMessage;
  AppController get app => widget.app;
  Map<String, dynamic> get view => app.view ?? {};
  Map<String, dynamic>? get game => view['game'] as Map<String, dynamic>?;
  List<dynamic> get seats => view['seats'] as List? ?? [null, null, null];
  String? get you => view['you'] as String?;
  String get stage => game?['stage'] as String? ?? 'lobby';
  bool get active => game != null && game!['finished'] != true;
  bool get canAct =>
      app.connected &&
      !app.busy &&
      view['phase'] == 'playing' &&
      game?['turnPlayer'] == you;
  bool get canSelect =>
      app.connected &&
      !app.busy &&
      view['phase'] == 'playing' &&
      stage == 'playing';
  Map<String, dynamic>? seat(String? id) {
    for (final s in seats.whereType<Map>()) {
      if (s['id'] == id) return Map<String, dynamic>.from(s);
    }
    return null;
  }

  String name(String? id) => seat(id)?['name'] as String? ?? '离开的玩家';
  bool get ready => seat(you)?['ready'] == true;
  bool get canStart =>
      app.connected &&
      !app.busy &&
      !active &&
      seats.length == 3 &&
      seats.every(
        (s) => s != null && s['online'] == true && s['ready'] == true,
      );

  Future<void> send(String type, [Map<String, dynamic> data = const {}]) async {
    await app.command('play', {
      'type': type,
      'roundId': view['roundId'],
      ...data,
    });
    if (mounted && app.message == null) {
      setState(() {
        _selected.clear();
        _hintMessage = null;
      });
    }
  }

  void hint() {
    final hand = List<int>.from(game?['hand'] as List? ?? []);
    final previous = (game?['lastPlay'] as Map?)?['cards'] as List?;
    final suggestion = suggestPlay(hand, previous?.cast<int>());
    setState(() {
      _selected
        ..clear()
        ..addAll(suggestion);
      _hintMessage = suggestion.isEmpty ? '没有更大的牌，可以选择不出' : null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final hand = List<int>.from(game?['hand'] as List? ?? []);
      final round = view['roundId'] as String?;
      if (_round != round) {
        _round = round;
        _selected.clear();
        _hintMessage = null;
      }
      _selected.removeWhere((c) => !hand.contains(c));
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.2),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFF124B44),
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/ddz_countryside.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, trace) =>
                      const ColoredBox(color: Color(0xFF124B44)),
                ),
              ),
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withValues(alpha: .12)),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth, h = constraints.maxHeight;
                    final cardH = (h * .27).clamp(80.0, 118.0),
                        cardW = cardH * .70;
                    final controlTop = h - cardH - 80;
                    final selfIndex = seats.indexWhere(
                      (s) => s != null && s['id'] == you,
                    );
                    final me = selfIndex < 0 ? 0 : selfIndex;
                    return Stack(
                      children: [
                        Positioned(
                          left: w * .12,
                          top: h * .19,
                          width: w * .76,
                          height: h * .57,
                          child: CustomPaint(painter: const _FeltPainter()),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 46,
                          child: _header(),
                        ),
                        if (game != null)
                          Positioned(
                            top: 48,
                            left: w / 2 - 68,
                            width: 136,
                            height: 42,
                            child: _bottomCards(),
                          ),
                        Positioned(
                          left: 12,
                          top: math.max(86, h * .23),
                          width: 104,
                          child: _player(seats[(me + 2) % 3] as Map?),
                        ),
                        Positioned(
                          right: 12,
                          top: math.max(86, h * .23),
                          width: 104,
                          child: _player(seats[(me + 1) % 3] as Map?),
                        ),
                        if (game != null && stage != 'finished')
                          Positioned(
                            left: 124,
                            right: 124,
                            top: h < 350 ? 82 : 98,
                            child: _center(w - 248),
                          ),
                        if (!active)
                          Positioned.fill(
                            top: 82,
                            bottom: 12,
                            child: Center(child: _lobbyOrResult(h)),
                          ),
                        if (active) ...[
                          Positioned(
                            left: 112,
                            right: 112,
                            top: controlTop,
                            height: 48,
                            child: _controls(),
                          ),
                          Positioned(
                            left: 8,
                            bottom: 12,
                            width: 96,
                            child: _player(seat(you), self: true),
                          ),
                          if (hand.isNotEmpty)
                            Positioned(
                              left: 110,
                              right: 110,
                              bottom: 8,
                              height: cardH + 18,
                              child: _hand(hand, cardW, cardH),
                            ),
                        ],
                        if (view['phase'] == 'paused' || !app.connected)
                          Positioned(
                            top: 47,
                            left: 120,
                            right: 120,
                            child: _banner(
                              !app.connected
                                  ? '连接中断 · 正在找回你的座位'
                                  : '玩家离线 · 对局暂停，全员回来后继续',
                              const Color(0xFFE5A542),
                              Icons.pause_circle_outline,
                            ),
                          ),
                        if (app.message != null || _hintMessage != null)
                          Positioned(
                            left: 120,
                            right: 120,
                            bottom: active ? cardH + 136 : 8,
                            child: IgnorePointer(
                              child: _banner(
                                app.message ?? _hintMessage!,
                                const Color(0xFF8E4138),
                                Icons.info_outline,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _header() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          const Color(0xFF173F3B).withValues(alpha: .95),
          const Color(0xFF173F3B).withValues(alpha: .68),
        ],
      ),
    ),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('ddz-leave'),
          tooltip: '离开房间',
          onPressed: widget.onLeave,
          icon: const Icon(Icons.arrow_back_rounded, color: _white),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                view['name'] as String? ?? '朋友的牌桌',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Text(
                '经典斗地主 · 三人局 · ${app.connected ? '局域网已连接' : '正在重连'}',
                style: const TextStyle(color: Color(0xFFB6D3C9), fontSize: 10),
              ),
            ],
          ),
        ),
        _pill('底分 1', const Color(0xFF2B6054)),
        const SizedBox(width: 8),
        _pill('×${game?['multiplier'] ?? 1}', const Color(0xFFB4742A)),
        if (app.isHost)
          PopupMenuButton<String>(
            key: const ValueKey('ddz-host-menu'),
            icon: const Icon(Icons.settings_rounded, color: _gold, size: 22),
            itemBuilder: (_) => [
              if (active)
                PopupMenuItem(
                  value: 'abort',
                  enabled: app.connected && !app.busy,
                  child: const Text('结束本局，不计分'),
                ),
              for (final s in seats.whereType<Map>().where(
                (s) => s['id'] != you,
              ))
                PopupMenuItem(
                  value: s['id'] as String,
                  enabled: app.connected && !app.busy,
                  child: Text('移出 ${s['name']}'),
                ),
              if (!app.discovery.published)
                const PopupMenuItem(value: 'publish', child: Text('重新发布房间')),
            ],
            onSelected: (value) {
              if (value == 'abort') {
                unawaited(widget.onAbort());
              } else if (value == 'publish') {
                unawaited(app.retryPublication());
              } else {
                unawaited(widget.onKick(value, name(value)));
              }
            },
          ),
      ],
    ),
  );

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: _white,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );

  Widget _bottomCards() {
    final bottom = List<int>.from(game?['bottomCards'] as List? ?? []);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 6),
          child: Text('底牌', style: TextStyle(color: _white, fontSize: 11)),
        ),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: SizedBox(
              width: 27,
              height: 38,
              child: DdzCardFace(card: bottom.length == 3 ? bottom[i] : -1),
            ),
          ),
      ],
    );
  }

  Widget _player(Map? member, {bool self = false}) {
    final id = member?['id'] as String?;
    final empty = member == null;
    final online = member?['online'] == true;
    final landlord = game?['landlordId'] == id && id != null;
    final turn = game?['turnPlayer'] == id && active;
    final count = (game?['handCounts'] as Map?)?[id];
    final bid = (game?['bidActions'] as Map?)?[id] as String?;
    final last = (game?['lastActions'] as Map?)?[id] as Map?;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: empty
                  ? [const Color(0xFF6D9D91), const Color(0xFF416F65)]
                  : landlord
                  ? [const Color(0xFFF2B963), const Color(0xFFB66F36)]
                  : [const Color(0xFF7CD1C5), const Color(0xFF327B80)],
            ),
            border: Border.all(
              color: turn ? _gold : Colors.white.withValues(alpha: .5),
              width: turn ? 3 : 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            empty
                ? Icons.chair_outlined
                : !online
                ? Icons.person_off_outlined
                : landlord
                ? Icons.workspace_premium_rounded
                : Icons.face_rounded,
            size: 32,
            color: const Color(0xFFFFF4DD),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          empty ? '空位' : '${member['name']}${self ? '（你）' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
          ),
        ),
        const SizedBox(height: 3),
        _pill(
          empty
              ? '等朋友加入'
              : !online
              ? '离线占座'
              : !active
              ? member['ready'] == true
                    ? '已准备'
                    : '未准备'
              : game?['landlordId'] == null
              ? '待定'
              : landlord
              ? '地主'
              : '农民',
          !empty && !online ? const Color(0xFF995C37) : const Color(0xCC20554B),
        ),
        if (!empty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              active && count != null
                  ? '$count 张 · ${member['points'] ?? 0} 分'
                  : '${member['points'] ?? 0} 分',
              style: const TextStyle(color: _gold, fontSize: 10),
            ),
          ),
        if (active && !self && online) ...[
          if (stage == 'bidding' && bid != null)
            Text(
              bid,
              style: const TextStyle(
                color: _gold,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (stage == 'playing' && last?['type'] == 'pass')
            const Text(
              '不出',
              style: TextStyle(
                color: _gold,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ],
    );
  }

  Widget _center(double width) {
    if (stage == 'bidding') {
      final mode = game?['bidMode'] == 'calling' ? '叫地主' : '抢地主';
      return Column(
        children: [
          Text(
            '叫抢地主',
            style: TextStyle(
              color: _gold,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${name(game?['turnPlayer'] as String?)}正在$mode',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _white, fontSize: 12),
          ),
        ],
      );
    }
    final last = game?['lastPlay'] as Map?;
    if (last == null) {
      return Column(
        children: [
          Text(
            game?['turnPlayer'] == you
                ? '轮到你领出'
                : '等待 ${name(game?['turnPlayer'] as String?)} 出牌',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _gold,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            '先出完手牌的一方获胜',
            style: TextStyle(color: Color(0xFFCCDFD0), fontSize: 11),
          ),
        ],
      );
    }
    final cards = List<int>.from(last['cards'] as List? ?? []);
    return Column(
      children: [
        Text(
          '${name(last['playerId'] as String?)} · ${last['name']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        _publicFan(cards, width),
      ],
    );
  }

  Widget _publicFan(List<int> cards, double available) {
    if (cards.isEmpty) return const SizedBox.shrink();
    const cw = 34.0, ch = 47.0;
    final step = cards.length == 1
        ? 0.0
        : math.min(25.0, (available - cw) / (cards.length - 1));
    return SizedBox(
      width: cw + step * (cards.length - 1),
      height: ch,
      child: Stack(
        children: [
          for (var i = 0; i < cards.length; i++)
            Positioned(
              left: i * step,
              width: cw,
              height: ch,
              child: DdzCardFace(card: cards[i]),
            ),
        ],
      ),
    );
  }

  Widget _hand(List<int> cards, double cw, double ch) => LayoutBuilder(
    builder: (context, constraints) {
      final step = cards.length == 1
          ? 0.0
          : math.min(
              cw * .64,
              (constraints.maxWidth - cw) / (cards.length - 1),
            );
      final width = cw + step * (cards.length - 1);
      int index(double x) => (x / step).floor().clamp(0, cards.length - 1);
      void toggle(int c) {
        if (!canSelect) return;
        setState(() {
          if (!_selected.add(c)) _selected.remove(c);
          _hintMessage = null;
        });
      }

      void drag(double x) {
        if (!canSelect) return;
        final current = cards.length == 1 ? 0 : index(x);
        setState(() {
          for (
            var i = math.min(_lastDragIndex, current);
            i <= math.max(_lastDragIndex, current);
            i++
          ) {
            final c = cards[i];
            if (!_dragged.add(c)) continue;
            if (_dragSelect) {
              _selected.add(c);
            } else {
              _selected.remove(c);
            }
          }
          _lastDragIndex = current;
          _hintMessage = null;
        });
      }

      return Center(
        child: SizedBox(
          width: width,
          height: ch + 18,
          child: GestureDetector(
            key: const ValueKey('ddz-hand'),
            behavior: HitTestBehavior.opaque,
            onTapDown: canSelect
                ? (d) => _dragAnchor = d.localPosition.dx
                : null,
            onHorizontalDragDown: canSelect
                ? (d) => _dragAnchor = d.localPosition.dx
                : null,
            onTapUp: canSelect
                ? (d) => toggle(
                    cards[cards.length == 1 ? 0 : index(d.localPosition.dx)],
                  )
                : null,
            onHorizontalDragStart: canSelect
                ? (d) {
                    _dragged.clear();
                    _lastDragIndex = cards.length == 1 ? 0 : index(_dragAnchor);
                    final c = cards[_lastDragIndex];
                    _dragSelect = !_selected.contains(c);
                    drag(_dragAnchor);
                    drag(d.localPosition.dx);
                  }
                : null,
            onHorizontalDragUpdate: canSelect
                ? (d) => drag(d.localPosition.dx)
                : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < cards.length; i++)
                  AnimatedPositioned(
                    key: ValueKey('visual-card-${cards[i]}'),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    left: i * step,
                    top: _selected.contains(cards[i]) ? 0 : 18,
                    width: cw,
                    height: ch,
                    child: DdzCardFace(
                      card: cards[i],
                      selected: _selected.contains(cards[i]),
                    ),
                  ),
                for (var i = 0; i < cards.length; i++)
                  Positioned(
                    left: i * step,
                    top: _selected.contains(cards[i]) ? 0 : 18,
                    width: i == cards.length - 1 ? cw : step,
                    height: ch,
                    child: Semantics(
                      key: ValueKey('hand-card-${cards[i]}'),
                      label: ddzCardLabel(cards[i]),
                      button: true,
                      selected: _selected.contains(cards[i]),
                      onTap: canSelect ? () => toggle(cards[i]) : null,
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _controls() {
    if (stage == 'bidding') {
      final bids = List<String>.from(game?['availableBids'] as List? ?? []);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (bids.contains('pass')) ...[
            _button(
              game?['bidMode'] == 'calling' ? '不叫' : '不抢',
              canAct ? () => send('bid', {'bid': 'pass'}) : null,
              secondary: true,
              key: 'ddz-bid-pass',
            ),
            const SizedBox(width: 12),
          ],
          if (bids.contains('call'))
            _button(
              '叫地主',
              canAct ? () => send('bid', {'bid': 'call'}) : null,
              key: 'ddz-bid-call',
            ),
          if (bids.contains('rob'))
            _button(
              '抢地主',
              canAct ? () => send('bid', {'bid': 'rob'}) : null,
              key: 'ddz-bid-rob',
            ),
          if (bids.isEmpty) _pill('等待其他玩家叫抢', const Color(0xCC20554B)),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (canAct && game?['canPass'] == true) ...[
          _button('不出', () => send('pass'), secondary: true, key: 'ddz-pass'),
          const SizedBox(width: 10),
        ],
        _button('提示', canAct ? hint : null, secondary: true, key: 'ddz-hint'),
        const SizedBox(width: 10),
        _button(
          '出牌',
          canAct && _selected.isNotEmpty
              ? () => send('play', {'cards': _selected.toList()})
              : null,
          key: 'ddz-play',
        ),
        if (!canAct) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              view['phase'] == 'paused' ? '已暂停' : '等待出牌',
              style: const TextStyle(color: _white, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }

  Widget _lobbyOrResult(double h) {
    final finished = game?['finished'] == true;
    final winners = List<String>.from(game?['winnerIds'] as List? ?? []);
    final scores = Map<String, dynamic>.from(game?['scoreDelta'] as Map? ?? {});
    return Container(
      width: 370,
      constraints: BoxConstraints(maxHeight: h - 94),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xEF204F43),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE3BC71), width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 20)],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              finished ? (winners.contains(you) ? '胜利！' : '本局结束') : '朋友到齐，一起开局',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _gold,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              finished
                  ? (game?['resultText'] as String? ?? '本局已结束')
                  : '座位 ${view['occupied'] ?? 0}/3 · 地主对战两位农民',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFCCE1D5), fontSize: 12),
            ),
            const SizedBox(height: 10),
            for (final s in seats.whereType<Map>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      s['online'] == true
                          ? Icons.circle
                          : Icons.circle_outlined,
                      size: 9,
                      color: s['online'] == true
                          ? const Color(0xFF8EDBB6)
                          : _gold,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s['name'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _white, fontSize: 12),
                      ),
                    ),
                    if (scores[s['id']] != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          '${(scores[s['id']] as int) > 0 ? '+' : ''}${scores[s['id']]} 分',
                          style: const TextStyle(color: _gold, fontSize: 12),
                        ),
                      ),
                    Text(
                      s['online'] != true
                          ? '离线占座'
                          : s['ready'] == true
                          ? '已准备'
                          : '未准备',
                      style: const TextStyle(
                        color: Color(0xFFA6DDBF),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                _button(
                  ready
                      ? '取消准备'
                      : finished
                      ? '准备下一局'
                      : '准备好了',
                  app.connected && !app.busy
                      ? () => app.command('ready', {'ready': !ready})
                      : null,
                  secondary: ready,
                  key: 'ddz-ready',
                ),
                if (app.isHost)
                  _button(
                    '开始游戏',
                    canStart ? () => app.command('start') : null,
                    key: 'ddz-start',
                  ),
              ],
            ),
            if (!finished)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '三人在线且准备后，由房主开始。',
                  style: TextStyle(color: Color(0xFFB6D3C9), fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _button(
    String text,
    VoidCallback? action, {
    bool secondary = false,
    String? key,
  }) => SizedBox(
    height: 44,
    child: ElevatedButton(
      key: key == null ? null : ValueKey(key),
      onPressed: action,
      style: ElevatedButton.styleFrom(
        backgroundColor: secondary
            ? const Color(0xFF397AA3)
            : const Color(0xFFF0AD4E),
        foregroundColor: secondary ? _white : const Color(0xFF563B22),
        disabledBackgroundColor: const Color(0xFF52746B),
        disabledForegroundColor: const Color(0xFFB5C6BF),
        padding: const EdgeInsets.symmetric(horizontal: 21),
        minimumSize: const Size(70, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        elevation: action == null ? 0 : 3,
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
  );

  Widget _banner(String text, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _white, size: 16),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _white, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _FeltPainter extends CustomPainter {
  const _FeltPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()..addOval(rect.deflate(8));
    canvas.drawShadow(path, Colors.black.withValues(alpha: .55), 12, true);
    canvas.drawOval(rect.deflate(7), Paint()..color = const Color(0xFF9F6C37));
    canvas.drawOval(
      rect.deflate(14),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF3D9980), Color(0xFF216754)],
        ).createShader(rect),
    );
    canvas.drawOval(
      rect.deflate(22),
      Paint()
        ..color = const Color(0x5573B79A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _FeltPainter oldDelegate) => false;
}
