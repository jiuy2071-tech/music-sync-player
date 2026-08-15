# Codex 恢复提示

本项目已经完成 V1 自动验证和交付整理，不要再从工程初始化或 Phase 1 开始。

开始任何新工作前：

1. 阅读 `agent.md`、`README.md`、`GOALS.md`、`BLOCKERS.md`、`CHECKPOINT.md`。
2. 需要变更需求或同步逻辑时，再阅读 `docs\product_requirements.md` 与 `docs\technical_implementation.md`。
3. 先检查 `git status`，不覆盖用户现有改动。
4. 每个有意义的修改完成后，运行对应测试/构建、更新必要文档、同步交付产物并提交 Git。

当前本地构建输出：

- Windows：`apps/windows_app/build/windows/x64/runner/Release/`
- Android：`apps/android_app/build/app/outputs/flutter-apk/app-debug.apk`

公开二进制文件只通过 GitHub Releases 分发，不提交本机 `release/` 或 `build/` 目录。

下一步优先做真实设备人工验收和修复。保持 V1 边界：只做同一 Wi-Fi 的 Windows -> Android 歌单同步和本地离线播放；不增加云同步、远程播放、USB、蓝牙、封面、歌词或 Android 主库编辑。
