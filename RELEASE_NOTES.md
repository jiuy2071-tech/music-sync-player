# 壹加音乐 V1 开发版说明

## 2026-08-15 开源整理版

本次把原本面向单机开发环境的项目整理为可以公开阅读、克隆和参与贡献的仓库。源码分支不包含 APK、EXE、ZIP、SDK、音乐样本、数据库或构建缓存；公开二进制文件应通过 [GitHub Releases](https://github.com/YZCore/music-sync-player/releases) 单独分发。

### 主要变化

- README 改为标准源码运行和构建说明，不再把某台电脑的绝对路径写成交付入口。
- 增加 MIT License、贡献说明、安全报告方式、GitHub Actions CI 和一键验证脚本。
- 清理 Flutter 模板描述与占位许可证，`packages/player` 改为正式播放状态和播放器契约。
- `sqlite3` 升级到 `3.5.1`，移除已经失效的 `sqlite3_flutter_libs`；`mobile_scanner` 升级到 `7.4.0`。
- 搜索会把 `%`、`_` 和反斜杠都按普通字符处理。
- Android 下载过程中会限制实际字节数；服务端发送内容超过 manifest 声明大小时立即停止，不再等超大文件完整落盘。
- 二维码、连接请求和连接响应增加字段、端口、会话与连接码格式检查。
- Windows 同步服务限制连接请求大小，返回通用错误，不向局域网客户端暴露内部异常文本。
- Windows 删除歌曲时先确认应用管理的副本能够删除，再移除数据库记录；源文件仍不会被删除。
- 新安装的 Windows 音乐库默认使用当前用户应用数据目录，同时兼容旧版目录和环境变量。

### 已实现功能

- Windows：MP3、FLAC、M4A、WAV 文件/文件夹导入、Hash 去重、待整理命名、整库删除、歌单、搜索、本地播放和播放队列。
- Windows：临时 Wi-Fi 同步模式、二维码、连接码、权威歌单清单、manifest 和受限音频下载。
- Android：扫码或手动粘贴连接、整张歌单同步、已同步内容搜索、本地缓存删除和离线播放。
- 同步安全：临时下载、大小与 SHA-256 校验、SQLite 事务、中断恢复、空间预检、有限重试、歌单版本对账和孤儿清理。

### 本次验证

- 四个共享包和两个应用的 `flutter analyze` 全部通过。
- 共 54 项自动测试通过：共享包 20 项、Windows 18 项、Android 16 项。
- `flutter build windows` 通过。
- `flutter build apk --debug` 通过。
- 从本机固定验收目录启动 Windows EXE 成功。
- 本次 Android APK SHA-256：`FDADF39B4972E9F0293BD4CD94C34ED9A116154F46E2322767F2DA8697C4FEA1`。

标准构建输出：

```text
apps/windows_app/build/windows/x64/runner/Release/
apps/android_app/build/app/outputs/flutter-apk/app-debug.apk
```

### 已知限制

- Android APK 仍是 Debug 包，没有应用商店发布签名。
- 本次固定 APK 已在现有 Android Studio 模拟器上通过 `adb install -r` 覆盖安装，保留原有本地歌曲并正常进入音乐库；启动日志没有 Android 或 Flutter 崩溃。
- `mobile_scanner 7.4.0` 当前可以构建，但 Flutter 提示该插件未来需要迁移到 Built-in Kotlin；后续升级 Flutter 时需要继续关注插件发布说明。
- 实体手机上的首次相机权限、二维码扫描、真实 Wi-Fi、覆盖安装和断网离线播放仍需要人工确认；模拟器升级启动不能替代真机验收。
- Windows 本地播放依赖目标机器可启动 `ffplay`；没有 `ffprobe` 时部分歌曲时长可能无法提前读取。

## V1 范围外

云同步、公网远程播放、USB、蓝牙、封面、歌词、推荐、社交、多用户登录、Android 编辑歌单、Android 导入音乐和 Android 同步回电脑均不在 V1 内。
