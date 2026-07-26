# 开发记录

## 2026-07-07：基础工程到同步闭环

- 确定正式路径为 `D:\Projects\music_sync_player`，避免中文路径造成 Windows 构建编码问题。
- 配置 Flutter、Android SDK、Pub 与 Gradle 缓存到 D 盘。
- 完成共享模型、SQLite、Windows 导入/歌单/播放、Windows 同步服务和 Android 歌单同步/离线播放。
- 建立 Git 忽略规则，排除 SDK、缓存、构建产物、APK、EXE、release 和生成测试音频。

## 2026-07-18：验收、交付与体验整理

- 使用项目内生成的 MP3、FLAC、M4A、WAV 验证导入、待整理命名、重复检测和 Windows 播放探测。
- 完成 Windows 同步服务与 Android 同步客户端自动测试；真实扫码、同一 Wi-Fi 和离线播放保留给真机人工确认。
- Windows 播放器更新为居中的上一首/播放/下一首、播放队列、播放模式、快捷键和可拖动进度条。
- Windows 视觉整理为浅色雾灰绿主题，修正导航字重与播放队列提示；应用品牌改为壹加音乐，正式 EXE 为 `YijiaMusic.exe`。
- Android 更新为音乐库、歌单、同步音乐三页导航；同步完成后自动刷新本地库并返回音乐库；增加迷你播放器、完整播放面板、切歌、进度跳转与缓存删除确认。
- Android 应用名称、启动图标和应用内品牌资源改为壹加音乐。
- 最后一次自动验证通过：Windows 和 Android 的 `flutter analyze`、`flutter test` 及对应构建命令。

## 2026-07-26：Android 原子同步安全加固

- 修复同步开始后立即清空本地歌单的问题：歌曲、歌单关系和缓存记录现在放在同一个 SQLite 事务中提交。
- 新文件先下载到 APP 私有临时目录，检查文件大小和 SHA-256 后才替换正式缓存。
- 替换正式文件前保留旧文件备份；数据库或文件操作失败时回滚数据库并恢复旧缓存。
- 增加同步清单安全检查，拒绝危险歌曲 ID、错误 Hash、越界路径和指向其他主机或旧会话的下载地址。
- 新增不完整下载、错误 Hash、成功升级、路径越界和数据库事务回滚测试。
- 同步前通过 Android 系统接口检查 APP 私有目录可用空间，预留 16 MB 安全余量；空间不足时不会开始音频下载或修改本地数据。
- 连接、清单和文件读取增加 20 秒无响应超时；断连、超时、HTTP 408/429/5xx 最多尝试 3 次，权限错误、危险地址和校验错误不会重试。
- 新增空间不足提前停止和服务器临时失败后重试成功的自动测试。
- Android `flutter analyze`、完整 `flutter test` 和 `flutter build apk --debug` 已通过；新的 APK 已更新到本地交付目录。
- Windows 权威歌单对账、孤儿缓存清理和真机断网回归仍在后续 P0 清单中。
- Windows `/playlists` 增加权威清单 SHA-256 和每张歌单内容版本；manifest 返回对应版本，Android 会拒绝同步期间发生变化的清单。
- SQLite 增加 `synced_playlists` 快照表，空歌单同步后可正常显示，并兼容补录旧数据库中的已有非空歌单。
- Android 连接后会移除 Windows 已删除的本地歌单；孤儿清理按 `playlist_items` 引用判断，共用歌曲保留，最后引用消失后才删除。
- 孤儿音频先移动到 APP 私有临时回收目录，数据库删除失败会恢复文件。
- Windows 与 Android 的完整 `flutter analyze`、`flutter test` 和对应构建再次通过；两个固定交付位置均已覆盖为本次版本。
- Windows 启动前会检测 `ffplay` 与 `ffprobe`：底部播放器直接显示可播放、只能播放但无法预读时长，或本地播放不可用。
- 缺少 `ffplay` 时播放操作会被明确阻止，但导入、歌单管理和 Wi-Fi 同步不受影响。
- 新增播放能力检测自动测试；Windows `flutter analyze`、完整 `flutter test` 和 `flutter build windows` 再次通过。
- Windows 交付目录已整体镜像更新，并核对 `data\app.so` 与构建目录 Hash 一致，保证固定 EXE 加载本次业务代码。

## 当前交付

- Windows：`release\windows\MusicSyncPlayer\YijiaMusic.exe`
- Android：`release\android\music_sync_player_v1_debug.apk`
- 详细安装、同步和人工确认清单：`RELEASE_NOTES.md` 与 `testing_notes.md`。
