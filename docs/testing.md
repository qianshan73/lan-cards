# 测试与真机验收

## 自动化

```
flutter pub get
dart analyze --format machine lib test
flutter test --reporter expanded
```

- room_test：座位保留、跨局保留、人数、隐藏信息、权限、出牌合法性、重复命令、旧局命令、完整下一局。
- network_test：真实本机 HTTP / WebSocket，加入、发牌、断线、换客户端恢复、连接替换竞态、踢人、伪造身份、坏消息、关闭房间。
- controller_test：单房间限制、持久化身份恢复、主机冷启动、失效凭证清理。
- discovery_test：原生启动 / 注册错误与重试（替身）、解析失败 / 无地址、HTTP 分类（真实本机 Socket）、脱敏报告、停止后的异步竞态。
- discovery_ui_test：局域网诊断提示、小横屏入口、重试和复制脱敏报告；controller_test 另覆盖发布失败不影响本机房间及原地重试。
- ui_test：390×844、320×568、844×390 布局，首页提示、搜索入口和座位选择。
- doudizhu_test：14 类牌型、非法牌型、叫抢与反抢、重新发牌、阵营、翻倍、春天与反春、20 个种子的完整自动出牌过程。
- doudizhu_network_test：三条真实客户端连接完成叫抢、发牌、暂停、原身份恢复、出完整局、结算和下一局。
- doudizhu_ui_test：667×320、844×390、1024×768，叫抢按钮、20 张手牌、点击划选、提示提交、暂停控制与结算后再开局。

测试中只有系统存储与原生 DNS-SD 用替身；网络集成测试使用真实 Socket。

发现诊断的解释、隐私边界与真机记录方式见 [discovery-diagnostics.md](discovery-diagnostics.md)。自动化诊断通过不等于 NSD / Bonjour / 热点兼容性通过；当前已有安装包不包含新增诊断，检查前先重新构建。

## 真机矩阵（未执行的项目不应标记已通过）

| 网络 | 房主 | 加入方 | 核心检查 |
|---|---|---|---|
| 同一普通 Wi-Fi | Android | iPhone + Android | 自动发现、点选加入、全局流程 |
| 同一普通 Wi-Fi | iPhone | Android + iPhone | 反向开房、权限、前台运行 |
| Android 热点 | 热点手机自身 | iPhone + Android | 热点主机能否发布与接收连接 |
| Android 热点 | 另一台手机 | 其他设备 | 热点下客户端之间是否互通 |
| iPhone 热点 | 热点手机自身 | Android + iPhone | 发现与实际连接分别验证 |
| iPhone 热点 | 另一台手机 | 其他设备 | 热点隔离或组播限制 |
| 无互联网的路由器 | 任一平台 | 两种平台 | 不因外网断开禁止开房 |

每组都覆盖：

1. 开房、发现、加入、昵称、座位、准备、完整结束、下一局。
2. 客户端断网：占座、暂停、恢复原手牌，全部本局参与者恢复后自动继续。
3. 客户端 App 进程关闭后再打开：只要主机仍在，自动恢复原座位。
4. 离线保留座位已满时，新玩家不能顶替。
5. 有空位时中途加入，新人等待下一局。该新人离线不能暂停当前局。
6. 房主终止暂停中的本局：不计分，房间与离线座位仍在。
7. 房主踢出：座位释放，原凭证重连失败。
8. 房主 App 进程结束：不发生主机迁移，客户端可以退出重新组房。
9. 拒绝本地网络权限，再在设置中允许并重试。
10. 房间发布消失、旧列表条目、连接期间座位刚被其他人占满。
11. 手动连接备用地址；网络隔离时不误报一定能连接。

## UI 预览

Windows 上可运行 `flutter test tool/render_preview_test.dart --no-pub` 生成 docs/preview-home.png 和 docs/preview-room.png。预览脚本只读取系统字体，不将系统字体复制进项目。

横屏斗地主的六种状态由 `flutter test tool/render_doudizhu_preview_test.dart --no-pub` 生成到 docs/ddz-*.png。
