# 开发记录

## 2026-07-07

### 已完成

- 将正式项目路径确定为 `D:\Projects\music_sync_player`。
- 保留原中文路径项目为备份，避免 Windows 构建链乱码问题。
- Flutter SDK 已安装到 `D:\Dev\flutter`。
- Android SDK 已安装到 `D:\Android\Sdk`。
- Pub 缓存使用 `D:\DevCaches\pub`。
- Gradle 缓存使用 `D:\DevCaches\gradle`。
- Windows Flutter APP 已创建并通过 `flutter analyze`、`flutter build windows`。
- Android Flutter APP 已创建并通过 `flutter analyze`、`flutter build apk --debug`。
- 共享包已创建：`music_core`、`music_database`、`music_player`、`music_sync_protocol`。

### 验证结果

- `flutter doctor -v`：No issues found。
- Windows 构建产物：`apps\windows_app\build\windows\x64\runner\Release\windows_app.exe`。
- Android debug APK：`apps\android_app\build\app\outputs\flutter-apk\app-debug.apk`。

### Phase 2：核心数据模型和数据库

已完成：

- `packages\core`：实现 `Song`、`Playlist`、`PlaylistItem`、`ImportResult`、`SyncManifest`、`SyncSession`、`SyncDownloadTask`、`AudioFormat`、`SongMetadata`、`AppError` 等核心模型。
- `packages\database`：使用 SQLite 实现数据库初始化。
- `packages\database`：创建 `songs`、`playlists`、`playlist_items`、`sync_cache` 表。
- `packages\database`：实现 `SongRepository`、`PlaylistRepository`、`SyncRepository`、`SearchRepository`。
- 数据库规则已覆盖：文件 hash 去重、同一歌单不重复加入同一首歌、删除歌单不删除歌曲记录、手机端可只搜索已同步内容。

验证：

- `packages\core`：`flutter analyze` 通过，`flutter test` 通过。
- `packages\database`：`flutter analyze` 通过，`flutter test` 通过。
- `apps\windows_app`：`flutter analyze` 通过，`flutter build windows` 通过。
- `apps\android_app`：`flutter analyze` 通过，`flutter build apk --debug` 通过。

### Git 初始化

已完成：

- 在 `D:\Projects\music_sync_player` 执行 `git init`。
- 创建 `.gitignore`，排除 Flutter/Android/Windows 构建产物、缓存、压缩包、临时文件和本地音乐库数据。
- 提交前运行 `apps\windows_app` 的 `flutter analyze`，结果通过。

说明：

- 当前仓库只用于项目源码和文档，不包含 Flutter SDK、Android SDK、Gradle/Pub 缓存或私人目录文件。

### Phase 3：Windows 端音频导入

已完成：

- Windows 端首页从 Flutter 计数器模板改为“壹加音乐 - Windows 主库”界面。
- 支持用户点击“导入音频文件”，用系统窗口选择 MP3、FLAC、M4A、WAV 文件。
- 支持用户点击“导入文件夹”，递归扫描其中支持格式的音频文件。
- 导入时复制音频到 `D:\OnePlusMusic\Library\audio`，不移动、不删除原始文件。
- 导入时计算 SHA-256 文件 hash，数据库中已有相同 hash 时跳过重复导入。
- MP3 文件会尝试读取 ID3v2 中的标题、歌手、专辑。
- 元数据不足时尝试使用文件名识别。
- 数字、长编码、乱码或无意义文件名进入“未命名音频 001/002/003...”并标记为待整理。
- Windows 首页展示全部歌曲、待整理音频、搜索框和导入统计。

验证：

- `apps\windows_app`：`flutter analyze` 通过。
- `apps\windows_app`：`flutter test` 通过。
- `apps\windows_app`：`flutter build windows` 通过。

当前限制：

- FLAC/M4A/WAV 暂时先走文件名识别兜底，尚未读取其内部元数据。
- 音乐库目录暂时固定为 `D:\OnePlusMusic\Library`，后续可做用户自选目录。

### Phase 4：Windows 端歌单和播放

已完成：

- Windows 端首页显示全部歌曲、待整理音频、歌单列表和当前歌单内容。
- 支持搜索歌曲标题、歌手、专辑、原始文件名和歌单名。
- 支持新建、重命名、删除歌单；删除歌单前会确认，且不会删除主库歌曲或音频文件。
- 支持把歌曲加入当前歌单，并支持从歌单移除歌曲。
- 支持从全部歌曲、待整理音频和歌单内容中播放本地文件。
- 支持暂停、继续和停止当前播放，并把播放错误显示到状态栏。
- 歌单面板已改成可伸缩布局，避免小窗口或测试窗口高度不足时溢出。

验证：

- `apps\windows_app`：`flutter analyze` 通过。
- `apps\windows_app`：`flutter test` 通过。
- `packages\database`：`flutter test` 通过。

当前限制：

