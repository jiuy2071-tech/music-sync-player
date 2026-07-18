# 壹加音乐

壹加音乐 V1 是一个个人使用的 Windows + Android 双端音乐同步播放器。

Windows 端是主音乐库，负责导入音乐、管理歌单、本地播放和开启 Wi-Fi 同步模式。
Android 端是只读随身播放器，负责扫码连接电脑端、同步整个歌单到手机本地，并离线播放已同步音乐。

V1 只做同一 Wi-Fi 下扫码同步，不做云同步、远程在线播放、USB、蓝牙、歌词、封面、推荐、社交、手机端编辑歌单、手机端导入音乐或手机端同步回电脑。

## 当前状态

当前完成到 Phase 8 交付整理：

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
- Windows 端已支持新建、重命名、删除歌单。
- Windows 端已支持把歌曲加入歌单、从歌单移除。
- Windows 端已支持基础本地播放、暂停、继续和停止。
- Windows 端已用项目内生成的 MP3、FLAC、M4A、WAV 测试音频通过导入和播放探测。
- Windows 端已支持手动开启 Wi-Fi 同步模式，生成连接码和二维码。
- Windows 端已提供连接验证、歌单列表、同步清单和音频下载接口。
- Android 端已支持解析二维码载荷、连接 Windows 端并显示电脑端歌单。
- Android 端已支持扫码连接 Windows 端，并保留手动粘贴二维码载荷的备用方式。
- Android 端已支持按整张歌单同步到 APP 本地目录和本地数据库。
- Android 端只显示已同步到本地的歌曲和歌单，支持搜索、删除本地缓存和离线播放。
- Phase 7 已在 `manual_test_audio/` 内生成非敏感测试音频，该目录不会提交到 Git。
- Phase 8 已重新构建 Windows 运行目录和 Android debug APK，并整理到 `release/`。

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

## 交付产物

Windows 端完整运行目录：

```text
D:\Projects\music_sync_player\release\windows\MusicSyncPlayer\
```

Windows 启动文件：

```text
D:\Projects\music_sync_player\release\windows\MusicSyncPlayer\windows_app.exe
```

Android debug APK：

```text
D:\Projects\music_sync_player\release\android\music_sync_player_v1_debug.apk
```

## Windows 界面设计更新

- Windows 首页采用明亮的雾灰绿分层：背景、导航、内容区和播放控制区使用不同深浅的中性浅色，不再使用压暗界面的黑色大底。
- 主强调色改为深森林绿 `#2C664C`，当前播放和选中状态使用淡鼠尾草绿；信号黄绿只作为小面积状态点缀。
- 统一 `Microsoft YaHei UI` 的字号和字重：页面标题使用 600，歌曲标题和按钮使用 500，说明文字使用 400。
- 左侧导航、搜索框、歌曲列表、歌单和导入/同步页采用细分隔线与留白组织；导入和同步仍在独立页面，不占用听歌首页。
- 底部播放条改为明亮的全宽固定控制台，保持居中的上一首、播放/暂停、下一首；播放键为深绿实心按钮配白色图标，其他操作图标使用高对比深色。
- 播放队列改为右侧展开式面板，可查看、点歌、拖动排序、移除待播歌曲和清空待播放内容。
- 本轮 Windows 验证已通过：`flutter analyze`、`flutter test`、`flutter build windows`。最新运行包：`release\\windows\\MusicSyncPlayer\\windows_app.exe`。

## 最新 Windows 播放器体验

- Windows 界面统一使用 `Microsoft YaHei UI`，标题、正文和按钮采用固定字重层级，避免同一页面忽粗忽细。
- 底部播放条采用三段布局：左侧显示当前歌曲，中间固定为“上一首 / 播放或暂停 / 下一首”，右侧提供播放模式、播放队列和停止。
- 支持顺序播放、列表循环、单曲循环和随机播放；队列可以查看、拖动排序、点歌播放、移除待播歌曲和清空待播放内容。
- 全部歌曲和歌单歌曲的更多菜单均可“播放下一首”或“加入播放队列”；双击歌曲也可以开始播放。
- 键盘快捷键：`Ctrl + 空格` 播放/暂停，`Ctrl + 左/右` 上一首/下一首，`Alt + 左/右` 后退/前进 5 秒。
- Windows 验证已通过：`flutter analyze`、`flutter test`、`flutter build windows`。最新可运行版本在 `release\\windows\\MusicSyncPlayer\\windows_app.exe`。

`release/` 是交付输出目录，不提交到 Git。

## 使用方法

### 启动 Windows 端

1. 打开：

   ```text
   D:\Projects\music_sync_player\release\windows\MusicSyncPlayer\
   ```

2. 双击 `windows_app.exe`。
3. 默认进入“音乐库”，可直接搜索、播放歌曲和管理歌单。
4. 需要导入时，点击左侧“添加歌曲”，再选择导入音频文件或导入文件夹。
5. 需要同步时，点击左侧“Wi-Fi 同步”，开启同步模式并查看二维码和连接码。

播放界面说明：底部固定播放条会显示歌曲、歌手、播放时间和进度条。点击中间按钮可播放或暂停；拖动进度条后，Windows 端会从目标位置继续播放。

说明：当前 Windows 本地播放使用本机已有的 `ffplay`，用于支持 MP3、FLAC、M4A、WAV。若目标机器没有 `ffplay`，导入、歌单和同步仍可用，但 Windows 本地播放需要后续补充播放器环境或更换内置播放方案。

### 安装 Android APK

1. 将下面 APK 复制到 Android 手机：

   ```text
   D:\Projects\music_sync_player\release\android\music_sync_player_v1_debug.apk
   ```

2. 在手机上允许安装本地 APK。
3. 安装后打开“壹加音乐”。

### Wi-Fi 同步

1. 确认 Windows 电脑和 Android 手机在同一 Wi-Fi。
2. Windows 端开启同步模式。
3. Android 端点击“扫码”，扫描 Windows 端二维码。
4. 如果扫码失败，可以复制 Windows 端二维码载荷，在 Android 端粘贴后点击“连接电脑端”。
5. Android 显示电脑端歌单后，选择整张歌单同步。
6. 同步完成后，Android 端只显示已同步到本地的歌曲和歌单。
7. 关闭 Windows 同步模式或断开网络后，Android 已同步歌曲应可离线播放。

## 仍需人工确认

- Windows 真实文件选择器和文件夹选择器点击流程。
- Android 真机扫码权限弹窗和扫码识别。
- Android 真机同 Wi-Fi 连接 Windows 同步服务。
- Android 真机断网或关闭 Windows 同步模式后的离线播放。

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

交付目录：

```text
D:\Projects\music_sync_player\release\windows\MusicSyncPlayer\
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

交付 APK：

```text
D:\Projects\music_sync_player\release\android\music_sync_player_v1_debug.apk
```
