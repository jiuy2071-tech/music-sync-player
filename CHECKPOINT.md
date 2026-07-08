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

下一步从 Phase 7 继续：验收、修复和 release 交付。

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
