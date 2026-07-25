# 断点恢复说明

## 项目位置

```text
D:\Projects\music_sync_player
```

## 恢复顺序

1. 读取 `agent.md`、`README.md`、`GOALS.md`、`BLOCKERS.md` 和本文件。
2. 若要改业务规则，再读取 `docs\product_requirements.md` 和 `docs\technical_implementation.md`。
3. 先运行与改动范围相符的分析或测试；不要为了确认环境重复 Windows/Android 全量构建。

## 当前状态

- V1 的代码、自动验收、Windows 运行目录和 Android debug APK 已完成。
- Windows 验收入口：`release\windows\MusicSyncPlayer\YijiaMusic.exe`。
- Android 验收入口：`release\android\music_sync_player_v1_debug.apk`。
- 2026-07-18 最近一次自动验证已通过 Windows 与 Android 的 `flutter analyze`、`flutter test` 和对应构建命令。
- `manual_test_audio/` 是项目内生成的非敏感样本，已被 Git 忽略，不能提交。

## 下一步

只进行真实设备人工验收：Windows 选择器、Android 扫码、同一 Wi-Fi 同步和 Android 离线播放。发现问题时保持 V1 范围，不扩展云同步、远程播放或 Android 主库编辑。

## 环境与交付注意事项

- Flutter：`D:\Dev\flutter`；Android SDK：`D:\Android\Sdk`。
- Windows 本地播放要求目标机器可启动 `ffplay`。
- Android APK 是 debug 包；真机扫码、连接和离线播放尚未被自动测试替代。
