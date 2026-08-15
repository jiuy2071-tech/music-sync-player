# music_sync_protocol

壹加音乐的共享同步协议模型。

包含二维码载荷 `SyncQrPayload`、连接请求 `SyncConnectRequest` 和连接响应 `SyncConnectResponse`。当前协议标识为 `personal_music_sync`，版本为 `1`；二维码携带局域网主机、端口、临时会话 ID 和连接码。

运行检查：

```powershell
flutter analyze
flutter test
```
