# 局域网协议 v1

## 发现

- 服务类型：`_lancards._tcp`
- 实例名：`lancards-<随机房间标识前缀>`
- TXT：`room`（roomId）、`v=1`，无任何认证凭据。
- 地址由系统 DNS-SD 解析。`GET /room` 返回最新的公开房间概况。
- 概况字段：protocol、roomId、name、gameId、gameTitle、capacity、occupied、online、phase。
- occupied 包含离线保留座位。空位可加入，不等同于正在进行的牌局允许中途参与。

## WebSocket /play

新玩家握手：

```json
{"type":"hello","protocol":1,"roomId":"ROOM_ID","name":"小红","supportedGames":["doudizhu_v1","round_robin_v1"]}
```

恢复已有身份：

```json
{"type":"hello","protocol":1,"roomId":"ROOM_ID","playerId":"PLAYER_ID","token":"PRIVATE_RESUME_TOKEN","supportedGames":["doudizhu_v1","round_robin_v1"]}
```

握手成功的 `welcome` 只发给本人，包含 roomId、playerId、token、view。身份凭据写入系统安全存储，不能写入发现数据。

从 0.2.0 起，主机在分配座位之前检查 supportedGames。不包含该规则的客户端收到 unsupported_game，避免旧界面误入新游戏。缺少此字段的旧版客户端仅允许加入 round_robin_v1 测试房间。

斗地主使用通用 play 命令：叫抢载荷为 `{"type":"bid","bid":"call|rob|pass","roundId":"ROUND_ID"}`，出牌载荷为 `{"type":"play","cards":[2,15],"roundId":"ROUND_ID"}`，不出载荷为 `{"type":"pass","roundId":"ROUND_ID"}`。对照 doudizhu.md 的具体规则。

普通命令：

```json
{"type":"command","requestId":"UNIQUE_REQUEST_ID","command":"ready","payload":{"ready":true}}
```

命令：`ready`、`start`、`play`、`abort`、`kick`、`leave`。

```json
{"type":"command","requestId":"UNIQUE_REQUEST_ID","command":"play","payload":{"type":"play","roundId":"ROUND_ID","card":12}}
```

主机响应：

- `ack`：requestId。
- `error`：code、message、可选 requestId。
- `state`：view，本人可见的当前完整快照。
- `removed`：已离开或被踢出，应清除恢复凭据。
- `room_closed`：房主显式关闭房间。
- `replaced`：同一身份已在另一条连接上恢复，停止当前连接重试。

view 包含房间概况、revision、you、hostId、roundId、seats、offlineParticipants、lastResult、game。seats 只含公开身份信息，不包含 token。

测试游戏 game 只包含本人 hand、公开 handCounts、出过的 table、participants、turnPlayer、finished、winner、waitingNextRound；绝不包含完整 hands 映射。

## 限制

- 8 秒未完成握手关闭连接。
- 客户端请求上限 16 KiB 文本；二进制请求不被执行。
- 每成员最近 256 个成功 requestId 防重；不是无限期的持久化幂等日志。
- WebSocket 心跳间隔 4 秒，断线后客户端每约 3 秒尝试恢复，均不显示处罚倒计时。
- 相同昵称不代表同一人；相同 roomId 才是恢复目标。
