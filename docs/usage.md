# 使用与开发

「一起出牌」是免费、无广告、无账号的局域网卡牌 App，不使用云端牌局服务。支持 [斗地主](doudizhu.md) 和 [21 点](blackjack.md)；原轮流出牌模块保留用于测试与旧版兼容，不在创建菜单展示。

## 同桌游玩

1. 安装同一版本 App，连接同一个 Wi-Fi 或手机热点。
2. 一人点击「创建房间」并选择游戏；其他人点击「搜索房间」加入。手动地址仅备用。
3. 全员准备，房主开局。尽量保持 App 在前台；短暂断线时保留座位，原房主进程结束则需重新组房。

本机 APK 说明见 [安装包记录](../dist/README.md)。编译和签名通过不等于真机 Wi-Fi / 热点兼容性通过，参见 [验证记录](verification.md)。

## 开发

使用 Flutter 3.47.8 / Dart 3.13.7，依赖锁定在 `pubspec.lock`。接手先读 [项目交接记录](HANDOFF.md) 和根目录 `AGENTS.md`。

```sh
flutter pub get
dart analyze --format machine lib test tool
flutter test --reporter expanded
flutter build apk --release --target-platform android-arm64
```

Windows 本机可用 `tool/dev.ps1 check` / `tool/dev.ps1 release`，它会临时映射 ASCII 工作路径。iOS 需在 macOS 使用 Xcode 编译和签名；本项目未完成真机 iOS 安装。当前 Android release 用开发测试证书，正式应用商店签名需另行配置。GitHub Actions 提供手动验证入口，暂不随推送自动运行。

详见 [架构](architecture.md)、[协议](protocol.md)、[测试](testing.md) 与 [美术来源](../assets/README.md)。代码采用 MIT License；第三方依赖保留各自许可证。游戏运行不依赖模型 API。
