# 壹加音乐

壹加音乐 V1 是一个个人使用的 Windows + Android 双端音乐同步播放器。

Windows 端是主音乐库，负责导入音乐、管理歌单、本地播放和开启 Wi-Fi 同步模式。
Android 端是只读随身播放器，负责扫码连接电脑端、同步整个歌单到手机本地，并离线播放已同步音乐。

V1 只做同一 Wi-Fi 下扫码同步，不做云同步、远程在线播放、USB、蓝牙、歌词、封面、推荐、社交、手机端编辑歌单、手机端导入音乐或手机端同步回电脑。

## 当前状态

当前完成到 Phase 2：

- 已整理项目文档。
- 已创建 monorepo 基础目录。
- Flutter SDK 已安装到 `D:\Dev\flutter`。
- Android SDK 已安装到 `D:\Android\Sdk`。
- Windows Flutter APP 已生成并能构建。
- Android Flutter APP 已生成并能构建 debug APK。
- 共享核心模型已实现。
- SQLite 数据库初始化、基础表、仓库和搜索已实现。
- Windows 端已支持导入音频文件和文件夹。
- Windows 端导入会复制音乐到 `D:\OnePlusMusic\Library\audio`。
- Windows 端已显示全部歌曲、待整理音频、搜索框和导入结果。

原中文路径触发 Windows 构建乱码问题后，项目已复制到纯英文路径：

```text
D:\Projects\music_sync_player
```

原目录仍保留为备份，没有删除。

## 目录结构

```text
Projectsmusic_sync_player/
  agent.md
  codex_start_prompt.md
  docs/
    product_requirements.md
    technical_implementation.md
  apps/
    windows_app/
    android_app/
  packages/
    core/
    database/
    player/
    sync_protocol/
  tools/
  scripts/
  README.md
```

## 开发工具

### Flutter SDK

Flutter SDK 用来创建、运行和打包 Windows 端与 Android 端 APP。

本机目标安装位置：

```text
D:\Dev\flutter
```

安装成功后检查：

```powershell
D:\Dev\flutter\bin\flutter.bat --version
D:\Dev\flutter\bin\flutter.bat doctor -v
```

当前 `flutter doctor -v` 已检查通过。

### Android SDK / ADB

Android SDK 用来把手机端 APP 打包成 APK。ADB 用来让电脑识别 Android 真机、安装和调试 APP。

后续建议安装位置：

```text
D:\Android\Sdk
```

当前 Android SDK 已安装到该目录，已可构建 debug APK。

安装成功后检查：

```powershell
adb version
flutter devices
```

### Windows 构建工具

Windows 构建工具用来把 Windows 端 APP 打包成可以双击启动的 exe。

安装成功后主要通过下面命令检查：

```powershell
flutter doctor -v
```

## 后续 Phase 1 目标

环境准备好后，继续完成：

1. Phase 4：Windows 端创建、重命名、删除歌单。
2. Phase 4：Windows 端把歌曲加入歌单、从歌单移除。
3. Phase 4：Windows 端本地播放歌曲。
4. Phase 5：Windows 端开启 Wi-Fi 同步模式。

## 当前验证结果

Windows 端：

```powershell
cd D:\Projects\music_sync_player\apps\windows_app
flutter analyze
flutter build windows
```

已通过，Windows 产物位置：

```text
D:\Projects\music_sync_player\apps\windows_app\build\windows\x64\runner\Release\windows_app.exe
```

Android 端：

```powershell
cd D:\Projects\music_sync_player\apps\android_app
flutter analyze
flutter build apk --debug
```

已通过，Android debug APK 位置：

```text
D:\Projects\music_sync_player\apps\android_app\build\app\outputs\flutter-apk\app-debug.apk
```
