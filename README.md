# 壹加音乐

壹加音乐 V1 是一个个人使用的 Windows + Android 本地音乐同步播放器。

- Windows 是主音乐库：导入音频、管理歌单、播放本地歌曲、开启 Wi-Fi 同步。
- Android 是只读随身播放器：扫码连接电脑、按整张歌单同步、搜索和离线播放已同步歌曲。
- 同步只在同一 Wi-Fi 下从 Windows 单向传到 Android；不依赖云端。

## 当前交付状态

源码、自动测试和交付产物已完成。仍待真实设备人工确认的项目列在文末，不把它们误写成已验收通过。

已实现：

- MP3、FLAC、M4A、WAV 的 Windows 文件/文件夹导入、复制保存、hash 去重和待整理命名。
- Windows 歌单、搜索、播放队列、播放/暂停、切歌和可拖动进度条。
- Windows 同步模式、二维码、连接码、歌单清单和受限音频下载服务。
- Android 扫码与手动粘贴连接、整张歌单同步、本地数据库和已同步内容搜索。
- Android 音乐库、歌单、同步音乐三页导航，以及本地迷你播放器、完整播放页和缓存删除确认。
- Windows 与 Android 的壹加音乐品牌名称、图标和浅色雾灰绿界面。

## 交付文件

Windows 完整运行目录：

```text
D:\Projects\music_sync_player\release\windows\MusicSyncPlayer\
```

Windows 启动文件：

```text
D:\Projects\music_sync_player\release\windows\MusicSyncPlayer\YijiaMusic.exe
```

Android debug APK：

```text
D:\Projects\music_sync_player\release\android\music_sync_player_v1_debug.apk
```

`release/` 是交付目录，已被 Git 忽略，不会提交构建产物。

## 使用方式

### Windows

1. 打开 `release\windows\MusicSyncPlayer\`。
2. 双击 `YijiaMusic.exe`。
3. 在“添加歌曲”中导入文件或文件夹，在“音乐库”中播放和管理歌单。
4. 在“Wi-Fi 同步”中开启同步模式，显示二维码和连接码。

Windows 启动时会检测 `ffplay` 和 `ffprobe`，结果显示在底部播放器状态区。没有 `ffplay` 时，导入、歌单和同步仍可使用，但 Windows 本地播放会被明确标为不可用；没有 `ffprobe` 时仍可播放，只是部分歌曲时长可能无法提前读取。

### Android

1. 将 `release\android\music_sync_player_v1_debug.apk` 传到 Android 手机。
2. 在系统安装页面允许安装本地 APK，然后打开“壹加音乐”。
3. 底部“音乐库”只显示已同步歌曲；“歌单”只显示已同步歌单；“同步音乐”用于连接电脑。

### 在电脑模拟 Android

本机已有 Android Studio 虚拟手机 `YijiaMusic_Pixel_7_API_35`。启动模拟器后，可用以下命令保留现有 APP 数据并覆盖安装固定验收 APK：

```powershell
D:\Android\Sdk\platform-tools\adb.exe -s emulator-5554 install -r D:\Projects\music_sync_player\release\android\music_sync_player_v1_debug.apk
```

模拟器不方便扫描电脑屏幕时，在 Windows “Wi-Fi 同步”页点击“复制连接信息”，再在 Android “同步音乐”页展开“手动粘贴连接信息”。2026-07-27 已用正式 Windows EXE 与该模拟器完成真实连接、整张歌单同步、重复同步无重复落盘、空歌单同步、电脑端删除歌单后的自动对账、共用歌曲引用保留、歌单成员移除后重同步，以及 Windows 退出后的本地离线播放验证。

### 第一次 Wi-Fi 同步

1. 让 Windows 电脑与 Android 手机连接到同一 Wi-Fi。
2. Windows 端开启“Wi-Fi 同步”。
3. Android 端打开“同步音乐”，扫描 Windows 二维码。
4. 扫码无法使用时，展开手动连接并粘贴 Windows 二维码载荷。
5. 连接成功后选择整张歌单同步。完成后 Android 会返回音乐库并显示本机实际歌曲数。
6. 关闭 Windows 同步模式或断开网络后，Android 仍只播放已保存到本机的歌曲。

## 工程结构

```text
music_sync_player/
  apps/windows_app/       Windows Flutter 应用
  apps/android_app/       Android Flutter 应用
  packages/core/          共享歌曲、歌单和同步状态模型
  packages/database/      SQLite 表与查询仓库
  packages/sync_protocol/ 二维码和连接协议模型
  docs/                   产品与技术说明
  release/                本地交付输出（Git 忽略）
```

`packages/player/` 目前是保留的未来抽象位置；Windows 与 Android 现阶段各自使用平台适配播放器，不能把其中的模板类当作运行时播放器。

## 验证命令

Windows：

```powershell
cd D:\Projects\music_sync_player\apps\windows_app
D:\Dev\flutter\bin\flutter.bat analyze
D:\Dev\flutter\bin\flutter.bat test
D:\Dev\flutter\bin\flutter.bat build windows
```

Android：

```powershell
cd D:\Projects\music_sync_player\apps\android_app
D:\Dev\flutter\bin\flutter.bat analyze
D:\Dev\flutter\bin\flutter.bat test
D:\Dev\flutter\bin\flutter.bat build apk --debug
```

项目内 `manual_test_audio/` 包含非敏感自动生成样本，仅用于导入和播放验收，并且被 Git 忽略。详细样本与人工检查清单见 [testing_notes.md](testing_notes.md)。

## 同步数据安全

Android 同步会先把整张歌单需要的新文件下载到 APP 私有临时目录，核对文件大小和 SHA-256 后，再在 SQLite 事务内更新本地歌单并替换正式缓存。同步中断、文件不完整或 Hash 错误时，旧歌单和原本可播放的缓存会保留。

替换正式缓存前还会写入恢复清单，并把提交标记放进同一个数据库事务。即使 Android 系统在文件替换与数据库提交之间强制结束 APP，下次启动也会根据提交标记恢复旧文件，或保留已提交的新文件并清理备份。旧版数据库的磁盘升级也有自动测试，升级不会清空原有歌曲和歌单。

同步还会在下载前检查手机可用空间，并为网络请求设置 20 秒无响应超时。断连、超时和服务器临时错误最多尝试 3 次，权限错误、危险地址和文件校验错误不会盲目重试。

Windows 会为权威歌单清单和每张歌单生成内容版本。Android 连接后会移除电脑端已删除的旧快照；空歌单也能保留显示。音频按歌单引用清理，多张歌单共用的文件不会因为删除其中一张歌单而误删。

完整安全规则、代码位置、协议字段和负面测试见 [docs/sync_safety_plan.md](docs/sync_safety_plan.md)。

## 仍需人工确认

- Windows 真实文件选择器和文件夹选择器的完整点击流程。
- Android 真机的相机权限弹窗与扫描 Windows 二维码。
- Android 与 Windows 在同一 Wi-Fi 下的真实连接和整张歌单下载。
- 关闭 Windows 同步模式或断网后，Android 已同步歌曲的真机离线播放。

## V1 范围外

不做云同步、公网远程播放、USB、蓝牙、封面、歌词、推荐、评论社交、多用户登录、Android 编辑歌单、Android 导入音乐或 Android 同步回电脑。
