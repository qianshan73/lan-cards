import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../network/discovery_diagnostics.dart';

String _failureAdvice(DiscoveryFailure? failure) => switch (failure) {
  DiscoveryFailure.permission => '系统报告权限问题。请在系统设置允许本地网络权限，回到 App 后重试。',
  DiscoveryFailure.unsupported => '系统报告不支持此发现操作。可使用备用连接地址，并记录设备和系统版本。',
  DiscoveryFailure.busy => '系统发现服务繁忙。请稍候重试，或关闭重复运行的发现应用后再试。',
  _ => '请检查本地网络权限、Wi-Fi / 热点连接后重试；仍失败可使用备用连接地址。',
};

String _probeAdvice(ProbeFailure failure) => switch (failure) {
  ProbeFailure.timeout => '连接超时：请房主保持 App 前台，确认同一 Wi-Fi / 热点；检查热点或访客网络是否隔离设备。',
  ProbeFailure.network => '连接失败：地址可能已变化，或网络不允许设备互通。请重新搜索，必要时更换 Wi-Fi / 热点。',
  ProbeFailure.httpStatus => '房间接口未成功响应：请房主确认房间仍开启，再重新搜索。',
  ProbeFailure.invalidResponse => '房间响应格式或协议不匹配：请双方使用相同版本 App 并重新开房。',
  ProbeFailure.tooLarge => '房间响应超过大小限制，已停止读取：请确认连接的是本 App 房间并更新双方版本。',
  ProbeFailure.invalidEndpoint => '连接地址或端口无效：请核对房主显示的备用连接地址。',
};

String _stageLabel(DiscoveryStage stage) => switch (stage) {
  DiscoveryStage.idle => '未运行',
  DiscoveryStage.starting => '启动中',
  DiscoveryStage.active => '已启动',
  DiscoveryStage.failed => '失败',
};

/// Presentation only: never changes seating, game state or recovery decisions.
class DiscoveryDiagnosticsPanel extends StatelessWidget {
  const DiscoveryDiagnosticsPanel({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final d = app.discovery.diagnostics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('DNS-SD 搜索：${_stageLabel(d.search)}'),
        if (d.search == DiscoveryStage.failed)
          Text('搜索启动失败。${_failureAdvice(d.searchFailure)}'),
        if (app.isHost || d.publication != DiscoveryStage.idle) ...[
          Text('DNS-SD 房间发布：${_stageLabel(d.publication)}'),
          if (d.publication == DiscoveryStage.failed)
            Text('房间发布失败，朋友可能搜索不到。${_failureAdvice(d.publicationFailure)}'),
          if (app.isHost && d.publication != DiscoveryStage.active)
            TextButton(
              onPressed: d.publication == DiscoveryStage.starting
                  ? null
                  : () => unawaited(app.retryPublication()),
              child: const Text('重新发布房间'),
            ),
        ],
        Text(
          '发现服务 ${d.servicesSeen} · 已检查 ${d.servicesChecked} · 可访问房间 ${d.roomsReachable}',
        ),
        if (d.servicesSeen > d.servicesChecked)
          const Text('单次最多检查 32 个服务；当前统计不代表检查了全部服务。'),
        if (d.noUsableAddress > 0)
          Text('有 ${d.noUsableAddress} 个服务未取得可用地址或端口。请房主保持前台并重新发布；仍失败可尝试备用地址。'),
        if (d.failedProbes > 0)
          Text('有 ${d.failedProbes} 个服务的 HTTP 房间检查失败（尚未加入房间）。'),
        for (final reason in ProbeFailure.values)
          if ((d.probeFailures[reason] ?? 0) > 0)
            Text('${d.probeFailures[reason]} 个：${_probeAdvice(reason)}'),
        if (d.manualProbeFailure case final reason?)
          Text('手动地址检查：${_probeAdvice(reason)}'),
        if (d.search == DiscoveryStage.active && d.servicesSeen == 0)
          const Text('发现已启动，但尚未收到服务；请确认房主已开房。也可能是网络限制了组播，不能据此判断是否处于同一网络。'),
        const SizedBox(height: 8),
        const Text('统计仅为最近一次检查，不代表真机兼容性通过；不记录地址、房间名、凭证或手牌。'),
      ],
    );
  }
}

class DiscoveryDiagnosticsButton extends StatelessWidget {
  const DiscoveryDiagnosticsButton({super.key, required this.app, this.color});
  final AppController app;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final failed =
        app.discovery.diagnostics.publication == DiscoveryStage.failed;
    return IconButton(
      tooltip: failed ? '房间发布失败 · 局域网诊断' : '局域网诊断',
      icon: Icon(
        failed ? Icons.wifi_off_rounded : Icons.network_check_rounded,
        color: failed ? Colors.orange : color,
      ),
      onPressed: () => showDiscoveryDiagnostics(context, app),
    );
  }
}

Future<void> showDiscoveryDiagnostics(
  BuildContext context,
  AppController app,
) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => AlertDialog(
      title: const Text('局域网诊断'),
      content: SingleChildScrollView(
        child: DiscoveryDiagnosticsPanel(app: app),
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(
            ClipboardData(text: app.discovery.diagnostics.safeReport()),
          ),
          child: const Text('复制脱敏诊断'),
        ),
        TextButton(
          onPressed: app.discovery.searching
              ? null
              : () => unawaited(app.discovery.startSearch()),
          child: const Text('重新搜索'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  ),
);
