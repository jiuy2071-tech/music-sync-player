# 断点恢复说明

## 项目位置

```text
Git 仓库根目录
```

## 恢复顺序

1. 读取 `agent.md`、`README.md`、`GOALS.md`、`BLOCKERS.md` 和本文件。
2. 若要改业务规则，再读取 `docs\product_requirements.md` 和 `docs\technical_implementation.md`。
3. 先运行与改动范围相符的分析或测试；不要为了确认环境重复 Windows/Android 全量构建。

## 当前状态

- V1 的代码、自动验收、Windows 运行目录和 Android debug APK 已完成。
- Windows 验收入口：`release\windows\MusicSyncPlayer\YijiaMusic.exe`。
- Android 验收入口：`release\android\music_sync_player_v1_debug.apk`。
- 2026-07-26 已完成 Android 前两轮 P0 同步安全加固：临时下载、大小与 Hash 校验、SQLite 事务、正式文件备份替换、失败恢复、存储空间预检、20 秒网络超时和有限重试。
- 2026-07-26 已完成 Windows 权威歌单版本、Android 已同步歌单快照、空歌单显示、主端删除对账、引用判断和孤儿文件清理。
- 2026-07-26 Android `flutter analyze`、完整 `flutter test` 和 `flutter build apk --debug` 已通过。
- 2026-07-26 Windows `flutter analyze`、完整 `flutter test` 和 `flutter build windows` 已通过；Windows 完整运行目录和 Android APK 均已更新。
- 2026-07-26 Windows 已增加启动播放能力检测，缺少 `ffplay` 或 `ffprobe` 时会在底部播放器显示明确状态。
- 2026-07-26 最新 Android APK 已在模拟器保留数据覆盖安装并正常启动，无启动崩溃；实体手机覆盖安装后的显示与播放仍需人工确认。
- 2026-07-27 Android 已增加同步强制中断恢复清单与 SQLite 提交标记；APP 重启会自动恢复未提交的旧文件，或清理已提交事务留下的备份。
- 2026-07-27 真实磁盘旧数据库升级自动测试已通过，原有歌曲、歌单、成员关系和同步状态可保留。
- 2026-07-27 Android `flutter analyze`、14 项测试和 `flutter build apk --debug` 已通过；数据库 `flutter analyze` 与 10 项测试已通过；固定 APK 已更新。
- 2026-07-27 正式 Windows EXE 与 Android 模拟器已完成真实跨进程连接、整张歌单重复同步、无重复落盘和 Windows 退出后的离线播放验证。
- 2026-07-27 模拟器已完成真实空歌单同步与主端删除对账：空歌单可见，Windows 删除后 Android 移除 1 张旧快照且保留原歌单、歌曲和音频文件。
- 2026-07-27 模拟器已完成共用引用与成员变化回归：删除一张共用歌曲的临时歌单不会误删音频；歌单从 1 首改为 0 首后可重同步为空，原歌单仍保留歌曲。
- 2026-08-15 已完成公开仓库整理：MIT License、贡献/安全说明、CI、一键验证脚本和不含本机绝对交付路径的 README。
- 2026-08-15 已修复反斜杠搜索、超量下载中止、同步输入校验、服务端错误收口和 Windows 安全删除顺序。
- 2026-08-15 六个模块 `flutter analyze`、共 54 项测试、Windows 构建和 Android Debug APK 构建全部通过；固定 Windows 入口已启动验证。
- 2026-08-15 固定 APK 已在 Android Studio 模拟器覆盖安装，保留原有本地歌曲并进入音乐库，无启动崩溃；摄像头扫码仍未被模拟器替代。
- `manual_test_audio/` 是项目内生成的非敏感样本，已被 Git 忽略，不能提交。

## 下一步

代码安全项、公开仓库整理、旧数据库升级、模拟器跨进程同步、空歌单、主端删除对账、共用引用、成员变化与离线播放已经闭环。下一步是在实体手机确认相机扫码、真实 Wi-Fi、覆盖安装和断网离线播放体感，并按需要把预构建文件发布到 GitHub Releases。详细设计与负面测试见 `docs\sync_safety_plan.md`。保持 V1 范围，不扩展云同步、远程播放或 Android 主库编辑。

## 环境与交付注意事项

- Flutter 与 Android SDK 应通过本机标准命令行环境提供。
- Windows 本地播放要求目标机器可启动 `ffplay`。
- Android APK 是 debug 包；真机扫码、连接和离线播放尚未被自动测试替代。
