# 本次验证记录

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
