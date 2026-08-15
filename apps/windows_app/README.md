# 壹加音乐 Windows 应用

Windows 是主音乐库：导入文件或文件夹、管理歌单、播放本地歌曲，并在用户手动开启后提供同一 Wi-Fi 同步服务。

## 主要入口

- `lib/audio_import_service.dart`：复制、hash 去重、元数据/文件名识别和待整理命名。
- `lib/windows_audio_player.dart`：基于本机 `ffplay` 的播放、暂停、继续和进度跳转。
- `lib/sync_server.dart`：二维码会话、连接验证、歌单 manifest 和文件下载服务。
- `lib/main.dart`：Windows UI、播放器队列与同步模式。

## 验证

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows
```

构建结果位于 `build/windows/x64/runner/Release/`。完整 Release 目录必须一并分发；目标机器需要可启动 `ffplay` 才能在 Windows 端播放音乐。
