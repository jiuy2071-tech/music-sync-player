# 壹加音乐 V1 交付说明

## 最近构建

最近一次已验证构建：`2026-07-27`。

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
- 同步安全：临时下载、大小与 Hash 校验、SQLite 事务、强制中断重启恢复、旧文件恢复、空间预检、有限重试、权威歌单版本和孤儿清理。
- Android：电脑端删除歌单后可对账清理；空歌单可显示；多歌单共用歌曲不会误删。
- Windows：启动时检查 `ffplay` 和 `ffprobe`，在底部播放器显示真实播放能力。
- 两端：壹加音乐品牌名称、绿色折面标志和浅色高对比界面。

## 启动 Windows

1. 打开 `release\windows\MusicSyncPlayer\`。
2. 双击 `YijiaMusic.exe`。
3. 用“添加歌曲”导入文件或文件夹；用“Wi-Fi 同步”显示二维码和本次临时连接码。

Windows 启动时会检查 `ffplay` 和 `ffprobe`。目标机器没有可用 `ffplay` 时，底部播放器会直接提示本地播放不可用，但导入、歌单和同步仍可用；只有 `ffprobe` 缺失时仍能播放。

## 安装 Android

1. 把 `release\android\music_sync_player_v1_debug.apk` 复制到手机。
2. 在 Android 系统中允许安装本地 APK。
3. 安装后打开“壹加音乐”。

## Wi-Fi 同步

1. 让 Windows 电脑和 Android 手机使用同一 Wi-Fi。
2. Windows 打开“Wi-Fi 同步”。
3. Android 打开“同步音乐”，优先扫描 Windows 二维码。
4. 扫码失败时展开手动连接，粘贴 Windows 端复制的完整连接信息；不能只输入 6 位连接码。
5. 连接后选择整张歌单同步。Android 完成后会自动刷新音乐库并显示本机歌曲数量。

## 自动验证

- Windows：`flutter analyze`、`flutter test`、`flutter build windows`。
- Android：`flutter analyze`、`flutter test`、`flutter build apk --debug`。
- 项目内生成 MP3、FLAC、M4A、WAV 的导入、待整理命名、重复检测和 Windows 播放探测。
- Windows 同步服务与 Android 同步客户端的自动测试。
- Android 强制中断前后残留恢复，以及真实磁盘旧数据库升级测试。
- 2026-07-27 固定 Android APK 与本次构建文件 SHA-256 均为 `F56501F300A51BFBDCEC8D26B47F2FABBC1BD33946DE70A486F5EAB7A2392986`。
- 正式 Windows EXE 与 Android 模拟器已完成真实跨进程连接、整张歌单同步、重复同步无重复落盘，以及 Windows 退出后的离线播放验证。

## 仍需真机确认

- Windows 真实文件与文件夹选择器。
- Android 相机权限和扫描 Windows 二维码。
- 实体手机在同一 Wi-Fi 下连接、整张歌单下载和同步结果显示。
- 关闭 Windows 同步模式或断网后的实体手机离线播放。

## V1 范围外

云同步、公网远程播放、USB、蓝牙、封面、歌词、推荐、社交、多用户登录、Android 编辑歌单、Android 导入音乐和 Android 同步回电脑均不在 V1 内。
