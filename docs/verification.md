# 本次验证记录

## 0.2.0 — 2026-10-28（Asia/Shanghai）

- 静态分析：`dart analyze --format machine lib test tool`，无诊断。
- 格式检查通过；完整测试 **93 项通过**，包含 20 个随机种子的完整斗地主牌局、三条真实客户端连接的叫抢 / 暂停 / 恢复 / 结算 / 下一局。
- UI 测试覆盖 667×320、844×390、1024×768，点击划选、20 张手牌、叫抢、暂停与再开局。
- 实际 Flutter 预览渲染通过，人工查看横屏首页、叫抢、出牌和结算截图；没有使用概念图冒充运行界面。
- `tool/dev.ps1 release`：Android arm64 release 构建成功，版本 0.2.0 / versionCode 2，最低 API 24，目标 API 36。
- APK v2 签名校验通过，与 0.1.0 的测试签名一致；安装包 21,070,425 字节，约 20.1 MiB。
- 检查安装包包含 arm64 AOT 代码和离线背景素材；源码凭证扫描无匹配。
- Kimi K2.6 实际返回前端初稿，经过本地修正和测试后接入；未把调用凭证写入项目或安装包。
- 仍未连接真实 Android / iPhone 设备，未验证原生发现、真机安全存储和热点互通；未在 Windows 上声称完成 iOS 编译或签名。

## 0.1.0 — 历史记录

日期：2026-10-27（Asia/Shanghai）

## 已执行

- Flutter 3.47.8 / Dart 3.13.7。
- `dart format --output=none --set-exit-if-changed lib test tool`：通过。
- `flutter analyze --no-pub`：无问题（ASCII 工作路径）。
- `flutter test --no-pub --reporter expanded`：32 项通过。
- `flutter test tool/render_preview_test.dart --no-pub`：通过，生成实际 Flutter 界面预览，并进行人工查看。
- `flutter build apk --debug --no-pub --target-platform android-arm64`：通过。
- APK 的 v2 签名验证：通过；应用 ID `org.lancards.lan_cards`，版本 0.1.0，最低 Android API 24，目标 API 36，Flutter 引擎为 arm64-v8a。
- 测试包位于 dist/，约 84.6 MiB；SHA-256 校验文件一并提供。

首次 Android 构建发现 Kotlin 增量缓存不能处理项目盘符与 Pub 缓存盘符不同的问题。已关闭 Kotlin 增量缓存并重新构建成功。Socket 测试还发现关闭中的 WebSocket sink 与 readyState 之间的竞态，已增加发送保护并重新通过测试。

## 未执行

- 没有连接的 Android 测试设备，因此未执行实际安装启动、原生安全存储、原生 NSD 和多手机热点互通验收。
- 当前是 Windows 主机，未执行 iOS 编译、签名、安装或 Bonjour 真机验收。
- 已提供 CI 工作流，但未推送远程仓库、未触发远程 CI。

详细真机矩阵见 testing.md。后续验证时应补充具体设备、系统版本和网络类型，而不是用模拟测试替代真机结果。
