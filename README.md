<p align="center">
  <img src="apps/windows_app/assets/branding/yijia_music_logo.png" width="112" alt="壹加音乐 Logo">
</p>

# 壹加音乐

[![CI](https://github.com/jiuy2071-tech/music-sync-player/actions/workflows/ci.yml/badge.svg)](https://github.com/jiuy2071-tech/music-sync-player/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-2c664c.svg)](LICENSE)

壹加音乐是一个基于 Flutter 的 Windows + Android 本地音乐同步播放器。Windows 保存主音乐库，Android 通过同一 Wi-Fi 按整张歌单同步，之后可以断网离线播放。整个流程不依赖云端，也不会把音乐上传到第三方服务。

## 主要功能

- Windows 导入 MP3、FLAC、M4A、WAV 文件或文件夹，复制保存并按 SHA-256 去重。
- 根据音频标签或文件名整理标题；无意义名称进入“未命名音频”待整理区。
- Windows 歌单、搜索、播放队列、播放/暂停、上一首/下一首和进度跳转。
- Windows 手动开启局域网同步服务，生成临时二维码和六位连接码。
- Android 扫码或粘贴连接信息，按整张歌单下载到 APP 私有目录。
- Android 只显示已同步内容，支持搜索、删除本地缓存和离线播放。
- 同步包含文件大小与 Hash 校验、磁盘空间预检、数据库事务、有限重试和中断恢复。

## 项目状态

V1 主流程、自动测试、Windows 构建和 Android Debug APK 构建已经跑通。Android Studio 模拟器已经完成真实跨进程同步与离线播放验证；实体手机上的相机扫码、同一 Wi-Fi 连接和断网播放仍需要人工确认，详见 [testing_notes.md](testing_notes.md)。

本项目仍处于个人项目的早期公开阶段。同步服务使用局域网 HTTP 和一次性会话信息，不适合暴露到公网。安全边界见 [SECURITY.md](SECURITY.md)。

## 获取项目

```powershell
git clone https://github.com/jiuy2071-tech/music-sync-player.git
cd music-sync-player
```

公开的预构建版本应从 [GitHub Releases](https://github.com/jiuy2071-tech/music-sync-player/releases) 下载。若 Releases 页面尚无对应附件，请按下面的源码方式运行或构建；仓库不会提交 `build/`、APK、EXE、ZIP、SDK 或本机缓存。

## 环境要求

- Flutter `3.44.5` 或与 `pubspec.lock` 兼容的更新稳定版。
- Windows 10/11 和 Visual Studio 的“使用 C++ 的桌面开发”组件。
- Android Studio 或可用的 Android SDK；Android 端需要相机权限用于扫码。
- Windows 本地播放需要 `ffplay`；安装 `ffprobe` 后还能预读更多音频时长。它们通常随 FFmpeg 提供，但本项目不会自动安装大型工具。

## 运行 Windows 端

```powershell
cd apps/windows_app
flutter pub get
flutter run -d windows
```

构建 Windows 版本：

```powershell
flutter build windows
```

构建结果位于 `apps/windows_app/build/windows/x64/runner/Release/`。运行时必须保留整个目录，不能只复制其中的 EXE。

新安装默认把应用音乐库放在当前 Windows 用户的应用数据目录。可在启动前设置 `YIJIA_MUSIC_LIBRARY`，把音乐库放到自定义位置：

```powershell
$env:YIJIA_MUSIC_LIBRARY = '<your-library-folder>'
flutter run -d windows
```

导入操作只复制文件，不移动或删除原始音乐。应用内“删除歌曲”只删除应用管理的副本，不会删除最初导入的源文件。

## 运行 Android 端

先启动 Android 模拟器或连接已开启 USB 调试的设备，然后运行：

```powershell
cd apps/android_app
flutter pub get
flutter run
```

构建 Debug APK：

```powershell
flutter build apk --debug
```

APK 位于 `apps/android_app/build/app/outputs/flutter-apk/app-debug.apk`。这是调试包，不是用于应用商店发布的签名正式包。

## Wi-Fi 同步

1. 让 Windows 电脑和 Android 手机连接同一个可信 Wi-Fi。
2. Windows 端打开“Wi-Fi 同步”，点击“开启同步模式”。
3. Android 端打开“同步音乐”，扫描 Windows 显示的二维码。
4. 摄像头扫码不方便时，在 Windows 复制完整连接信息，再到 Android 展开手动连接并粘贴。
5. 连接成功后选择整张歌单同步。关闭 Windows 或断开网络后，Android 继续播放已经保存到本机的歌曲。

连接码和会话 ID 只在本次同步模式中有效。同步完成后建议关闭 Windows 同步模式。

## 工程结构

```text
apps/windows_app/       Windows 主音乐库、播放和同步服务
apps/android_app/       Android 同步客户端和离线播放器
packages/core/          共享歌曲、歌单和错误模型
packages/database/      SQLite 数据库与搜索
packages/player/        共享播放状态和播放器契约
packages/sync_protocol/ 二维码与连接协议模型
docs/                   产品、技术和同步安全说明
scripts/                本地验证脚本
```

## 检查与测试

在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1
```

该脚本会依次对四个共享包和两个应用执行 `flutter pub get`、`flutter analyze` 与 `flutter test`。Windows 和 Android 构建命令保持独立，避免普通代码检查重复生成大型产物。

## 参与贡献

提交问题或代码前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题不要直接公开利用细节，请按 [SECURITY.md](SECURITY.md) 的方式报告。

## V1 边界

V1 不包含云同步、公网远程播放、USB/蓝牙同步、封面、歌词、推荐、评论社交、多用户登录、Android 编辑歌单、Android 导入音乐或 Android 同步回电脑。

## 许可证

本项目使用 [MIT License](LICENSE)。
