# 断点恢复说明

## 当前工作目录

```text
D:\Projects\music_sync_player
```

## 恢复后先读

1. `agent.md`
2. `codex_start_prompt.md`
3. `docs\product_requirements.md`
4. `docs\technical_implementation.md`
5. `README.md`
6. `GOALS.md`
7. `DEV_LOG.md`
8. `BLOCKERS.md`

## 当前阶段

下一步从 Phase 7 继续：真机验收和 release 交付整理。

已完成 Phase 7 自动验收：
- 已在 `manual_test_audio/` 生成非敏感 MP3、FLAC、M4A、WAV 测试音频。
- Windows 端导入、文件夹导入、命名规则、重复文件、播放探测、同步服务测试通过。
- Android 端同步客户端测试通过。
- Windows exe 和 Android debug APK 均可构建。

仍需人工确认：
- Windows 文件选择器和文件夹选择器真实点击流程。
- Android 真机连接 Windows 同步服务。
- Android 真机断网或关闭同步模式后的离线播放。

## 常用验证命令

Windows 端：

```powershell
cd D:\Projects\music_sync_player\apps\windows_app
flutter analyze
flutter build windows
```

Android 端：

```powershell
cd D:\Projects\music_sync_player\apps\android_app
flutter analyze
flutter build apk --debug
```

共享包：

```powershell
cd D:\Projects\music_sync_player\packages\core
dart analyze

cd D:\Projects\music_sync_player\packages\database
dart analyze
```
