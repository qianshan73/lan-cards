# 本次验证记录

## 本机复测与诊断包 — 2026-10-30（Asia/Shanghai）

- 源码提交 `3a8768c`：`tool/dev.ps1 check` 静态分析无诊断、116 项测试全部通过；32 个 Dart 文件格式检查通过。
- 首次 Android release 在 `compileFlutterBuildRelease` 遇到 `parent` 为 null 的构建异常。以临时 ASCII 盘符单独运行该 Gradle 任务成功，随后重跑 `tool/dev.ps1 release` 成功；未修改源码，也未确定首次异常的根因。
- `dist/lan-cards-0.2.0-diagnostics-arm64.apk`：21,070,597 字节，应用 ID `org.lancards.lan_cards`，版本 0.2.0 / versionCode 2，最低 API 24、目标 API 36。APK v2 签名与原版使用同一开发测试证书。包内含 arm64 Flutter 引擎及 AOT 代码；在 AOT 中检查到诊断报告标记，原版无此标记。SHA-256 见同目录校验文件。
- 未在手机或模拟器上安装运行，未验证原生发现、Wi-Fi / 热点互通或 iOS 构建。2026-11-08 按用户要求延后测试，仅补记上述已完成的结果。

## 局域网发现诊断 — 2026-10-30（Asia/Shanghai，源码修改）

### 已实现

- 搜索启动与房间发布独立状态：未运行、启动中、已启动、失败；原生已知错误映射为权限、不支持、繁忙或未确定的平台错误。
- 显式原生服务解析，无地址 / 无有效端口 / 解析失败与 HTTP 失败分阶段统计；HTTP 区分超时、连接失败、非成功状态、无效格式 / 协议、超长响应与无效手动端点。
- 搜索页直接显示可操作提示；搜索 / 恢复 / 两种牌桌有诊断入口；注册失败持久提示不被普通游戏操作清空，可重试发布。
- 用户主动复制固定字段报告；只有白名单枚举和计数，无自动日志 / 持久化 / 上传，不包含地址、服务 / TXT、房间名 / ID、身份、凭证、原始异常、响应体或手牌。详见 `discovery-diagnostics.md`。

### 已执行的本机验证

- `tool/dev.ps1 check`：静态分析无诊断，完整 **116 项测试通过**（原有 93 项 + 新增 23 项）。
- `dart format --output=none --set-exit-if-changed lib test tool`：32 个文件，零格式变化；Git 差异空白检查通过。
- 中途直接从中文原路径重跑时，native-assets hooks 引用了已撤销的临时盘符而未能启动测试；最终通过 `tool/dev.ps1 check` 重新映射 / 解析依赖后完整通过。此为本机工具缓存路径问题，不是原生发现测试结果。
- 新增 `discovery_test.dart` 18 项：原生启动错误分类与重试、注册失败与恢复、停止后的迟到资源释放、无地址与解析失败、最近批次计数替换、停止后旧 HTTP 结果失效。
- HTTP 测试使用真实本机 Socket，覆盖成功、超时、连接拒绝、非 200、拒绝跟随重定向、格式 / 协议 / UTF-8 错误、8192 字节上限、手动结果与自动批次分离。恶意测试字段 / 原始异常文本和端点不进入脱敏报告；报告计数不可修改。
- 新增 `discovery_ui_test.dart` 4 项：HTTP 失败的行动建议、搜索失败与重试 / 复制脱敏报告、无地址提示、斗地主发布失败入口；覆盖 667×320 小横屏，无布局异常。原生调用用替身，不把 Widget 测试当作手机系统权限验证。
- `controller_test.dart` 新增 1 项：真实本机房间在发布失败后仍可操作，诊断在准备操作后保留，重试发布不重建房间。

### 仍未执行 / 不作结论

- 未连接真机；没有验证 Android NSD / iOS Bonjour、原生解析、实际权限弹窗 / 设置转换、普通 Wi-Fi、无互联网 Wi-Fi、Android / iPhone 热点、组播限制或客户端隔离。测试替身和本机 HTTP 不能证明任何真机组合已兼容。
- 诊断源码提交时未重新构建 APK；后续诊断包构建见上方。`dist/lan-cards-0.2.0-arm64.apk` 及旧预览仍属于 2026-10-28 的产物，不含诊断功能。
- Windows 环境未执行 iOS 编译、签名或安装；未触发远程 CI。
- 按 `testing.md` 网络矩阵收集设备 / 系统 / 构建版本、网络类型、热点提供者、权限步骤、发现与加入各自结果及脱敏报告，之后再更新兼容性结论。

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
