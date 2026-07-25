# 壹加音乐 V1 交付说明

## 最近构建

最近一次已验证构建：`2026-07-18`。

| 平台 | 交付文件 | 类型 |
| --- | --- | --- |
| Windows | `release\windows\MusicSyncPlayer\YijiaMusic.exe` | 完整 Windows 运行目录中的启动程序 |
| Android | `release\android\music_sync_player_v1_debug.apk` | Debug APK |

`release/` 是本地交付目录，已被 Git 忽略。

## 已完成

- Windows：导入 MP3、FLAC、M4A、WAV；文件夹导入；hash 去重；待整理命名；歌单；搜索；本地播放和播放队列。
- Windows：Wi-Fi 同步模式、二维码、连接码、歌单清单和受限音频下载。
- Android：扫码或手动粘贴连接信息；整张歌单同步；已同步歌曲和歌单搜索；删除本地缓存；离线本地播放。
- Android：音乐库、歌单、同步音乐三页导航；同步完成后自动刷新本地库；迷你播放器与完整播放面板。
- 两端：壹加音乐品牌名称、绿色折面标志和浅色高对比界面。

## 启动 Windows

1. 打开 `release\windows\MusicSyncPlayer\`。
2. 双击 `YijiaMusic.exe`。
3. 用“添加歌曲”导入文件或文件夹；用“Wi-Fi 同步”显示二维码和连接码。

Windows 本地播放依赖 `ffplay`。目标机器没有可用 `ffplay` 时，导入、歌单和同步仍可用，但 Windows 端无法播放本地歌曲。

## 安装 Android

1. 把 `release\android\music_sync_player_v1_debug.apk` 复制到手机。
2. 在 Android 系统中允许安装本地 APK。
3. 安装后打开“壹加音乐”。

## Wi-Fi 同步

1. 让 Windows 电脑和 Android 手机使用同一 Wi-Fi。
2. Windows 打开“Wi-Fi 同步”。
3. Android 打开“同步音乐”，优先扫描 Windows 二维码。
4. 扫码失败时展开手动连接，粘贴二维码载荷。
5. 连接后选择整张歌单同步。Android 完成后会自动刷新音乐库并显示本机歌曲数量。

## 自动验证

- Windows：`flutter analyze`、`flutter test`、`flutter build windows`。
- Android：`flutter analyze`、`flutter test`、`flutter build apk --debug`。
- 项目内生成 MP3、FLAC、M4A、WAV 的导入、待整理命名、重复检测和 Windows 播放探测。
- Windows 同步服务与 Android 同步客户端的自动测试。

## 仍需真机确认

- Windows 真实文件与文件夹选择器。
- Android 相机权限和扫描 Windows 二维码。
- 同一 Wi-Fi 下 Android 连接、整张歌单下载和同步结果显示。
- 关闭 Windows 同步模式或断网后的 Android 离线播放。

## V1 范围外

云同步、公网远程播放、USB、蓝牙、封面、歌词、推荐、社交、多用户登录、Android 编辑歌单、Android 导入音乐和 Android 同步回电脑均不在 V1 内。
