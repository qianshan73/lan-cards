import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_controller.dart';
import '../games/blackjack.dart';
import '../network/discovery_service.dart';
import 'blackjack_board.dart';
import 'doudizhu_table.dart';
import 'discovery_diagnostics.dart';

const green = Color(0xFF176B50);
const ink = Color(0xFF1D3029);
const muted = Color(0xFF6D7C73);
const paper = Color(0xFFF6F6EF);

class LanCardsApp extends StatelessWidget {
  const LanCardsApp({
    super.key,
    required this.controller,
    this.showIntro = true,
  });
  final AppController controller;
  final bool showIntro;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '一起出牌',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        surface: paper,
        onSurface: ink,
      ),
      scaffoldBackgroundColor: paper,
      fontFamilyFallback: const [
        'Microsoft YaHei',
        'PingFang SC',
        'sans-serif',
      ],
      appBarTheme: const AppBarTheme(backgroundColor: paper, elevation: 0),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    home: AppShell(controller: controller, showIntro: showIntro),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    required this.showIntro,
  });
  final AppController controller;
  final bool showIntro;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  AppController get app => widget.controller;
  int? selectedCard;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(app.initialize());
    if (widget.showIntro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                icon: const Icon(Icons.groups_rounded, color: green, size: 32),
                title: const Text('一起玩得更顺畅'),
                content: const Text(
                  '请先连接同一个 Wi-Fi 或手机热点。\n\n'
                  '对局时尽量保持游戏在前台。切换应用、锁屏或网络中断可能导致暂停；'
                  '短暂断线后会尝试恢复，房主应用被关闭则需要重新组房。',
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) app.onForeground();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(app.shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => PopScope(
      canPop: app.page == AppPage.home,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (app.page == AppPage.room) {
            unawaited(_leave());
          } else {
            app.home();
          }
        }
      },
      child: app.page == AppPage.room && app.view?['gameId'] == 'doudizhu_v1'
          ? DoudizhuTable(
              app: app,
              onLeave: _leave,
              onKick: _kickDdz,
              onAbort: _abortDdz,
            )
          : Scaffold(
              appBar: AppBar(
                leading: app.page == AppPage.home
                    ? null
                    : IconButton(
                        tooltip: '返回',
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () {
                          if (app.page == AppPage.room) {
                            unawaited(_leave());
                          } else {
                            app.home();
                          }
                        },
                      ),
                title: Text(
                  switch (app.page) {
                    AppPage.home => '一起出牌',
                    AppPage.search => '搜索房间',
                    AppPage.room => app.view?['name'] as String? ?? '朋友的房间',
                    AppPage.reconnect => '找回你的座位',
                  },
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                actions: [
                  if (app.page != AppPage.home)
                    DiscoveryDiagnosticsButton(app: app),
                  if (app.page == AppPage.room)
                    IconButton(
                      tooltip: '离开房间',
                      onPressed: _leave,
                      icon: const Icon(Icons.logout_rounded),
                    ),
                ],
              ),
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          app.page == AppPage.home &&
                              MediaQuery.sizeOf(context).width > 600
                          ? 1000
                          : 640,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (app.message != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Notice(
                                app.message!,
                                icon: Icons.info_outline_rounded,
                              ),
                            ),
                          switch (app.page) {
                            AppPage.home => _home(),
                            AppPage.search => _search(),
                            AppPage.room => _room(),
                            AppPage.reconnect => _reconnect(),
                          },
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ),
  );

  Widget _home() => MediaQuery.sizeOf(context).width > 600
      ? _landscapeHome()
      : _homePortrait();

  Widget _landscapeHome() => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '朋友在身边，\n好牌在手边。',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '经典斗地主 · 21 点\n同一个 Wi-Fi 或热点，一起开局。',
                style: TextStyle(color: muted, fontSize: 13, height: 1.7),
              ),
              const SizedBox(height: 18),
              InkWell(
                onTap: _nickname,
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFE5EDE1),
                      child: Icon(Icons.person_outline, color: green),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        app.nickname,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.edit_outlined, size: 17, color: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (app.hasRecovery) ...[
              FilledButton.icon(
                onPressed: app.retryRecovery,
                icon: const Icon(Icons.refresh),
                label: const Text('返回原来的座位'),
              ),
              TextButton(
                onPressed: () async {
                  if (await _confirm('离开原房间？', '离线时需要房主手动释放你的座位。')) {
                    await app.leave();
                  }
                },
                child: const Text('离开原房间 / 放弃恢复'),
              ),
            ],
            ActionCard(
              icon: Icons.add_rounded,
              title: '创建房间',
              subtitle: '选斗地主或 21 点，等朋友来坐下',
              primary: true,
              onTap: app.busy || app.hasRecovery ? null : _create,
            ),
            const SizedBox(height: 12),
            ActionCard(
              icon: Icons.radar_rounded,
              title: '搜索房间',
              subtitle: '找到朋友的牌桌，点一下就加入',
              onTap: app.busy || app.hasRecovery
                  ? null
                  : () => unawaited(app.search()),
            ),
            const SizedBox(height: 12),
            const Text(
              '局域网直连 · 无账号 · 无广告',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _kickDdz(String id, String name) async {
    if (await _confirm(
      '移出 $name？',
      '座位将释放，旧凭证失效。地主已确定时，退出一方按弃权结算；叫抢阶段则作废本局。',
    )) {
      await app.command('kick', {'playerId': id});
    }
  }

  Future<void> _abortDdz() async {
    if (await _confirm('结束当前这一局？', '本局作废、不计分，所有座位保留，回到房间等待下一局。')) {
      await app.command('abort');
    }
  }

  Widget _homePortrait() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 18),
      const Text(
        '朋友在身边，\n好牌在手边。',
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          height: 1.35,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        '同一个 Wi-Fi 或热点，就能一起开局。',
        style: TextStyle(color: muted, fontSize: 15),
      ),
      const SizedBox(height: 24),
      InkWell(
        onTap: _nickname,
        borderRadius: BorderRadius.circular(16),
        child: Panel(
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFE5EDE1),
                child: Icon(Icons.person_outline_rounded, color: green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '你的昵称',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    Text(
                      app.nickname,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined, size: 19, color: muted),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      if (app.hasRecovery) ...[
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '你在「${app.recoveryRoomName}」还有一个座位',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: app.retryRecovery,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('返回原来的座位'),
              ),
              TextButton(
                onPressed: () async {
                  if (await _confirm(
                    '离开原房间 / 放弃恢复？',
                    '如果现在无法连接原房间，就无法通知房主释放座位，需要房主手动移出你。',
                  )) {
                    await app.leave();
                  }
                },
                child: const Text('离开原房间 / 放弃恢复'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
      ActionCard(
        icon: Icons.add_rounded,
        title: '创建房间',
        subtitle: '当房主，等朋友们来坐下',
        primary: true,
        onTap: app.busy || app.hasRecovery ? null : _create,
      ),
      const SizedBox(height: 14),
      ActionCard(
        icon: Icons.radar_rounded,
        title: '搜索房间',
        subtitle: '找到朋友的牌桌，点一下就加入',
        onTap: app.busy || app.hasRecovery
            ? null
            : () => unawaited(app.search()),
      ),
      const SizedBox(height: 30),
      const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_rounded, size: 16, color: muted),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              '局域网直连 · 无账号 · 无广告',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        '斗地主 · 21 点',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 11),
      ),
    ],
  );

  Widget _search() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Notice('请与朋友连接同一个 Wi-Fi 或手机热点，无需互联网。', icon: Icons.wifi_rounded),
      const SizedBox(height: 18),
      Row(
        children: [
          const Expanded(
            child: Text(
              '当前网络中的房间',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ),
          IconButton(
            tooltip: '重新搜索',
            onPressed: app.discovery.searching
                ? null
                : () => unawaited(app.discovery.startSearch()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      if (app.discovery.searching) const LinearProgressIndicator(),
      DiscoveryDiagnosticsPanel(app: app),
      if (app.foundRooms.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 44),
          child: Column(
            children: [
              const Icon(Icons.chair_outlined, size: 52, color: muted),
              const SizedBox(height: 18),
              Text(
                app.discovery.searching ? '正在寻找朋友的房间…' : '暂时没有发现房间',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '请朋友先创建房间，并保持 App 在前台。',
                style: TextStyle(color: muted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      for (final room in app.foundRooms)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _foundRoom(room),
        ),
      const SizedBox(height: 16),
      TextButton.icon(
        onPressed: _connectionHelp,
        icon: const Icon(Icons.help_outline_rounded),
        label: const Text('找不到房间？'),
      ),
      TextButton(
        onPressed: app.busy ? null : _manual,
        child: const Text('备用：手动输入地址', style: TextStyle(color: muted)),
      ),
    ],
  );

  Widget _foundRoom(FoundRoom room) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.table_restaurant_rounded, color: green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                room.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            BadgeLabel(room.full ? '座位已满' : '有空位'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '座位 ${room.info['occupied']}/${room.info['capacity']} · 在线 ${room.info['online']} 人 · ${_phase(room.info['phase'])}',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 4),
        Text(
          room.info['gameTitle'] as String? ?? '卡牌游戏',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: room.full || app.busy
              ? null
              : () => unawaited(app.join(room)),
          child: Text(room.full ? '离线玩家仍保留座位' : '坐下加入'),
        ),
      ],
    ),
  );

  Widget _reconnect() => Panel(
    child: Column(
      children: [
        const SizedBox(height: 12),
        const CircularProgressIndicator(strokeWidth: 3),
        const SizedBox(height: 24),
        Text(
          '正在寻找「${app.recoveryRoomName}」',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          '你的座位不会因为短暂离线而释放。\n请连回原来的 Wi-Fi 或热点，并让房主保持游戏开启。',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, height: 1.7),
        ),
        const SizedBox(height: 20),
        TextButton(onPressed: app.home, child: const Text('返回首页，保留恢复信息')),
      ],
    ),
  );

  Widget _room() {
    final view = app.view;
    if (view == null) return _reconnect();
    final seats = view['seats'] as List;
    final me = seats.whereType<Map>().firstWhere(
      (m) => m['id'] == view['you'],
      orElse: () => <String, dynamic>{},
    );
    final game = view['game'] as Map<String, dynamic>?;
    final blackjack = view['gameId'] == blackjackGameId;
    final active = game != null && game['finished'] != true;
    final waiting = game?['waitingNextRound'] == true && active;
    final hand = (game?['hand'] as List? ?? []).cast<int>();
    final playable =
        app.connected &&
        !app.busy &&
        view['phase'] == 'playing' &&
        game?['turnPlayer'] == view['you'] &&
        !waiting;
    final people = seats.whereType<Map>().toList();
    final canStart =
        app.connected &&
        !app.busy &&
        !active &&
        people.length >= 2 &&
        people.every((m) => m['online'] == true && m['ready'] == true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (blackjack) const BadgeLabel('21 点'),
            BadgeLabel(app.isHost ? '你是房主' : '朋友的牌桌'),
            BadgeLabel(app.connected ? '局域网已连接' : '正在恢复连接'),
            BadgeLabel('座位 ${view['occupied']}/${view['capacity']}'),
          ],
        ),
        const SizedBox(height: 18),
        if (!app.connected) ...[
          const Notice(
            '连接暂时中断，对局暂停。正在尝试找回座位；如果房主应用已关闭，请退出后重新组房。',
            icon: Icons.wifi_off_rounded,
          ),
          const SizedBox(height: 14),
        ] else if (view['phase'] == 'paused') ...[
          Notice(
            '有参与者离线，对局暂停。全员恢复后将自动继续。${app.isHost ? '你可以继续等待，或结束本局返回房间。' : '请等待朋友回来，或由房主结束本局。'}',
            icon: Icons.pause_circle_outline_rounded,
          ),
          const SizedBox(height: 14),
        ],
        if (blackjack && game != null && !waiting) ...[
          BlackjackBoard(
            game: game,
            playerId: view['you'] as String,
            turnName: _playerName(game['turnPlayer']),
            canAct: playable,
            onAction: (type) => unawaited(
              app.command('play', {'type': type, 'roundId': view['roundId']}),
            ),
          ),
          const SizedBox(height: 14),
        ],
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              seats.length,
              (i) => SizedBox(
                width: (constraints.maxWidth - 16) / 3,
                child: _seat(i, seats[i] as Map?, view, game),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (view['lastResult'] != null) ...[
          Notice(view['lastResult'] as String, icon: Icons.flag_outlined),
          const SizedBox(height: 16),
        ],
        if (waiting) ...[
          const Notice(
            '你已坐下，本手已经开始。请等待下一局，不影响现有玩家继续游戏。',
            icon: Icons.hourglass_empty_rounded,
          ),
          const SizedBox(height: 16),
        ],
        if (game != null && !waiting && !blackjack) ...[
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  game['finished'] == true
                      ? '本局已结束'
                      : '轮到 ${_playerName(game['turnPlayer'])} 出牌',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _table(game),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '你的手牌',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              for (final card in hand)
                PlayingCard(
                  card: card,
                  selected: selectedCard == card,
                  onTap: playable
                      ? () => setState(() => selectedCard = card)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (active)
            FilledButton.icon(
              onPressed: playable && hand.contains(selectedCard)
                  ? () async {
                      final card = selectedCard;
                      setState(() => selectedCard = null);
                      await app.command('play', {
                        'type': 'play',
                        'card': card,
                        'roundId': view['roundId'],
                      });
                    }
                  : null,
              icon: const Icon(Icons.arrow_upward_rounded),
              label: Text(playable ? '出这张牌' : '等待其他玩家'),
            ),
          const SizedBox(height: 14),
        ],
        if (!active) ...[
          FilledButton.icon(
            onPressed: !app.connected || app.busy
                ? null
                : () => unawaited(
                    app.command('ready', {'ready': me['ready'] != true}),
                  ),
            icon: Icon(
              me['ready'] == true
                  ? Icons.check_circle
                  : Icons.check_circle_outline,
            ),
            label: Text(me['ready'] == true ? '已准备 · 点击取消' : '准备好了'),
          ),
          if (app.isHost) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: canStart
                  ? () => unawaited(app.command('start'))
                  : null,
              child: const Text('全员准备，开始一局'),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            blackjack
                ? '21 点：每人先拿两张，与庄家比点数。2–6 人，只计房间积分。\n开局前，所有占座玩家都须在线并准备。'
                : '测试玩法：每人 5 张牌，轮流出一张，先出完者获胜。\n至少 2 人；离线玩家占座，开局前需等其恢复或由房主移出。',
            style: const TextStyle(color: muted, fontSize: 12, height: 1.7),
          ),
        ],
        if (app.isHost && active) ...[
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: !app.connected || app.busy
                ? null
                : () async {
                    if (await _confirm(
                      '结束当前这一局？',
                      '本局作废、不计分。所有座位保留，在线玩家回到原房间，可以再开下一把。',
                    )) {
                      await app.command('abort');
                    }
                  },
            child: const Text('结束本局，返回房间'),
          ),
        ],
        if (app.isHost) ...[
          const SizedBox(height: 12),
          if (!app.discovery.published)
            TextButton.icon(
              onPressed: app.retryPublication,
              icon: const Icon(Icons.wifi_tethering_rounded, size: 17),
              label: const Text('重新发布房间'),
            ),
          TextButton.icon(
            onPressed: _addresses,
            icon: const Icon(Icons.link_rounded, size: 17),
            label: const Text('备用连接地址'),
          ),
        ],
      ],
    );
  }

  Widget _seat(int index, Map? member, Map<String, dynamic> view, Map? game) {
    final empty = member == null;
    final online = member?['online'] == true;
    final mine = member?['id'] == view['you'];
    final count = game?['finished'] == true
        ? null
        : (game?['handCounts'] as Map?)?[member?['id']];
    final blackjack = view['gameId'] == blackjackGameId;
    final outcome = (game?['outcomes'] as Map?)?[member?['id']] as Map?;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFFE5EDE1) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: mine ? green : const Color(0xFFE3E7DE)),
      ),
      child: Column(
        children: [
          Icon(
            empty
                ? Icons.chair_outlined
                : online
                ? Icons.person_rounded
                : Icons.person_off_outlined,
            color: empty || !online ? muted : green,
            size: 27,
          ),
          const SizedBox(height: 8),
          Text(
            empty ? '空位 ${index + 1}' : '${member['name']}${mine ? '（你）' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 5),
          Text(
            empty
                ? '等朋友坐下'
                : !online
                ? '离线 · 保留座位'
                : count != null
                ? '手牌 $count 张'
                : member['ready'] == true
                ? '已准备'
                : '未准备',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: !empty && !online ? Colors.orange.shade800 : muted,
            ),
          ),
          if (member?['isHost'] == true)
            const Text('房主', style: TextStyle(color: green, fontSize: 10)),
          if (blackjack && member != null)
            Text(
              '${outcome == null ? '' : '${outcome['label']} · '}${member['points']} 分',
              style: const TextStyle(color: green, fontSize: 11),
            ),
          if (app.isHost && !empty && !mine)
            SizedBox(
              height: 30,
              child: TextButton(
                onPressed: !app.connected || app.busy
                    ? null
                    : () async {
                        if (await _confirm(
                          '移出 ${member['name']}？',
                          blackjack
                              ? '座位将释放。若对方正在参与本局，本局作废、不计分。'
                              : '座位将释放，对方无法自动重连。测试游戏会跳过此玩家；只剩一人则结束本局。',
                        )) {
                          await app.command('kick', {'playerId': member['id']});
                        }
                      },
                child: const Text('移出', style: TextStyle(fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _table(Map game) {
    final table = game['table'] as List;
    if (table.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          '桌面还没有牌',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
      );
    }
    final last = table.last as Map;
    return Row(
      children: [
        PlayingCard(card: last['card'] as int, compact: true),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            '${_playerName(last['playerId'])} 刚刚出牌\n本局已出 ${table.length} 张',
            style: const TextStyle(color: muted, height: 1.8),
          ),
        ),
      ],
    );
  }

  String _playerName(dynamic id) {
    for (final m in (app.view?['seats'] as List? ?? []).whereType<Map>()) {
      if (m['id'] == id) return m['name'] as String;
    }
    return '玩家';
  }

  Future<void> _nickname() async {
    final text = TextEditingController(text: app.nickname);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('朋友怎么称呼你？'),
        content: TextField(
          controller: text,
          maxLength: 24,
          autofocus: true,
          decoration: const InputDecoration(labelText: '昵称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) await app.setNickname(result);
  }

  Future<void> _create() async {
    final text = TextEditingController(text: '${app.nickname}的房间');
    var capacity = 6;
    var gameId = 'doudizhu_v1';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('摆好一张牌桌'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: text,
                  maxLength: 24,
                  decoration: const InputDecoration(labelText: '房间名字'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: gameId,
                  decoration: const InputDecoration(labelText: '选择游戏'),
                  items: const [
                    DropdownMenuItem(
                      value: 'doudizhu_v1',
                      child: Text('经典斗地主 · 三人'),
                    ),
                    DropdownMenuItem(
                      value: blackjackGameId,
                      child: Text('21 点 · 2–6 人'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => gameId = value ?? 'doudizhu_v1'),
                ),
                const SizedBox(height: 12),
                if (gameId == blackjackGameId)
                  DropdownButtonFormField<int>(
                    initialValue: capacity,
                    decoration: const InputDecoration(labelText: '座位数量'),
                    items: [
                      for (var i = 2; i <= 6; i++)
                        DropdownMenuItem(value: i, child: Text('$i 个座位')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => capacity = value ?? 6),
                  ),
                const SizedBox(height: 14),
                Text(
                  gameId == 'doudizhu_v1'
                      ? '固定三人 · 54 张牌 · 叫抢地主 · 炸弹翻倍'
                      : '2–6 人 · 要牌或停牌 · 对庄家 · 仅房间积分',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('创建房间'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await app.createRoom(
        text.text,
        gameId == 'doudizhu_v1' ? 3 : capacity,
        gameId: gameId,
      );
    }
  }

  Future<void> _manual() async {
    final text = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('备用地址连接'),
        content: TextField(
          controller: text,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '房主提供的地址',
            hintText: '192.168.1.2:54321',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('连接'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await app.joinAddress(result.trim());
    }
  }

  Future<void> _connectionHelp() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('一起检查一下连接'),
      content: const SingleChildScrollView(
        child: Text(
          '1. 所有人连接同一个 Wi-Fi，或同一个人的手机热点。\n\n2. 房主先创建房间，并保持游戏在前台。\n\n'
          '3. 在系统设置中允许本软件访问本地网络。\n\n4. 酒店、访客 Wi-Fi 可能隔离设备，可以换用朋友的手机热点。\n\n'
          '5. 搜索仍无结果时，可请房主查看“备用连接地址”，再手动连接。手动地址也无法解决设备之间被网络隔离的问题。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
  Future<void> _addresses() async {
    final addresses = await app.hostAddresses();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('备用连接地址'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('通常搜索房间即可加入。以下来自本机网络接口，请使用 Wi-Fi 或热点对应的地址。'),
              const SizedBox(height: 16),
              if (addresses.isEmpty) const Text('没有发现可用地址，请检查 Wi-Fi 或热点。'),
              for (final address in addresses)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: SelectableText(address),
                  trailing: IconButton(
                    tooltip: '复制地址',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: address)),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _leave() async {
    if (await _confirm(
      app.isHost ? '关闭这个房间？' : '离开这个房间？',
      app.isHost
          ? '房主退出后，大家需要重新组房。'
          : app.connected
          ? '主动离开会释放你的座位。短暂切后台无需主动离开。'
          : '当前无法通知房主释放座位。退出将清除本机重连信息，请让房主手动移出你的座位。',
    )) {
      await app.leave();
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
}

String _phase(dynamic phase) => switch (phase) {
  'playing' => '游戏中 · 新人等待下一局',
  'paused' => '暂停中',
  'finished' => '等待下一局',
  _ => '等待开始',
};

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE3E7DE)),
    ),
    child: child,
  );
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFE9EEE3),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: green, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13, height: 1.6)),
        ),
      ],
    ),
  );
}

class BadgeLabel extends StatelessWidget {
  const BadgeLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFE9EEE3),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: const TextStyle(fontSize: 11, color: green)),
  );
}