- Windows 本地播放先使用系统 MCI 播放能力封装，真实格式兼容性仍需在 Phase 7 用 MP3、FLAC、M4A、WAV 实测。
- 尚未进入 Phase 5 的 Wi-Fi 同步模式实现。

### Phase 5：Windows 端同步模式

已完成：

- `packages\sync_protocol` 从模板占位改为同步协议模型，包含二维码载荷、连接请求和连接响应。
- Windows 端新增手动开启/关闭 Wi-Fi 同步模式。
- 开启同步模式时会启动本地 HTTP 服务，生成临时 `session_id`、6 位连接码、局域网地址和二维码载荷。
- Windows 首页显示连接地址、连接码、二维码和二维码原始载荷。
- 同步服务已实现连接验证接口、歌单列表接口、歌单同步清单接口和按 `songId` 下载音频文件接口。
- 下载接口只允许下载数据库中存在的歌曲文件，不接受任意本地路径。

验证：

- `packages\sync_protocol`：`flutter analyze` 通过。
- `packages\sync_protocol`：`flutter test` 通过。
- `apps\windows_app`：`flutter analyze` 通过。
- `apps\windows_app`：`flutter test` 通过，覆盖连接验证、歌单列表、同步清单和文件下载。

当前限制：

- Phase 5 的 Windows 服务骨架已完成，但尚未用 Android 端扫码联调。
- 目前二维码已生成并显示，Android 端解析和下载流程留到 Phase 6 继续。

### Phase 6：Android 端同步和本地播放

已完成：

- Android 端从计数器模板改为“壹加音乐 - Android 随身库”界面。
- Android 端支持粘贴并解析 Windows 端二维码载荷。
- Android 端支持连接 Windows 端同步服务，并获取电脑端歌单列表。
- Android 端支持选择整张歌单同步。
- 同步时会下载歌曲到 Android APP 本地 `audio` 目录。
- 同步完成后会写入 Android 本地 SQLite 数据库，包括歌曲、歌单、歌单条目和同步缓存状态。
- Android 端只显示 `sync_cache` 中状态为 `synced` 的本地内容。
- Android 端支持搜索已同步歌曲和歌单。
- Android 端支持删除本地缓存，并把本地同步状态标记为 deleted；该操作不调用电脑端修改接口，不影响电脑端主库。
- Android 端支持离线播放已同步到本地的音频文件，并支持暂停、继续和停止。
- Android Manifest 已声明网络权限，并允许同一 Wi-Fi 下访问 Windows 端明文 HTTP 同步服务。

验证：

- `apps\android_app`：`flutter analyze` 通过。
- `apps\android_app`：`flutter test` 通过。
- `packages\database`：`flutter analyze` 通过。
- `packages\database`：`flutter test` 通过。
- `apps\android_app`：`flutter build apk --debug` 通过，产物为 `apps\android_app\build\app\outputs\flutter-apk\app-debug.apk`。

构建说明：

- 第一次 Android 构建时，`sqlite3` native assets 需要下载预编译 SQLite 库，Dart 构建钩子遇到 TLS 握手失败。
- 按构建日志建议，用 PowerShell `Invoke-WebRequest` 成功访问同一 GitHub SQLite 库地址后，重新构建通过。

当前限制：

- 当前 Android 端已支持“解析二维码载荷”，尚未接入摄像头实时扫码 UI。
- 尚未做真机端到端验收：Windows 开启同步模式、Android 连接、同步真实歌曲并断网播放。

### Phase 7：验收、修复和 release 交付

已完成：

- 创建 `testing_notes.md`，列出 Phase 7 真实音频样本需求和手动验收清单。
- 将 `manual_test_audio/` 加入 `.gitignore`，避免后续手动验收样本被误提交。
- 新增 Android 同步客户端测试，覆盖连接本地测试服务、获取歌单、整张歌单同步、下载音频、写入本地数据库和 synced-only 可见性。
- 确认 `ffmpeg` 和 `ffplay` 可用。
- 在 `manual_test_audio/` 内生成 3 秒非敏感测试音频：MP3、FLAC、M4A、WAV 和重复 MP3。
- 新增 Windows 生成音频导入测试，覆盖文件导入、文件夹导入、四种格式、正常命名、待整理命名和重复文件处理。
- Phase 7 发现 Windows 旧 MCI 播放后端无法稳定播放带空格文件名，且不支持 FLAC/M4A。
- Windows 播放后端改为使用本机已有 `ffplay` 做本地播放，已通过生成 MP3、FLAC、M4A、WAV 播放探测。

自动验证：

