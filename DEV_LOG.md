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