class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.primary = false,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? .45 : 1,
    child: Material(
      color: primary ? green : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: primary ? green : const Color(0xFFE3E7DE)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(icon, size: 34, color: primary ? Colors.white : green),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: primary ? Colors.white : ink,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: primary ? const Color(0xFFDAE9DF) : muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: primary ? Colors.white : green,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PlayingCard extends StatelessWidget {
  const PlayingCard({
    super.key,
    required this.card,
    this.selected = false,
    this.compact = false,
    this.onTap,
  });
  final int card;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    const suits = ['♠', '♥', '♣', '♦'];
    const ranks = [
      'A',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      'J',
      'Q',
      'K',
    ];
    final suit = card ~/ 13;
    final label = '${ranks[card % 13]}${suits[suit]}';
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? const Color(0xFFE5EDE1) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
            color: selected ? green : const Color(0xFFD5DDD2),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: compact ? 52 : 56,
            height: compact ? 72 : 82,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 28,
                    child: FittedBox(
                      child: Text(
                        ranks[card % 13],
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: suit.isOdd ? const Color(0xFFB3453E) : ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  CustomPaint(
                    size: const Size(16, 18),
                    painter: _SuitPainter(
                      suit,
                      suit.isOdd ? const Color(0xFFB3453E) : ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vector suits avoid missing Unicode glyphs on different device fonts.
class _SuitPainter extends CustomPainter {
  const _SuitPainter(this.suit, this.color);
  final int suit;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    final paint = Paint()..color = color;
    final path = Path();
    switch (suit) {
      case 0:
        path.moveTo(.5, .03);
        path.cubicTo(.34, .28, .03, .37, .06, .58);
        path.cubicTo(.08, .79, .35, .82, .5, .61);
        path.cubicTo(.65, .82, .92, .79, .94, .58);
        path.cubicTo(.97, .37, .66, .28, .5, .03);
        path.close();
      case 1:
        path.moveTo(.5, .95);
        path.cubicTo(.28, .73, .03, .53, .03, .3);
        path.cubicTo(.03, .02, .4, -.03, .5, .24);
        path.cubicTo(.6, -.03, .97, .02, .97, .3);
        path.cubicTo(.97, .53, .72, .73, .5, .95);
        path.close();
      case 2:
        canvas.drawCircle(const Offset(.5, .24), .22, paint);
        canvas.drawCircle(const Offset(.25, .53), .24, paint);
        canvas.drawCircle(const Offset(.75, .53), .24, paint);
      case 3:
        path.moveTo(.5, .02);
        path.lineTo(.96, .5);
        path.lineTo(.5, .98);
        path.lineTo(.04, .5);
        path.close();
    }
    canvas.drawPath(path, paint);
    if (suit == 0 || suit == 2) {
      canvas.drawPath(
        Path()
          ..moveTo(.48, .53)
          ..lineTo(.3, .97)
          ..lineTo(.7, .97)
          ..lineTo(.52, .53)
          ..close(),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SuitPainter oldDelegate) =>
      oldDelegate.suit != suit || oldDelegate.color != color;
}