- `apps\android_app`：`flutter analyze` 通过。
- `apps\android_app`：`flutter test` 通过。
- `apps\android_app`：`flutter build apk --debug` 通过，产物为 `apps\android_app\build\app\outputs\flutter-apk\app-debug.apk`。
- `apps\windows_app`：`flutter analyze` 通过。
- `apps\windows_app`：`flutter test` 通过。
- `apps\windows_app`：`flutter build windows` 通过，产物为 `apps\windows_app\build\windows\x64\runner\Release\windows_app.exe`。
- `packages\core`：`flutter analyze` 通过，`flutter test` 通过。
- `packages\database`：`flutter test` 通过。
- `packages\sync_protocol`：`flutter analyze` 通过，`flutter test` 通过。

待手动验收：

- 真实 Windows 文件选择器和文件夹选择器操作仍需手动点选确认。
- Windows 和 Android 真机同 Wi-Fi 联调仍需手动确认。
- Android 断网或关闭 Windows 同步模式后的离线播放仍需真机确认。

### Android 扫码连接

已完成：

- Android 端新增扫码入口，位于“同步音乐”区域。
- 用户可以点击“扫码”打开摄像头扫描 Windows 端二维码。
- 扫码识别到合法同步二维码后，会复用现有连接 Windows 同步服务流程。
- 保留“粘贴”和“连接电脑端”手动备用方式，扫码失败时仍可手动输入二维码载荷。
- Android Manifest 已增加 Camera 权限。
- 新增 `mobile_scanner` 依赖，用于通过手机摄像头识别二维码；它是常见的 Flutter 扫码插件，Android 端使用 MLKit 做本地识别。

验证：

- `apps\android_app`：`flutter analyze` 通过。
- `apps\android_app`：`flutter test` 通过。
- `apps\android_app`：`flutter build apk --debug` 通过，产物为 `apps\android_app\build\app\outputs\flutter-apk\app-debug.apk`。
- 第一次构建时 Gradle 下载 `mobile_scanner` 相关 Android/Kotlin 依赖遇到 TLS 握手失败；用 PowerShell 成功访问对应 Maven 地址后重试构建通过。
- 当前环境无法真实打开手机摄像头，因此真机扫码仍需安装 APK 后人工确认。

### Phase 8：最终交付整理

已完成：

- 重新构建 Windows 端。
- 重新构建 Android debug APK。
- 整理 Windows 完整可运行目录到 `release\windows\MusicSyncPlayer`。
- 整理 Android debug APK 到 `release\android\music_sync_player_v1_debug.apk`。
- 创建 `RELEASE_NOTES.md`，并复制一份到 `release\RELEASE_NOTES.md` 方便交付。
- 更新 `README.md`，写清楚启动 Windows、安装 APK、Wi-Fi 同步、已完成功能和仍需人工确认事项。

验证：

- `apps\windows_app`：`flutter build windows` 通过。
- `apps\android_app`：`flutter build apk --debug` 通过。

交付产物：

- Windows：`release\windows\MusicSyncPlayer\windows_app.exe`。
- Android：`release\android\music_sync_player_v1_debug.apk`。

说明：

- `release/`、`build/`、APK、exe 等构建产物不提交到 Git。
- Android 构建仍有 `mobile_scanner` 使用 Kotlin Gradle Plugin 的未来兼容警告，但当前 debug APK 构建成功。
- 真机扫码、同 Wi-Fi 连接和断网离线播放仍需人工确认。

### Phase 8：播放器体验整理

- Windows 默认首页调整为播放器优先的“音乐库”：歌曲、歌单、搜索和底部播放条留在首页。
- “添加歌曲”和“Wi-Fi 同步”改为左侧独立页面，导入和二维码不再占用默认播放页面。
- Windows 底部播放条改为常见音乐软件样式：歌曲信息、单一播放/暂停按钮、停止按钮、播放时间和可拖动进度条。
- Windows 拖动进度条后会以目标时间重新启动 `ffplay`，因此会有一次轻微重启，但不会从头播放。
- Android 同步结果会显示实际本地歌曲数；如果某首歌曲失败，会显示首个失败原因，避免“看起来同步成功但列表为空”。

### Phase 8：Windows 播放器核心体验补齐

- 统一 Windows 的 `Microsoft YaHei UI` 字体、字号和字重层级，减少标题和正文视觉上的忽粗忽细。
- 底部播放条调整为三段式布局：上一首、播放/暂停、下一首固定居中；歌曲信息放左侧，播放模式、播放队列和停止放右侧。
- 新增播放队列：支持从全部歌曲和歌单中加入队列或设为下一首，支持查看、点歌、拖动排序、移除待播歌曲和清空待播放内容。
- 新增顺序播放、列表循环、单曲循环和随机播放；自然播放结束会按当前模式自动处理下一首。
- 新增 Windows 键盘快捷键：`Ctrl + 空格` 播放/暂停、`Ctrl + 左/右` 上一首/下一首、`Alt + 左/右` 后退/前进 5 秒。
- 验证通过：`apps/windows_app` 的 `flutter analyze`、`flutter test` 和 `flutter build windows`；完整运行目录已重新同步到 `release\\windows\\MusicSyncPlayer`。
