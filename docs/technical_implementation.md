# 技术实现点文档 - 给开发实现人员

## 1. 技术路线总览

V1 使用 Flutter 全端开发。

Windows 电脑端使用 Flutter Desktop。

Android 手机端使用 Flutter Android。

核心业务模型、数据库访问、同步协议、部分播放器逻辑尽量通过 Dart package 共享。

V1 只实现 Windows + Android，不考虑 iOS、macOS、Linux。

## 2. 总体架构

项目采用双端本地库架构：

电脑端维护完整主音乐库。

手机端维护已同步内容的本地副本。

同步方向为电脑端到手机端。

手机端不得修改主库数据。

建议使用 monorepo：

```text
music_sync_player/
  agent.md
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
  README.md
```

## 3. 推荐 Flutter/Dart 依赖方向

实际依赖版本由开发时选择，但功能上需要覆盖以下能力：

- 文件选择：用于 Windows 端选择文件和文件夹。
- SQLite：用于双端本地数据库。
- 本地文件路径：用于获取 APP 文档目录。
- 音频播放：用于 Windows 和 Android 本地播放。
- 二维码生成：用于 Windows 端显示同步二维码。
- 二维码扫描：用于 Android 端扫码。
- 本地 HTTP 服务：用于 Windows 端同步模式。
- HTTP 客户端：用于 Android 端请求同步接口和下载文件。
- 加密/hash：用于文件 hash 和连接码验证。

实现前必须验证所选依赖在 Windows 和 Android 平台是否可用。

不要假设某个 Flutter 插件天然支持 Windows。

## 4. 本地目录设计

### 4.1 Windows 端音乐库目录

用户第一次使用时，需要选择或创建一个 APP 音乐库目录。

建议结构：

```text
<MusicLibraryRoot>/
  audio/
    <song_id>.<ext>
  library.db
  config.json
```

V1 不做封面，不需要 covers 目录。

音频导入后复制到 audio 目录。

复制后的文件名建议使用 song_id 保证稳定，不依赖原始文件名。

原始文件名记录到数据库 original_file_name 字段。

### 4.2 Android 端目录

Android 端使用 APP 私有目录。

建议结构：

```text
<AppDocuments>/
  audio/
    <song_id>.<ext>
  library.db
  config.json
```

手机端只播放该目录下已同步音频。

卸载 APP 后，这些同步文件可以随 APP 删除。

## 5. 数据库设计

V1 使用 SQLite。

数据库需要支持 Windows 和 Android。

### 5.1 songs 表

字段建议：

```text
id TEXT PRIMARY KEY
 title TEXT NOT NULL
 artist TEXT NOT NULL
 album TEXT NOT NULL
 duration_ms INTEGER
 format TEXT NOT NULL
 file_size INTEGER NOT NULL
 file_hash TEXT NOT NULL
 local_path TEXT NOT NULL
 original_file_name TEXT NOT NULL
 display_name_source TEXT NOT NULL
 is_pending_review INTEGER NOT NULL DEFAULT 0
 created_at TEXT NOT NULL
 updated_at TEXT NOT NULL
```

说明：

id 是稳定歌曲 ID，用于歌单和同步。

file_hash 用于去重和同步判断。

display_name_source 可取 metadata、filename、unnamed。

is_pending_review 标记待整理音频。

### 5.2 playlists 表

字段建议：

```text
id TEXT PRIMARY KEY
 name TEXT NOT NULL
 sort_order INTEGER NOT NULL DEFAULT 0
 created_at TEXT NOT NULL
 updated_at TEXT NOT NULL
```

### 5.3 playlist_items 表

字段建议：

```text
id TEXT PRIMARY KEY
 playlist_id TEXT NOT NULL
 song_id TEXT NOT NULL
 sort_order INTEGER NOT NULL DEFAULT 0
 created_at TEXT NOT NULL
```

需要避免同一歌单重复加入同一首歌。

建议对 playlist_id + song_id 建唯一约束。

### 5.4 sync_cache 表

主要用于手机端记录缓存状态。

字段建议：

```text
id TEXT PRIMARY KEY
 song_id TEXT NOT NULL
 playlist_id TEXT
 local_cache_path TEXT NOT NULL
 file_hash TEXT NOT NULL
 status TEXT NOT NULL
 synced_at TEXT NOT NULL
```

status 可取 synced、failed、deleted。

### 5.5 search

V1 可以先使用普通 LIKE 搜索。

后续可升级 SQLite FTS。

电脑端搜索 songs、playlists。

手机端只搜索本地数据库中已同步内容。

## 6. 音频导入实现

### 6.1 支持入口

Windows 端提供：

- 选择文件导入
- 选择文件夹导入

选择文件夹时递归扫描子目录。

只接受 MP3、FLAC、M4A、WAV。

### 6.2 导入流程

导入流程：

1. 获取用户选择路径。
2. 扫描支持格式音频。
3. 对每个文件计算 file_hash。
4. 检查数据库是否已有相同 hash。
5. 尝试读取元数据。
6. 元数据不足时尝试文件名识别。
7. 文件名无意义时生成“未命名音频 XXX”。
8. 创建 song_id。
9. 复制文件到音乐库 audio 目录。
10. 写入 songs 表。
11. 返回导入结果。

### 6.3 文件名识别规则

优先读取元数据。

如果元数据没有 title/artist，再看文件名。

可以尝试识别：

```text
歌手 - 歌名
歌名 - 歌手
artist - title
title - artist
```

文件名只包含数字、时间戳、长编码、乱码、随机字符时，不允许当作歌曲名。

### 6.4 未命名音频规则

未识别音频按导入顺序命名：

```text
未命名音频 001
未命名音频 002
未命名音频 003
```

编号应基于当前数据库中已存在的未命名音频最大编号继续递增。

不要每次导入都从 001 开始。

这类音频：

- artist = 未知歌手
- album = 未知专辑
- display_name_source = unnamed
- is_pending_review = 1

### 6.5 导入安全

不得删除用户原始文件。

导入失败不得影响已成功导入文件。

复制失败时不得写入已完成状态。

不支持格式应跳过并记录原因。

重复文件应跳过或提示，不应重复复制。

## 7. 歌单实现

电脑端支持完整歌单管理。

手机端只读。

### 7.1 电脑端

需要实现：

- 创建歌单
- 重命名歌单
- 删除歌单
- 添加歌曲到歌单
- 从歌单移除歌曲
- 查看歌单歌曲
- 搜索歌单

删除歌单时只删除 playlist 和 playlist_items，不删除 songs 和音频文件。

从歌单移除歌曲时只删除关系，不删除歌曲。

### 7.2 手机端

手机端只展示已同步歌单。

不得提供创建、编辑、删除歌单入口。

手机端删除本地缓存只影响 sync_cache 和本地 audio 文件，不影响歌单结构。

## 8. 播放实现

V1 两端都播放本地文件。

不做远程在线播放。

### 8.1 Windows 端播放

播放电脑端 audio 目录中的本地文件。

支持：

- 播放
- 暂停
- 继续
- 上一首
- 下一首
- 播放进度
- 播放队列

### 8.2 Android 端播放

播放 Android APP 本地目录中的已同步文件。

支持：

- 播放
- 暂停
- 继续
- 上一首
- 下一首
- 播放进度
- 播放队列

V1 可以先保证前台播放。

如能稳定支持后台播放更好，但不得因此拖慢核心闭环。

## 9. Wi-Fi 同步实现

### 9.1 同步模式

电脑端用户手动开启同步模式。

开启后：

1. 启动本地 HTTP 服务。
2. 生成 session_id。
3. 生成临时 connect_code。
4. 获取本机局域网 IP。
5. 生成二维码。
6. 显示二维码和连接码。

关闭同步模式后：

1. 停止 HTTP 服务。
2. 清除 session_id。
3. 连接码失效。

### 9.2 二维码内容

推荐格式：

```json
{
  "app": "personal_music_sync",
  "version": 1,
  "host": "192.168.1.10",
  "port": 37891,
  "session_id": "uuid",
  "connect_code": "123456"
}
```

host 和 port 用于手机连接电脑端。

connect_code 仅当前同步模式有效。

session_id 用于当前同步会话。

### 9.3 HTTP 接口建议

电脑端作为临时同步服务。

建议接口：

```text
POST /api/sync/connect
GET  /api/sync/playlists
GET  /api/sync/playlists/{playlistId}/manifest
GET  /api/sync/songs/{songId}/download
GET  /api/sync/status
```

### 9.4 connect 接口

手机端提交：

```json
{
  "session_id": "uuid",
  "connect_code": "123456",
  "client_name": "Android Phone"
}
```

电脑端验证 session_id 和 connect_code。

验证失败返回错误。

验证成功返回临时 token。

后续请求携带 token。

V1 token 可以只在内存中保存，同步模式关闭后失效。

### 9.5 playlists 接口

返回电脑端歌单列表：

```json
{
  "playlists": [
    {
      "id": "playlist-id",
      "name": "日常听",
      "song_count": 23,
      "updated_at": "2026-07-07T10:00:00Z"
    }
  ]
}
```

### 9.6 manifest 接口

返回某个歌单完整同步清单：

```json
{
  "playlist": {
    "id": "playlist-id",
    "name": "日常听",
    "updated_at": "2026-07-07T10:00:00Z"
  },
  "songs": [
    {
      "id": "song-id",
      "title": "歌曲名",
      "artist": "歌手",
      "album": "专辑",
      "duration_ms": 240000,
      "format": "mp3",
      "file_size": 8000000,
      "file_hash": "sha256...",
      "download_url": "/api/sync/songs/song-id/download",
      "sort_order": 0,
      "is_pending_review": false
    }
  ]
}
```

手机端根据 file_hash 判断是否需要下载。

### 9.7 download 接口

根据 song_id 返回音频文件。

V1 可先实现普通文件下载。

后续可支持 Range 请求。

下载前必须验证 token。

不得允许下载未在音乐库中的任意路径文件。

必须防止路径穿越。

## 10. 手机端同步流程

手机端流程：

1. 扫码得到 host、port、session_id、connect_code。
2. 请求 connect 接口。
3. 获取 token。
4. 请求 playlists 接口。
5. 展示电脑端歌单。
6. 用户选择整个歌单。
7. 请求 manifest。
8. 与本地数据库对比。
9. 跳过已存在且 hash 一致的歌曲。
10. 下载缺失或 hash 不一致的歌曲。
11. 保存到 APP audio 目录。
12. 写入 songs、playlists、playlist_items、sync_cache。
13. 同步完成后展示本地歌单。

## 11. 同步覆盖规则

手机端歌单永远以电脑端为准。

同步某个歌单后，手机端该歌单的结构应更新为电脑端 manifest。

如果手机端本地有旧的 playlist_items，以本次 manifest 替换。

不要因为手机端旧数据而保留已被电脑端移除的歌单歌曲关系。

音频文件层面：

- hash 一致：跳过下载。
- hash 不一致：重新下载并替换本地缓存。
- 下载失败：保留旧文件，但标记同步失败。

## 12. 搜索实现

### 12.1 电脑端搜索

搜索范围：

- songs.title
- songs.artist
- songs.album
- playlists.name
- original_file_name

需要能搜索“未命名音频 001”。

### 12.2 手机端搜索

只搜索本地已同步数据。

不得搜索或展示电脑端未同步歌曲。

## 13. 错误处理

### 13.1 导入错误

需要处理：

- 文件不存在
- 权限不足
- 格式不支持
- 文件复制失败
- 元数据读取失败
- 数据库写入失败

### 13.2 同步错误

需要处理：

- 二维码无效
- 连接码错误
- 电脑端同步模式已关闭
- 手机和电脑不在同一网络
- 下载中断
- 文件 hash 不匹配
- 手机存储空间不足
- 数据库写入失败

### 13.3 播放错误

需要处理：

- 本地文件缺失
- 文件损坏
- 格式无法播放
- 缓存已删除

## 14. 安全与稳定性

V1 虽然是个人项目，但仍需基本安全。

同步服务只在用户手动开启时启动。

连接码每次打开同步模式重新生成。

旧连接码失效。

下载接口只能下载数据库中存在的歌曲文件。

不得允许客户端传任意路径下载文件。

手机端不能调用任何修改电脑端歌单的接口。

电脑端不暴露删除歌曲、修改歌单的同步接口给手机端。

## 15. 测试要点

必须覆盖：

1. 导入 MP3。
2. 导入 FLAC。
3. 导入 M4A。
4. 导入 WAV。
5. 导入文件。
6. 导入文件夹。
7. 导入数字文件名。
8. 导入乱码文件名。
9. 导入重复文件。
10. 创建多个歌单。
11. 同一首歌加入多个歌单。
12. 删除歌单不删除歌曲文件。
13. 电脑端播放。
14. 手机端扫码连接。
15. 手机端同步整个歌单。
16. 手机端离线播放。
17. 手机端搜索。
18. 电脑端搜索。
19. 手机端删除本地缓存。
20. 删除缓存后不影响电脑端。
21. 重复同步跳过 hash 一致歌曲。
22. 同步失败后可重试。

## 16. 开发优先级

优先级 P0：

- 工程搭建
- 数据模型
- SQLite
- Windows 端导入
- Windows 端歌单
- Windows 端播放
- Windows 端同步模式
- Android 端扫码连接
- Android 端歌单同步
- Android 端本地播放

优先级 P1：

- 搜索
- 待整理音频入口
- 删除本地缓存
- 同步失败重试
- 导入结果统计

优先级 P2：

- 更好的播放队列体验
- 更好的导入预览
- 更清楚的同步进度
- 更好的错误提示

V1 不做 P3 以上扩展功能。

## 17. 对开发人员的关键提醒

不要把项目做成远程播放器。

不要把手机端做成可编辑主库。

不要做云同步。

不要做 USB 同步。

不要做封面和歌词。

不要让文件名乱识别污染音乐库。

不要让删除歌单误删音频文件。

不要让手机端显示未同步歌曲。

不要把音频二进制塞进数据库。

不要破坏用户原始音频文件。

## 18. 构建与交付实现要求

V1 最终交付必须考虑实际可安装和可启动，而不是只完成开发态运行。

### 18.1 Android APK 构建

Android 端必须支持生成 APK。

Flutter 标准构建命令：

```bash
flutter build apk
```

开发人员应确认 Android 端工程配置完整，包括：

- Android package/applicationId 合理；
- minSdkVersion 与所用依赖兼容；
- 必要权限已声明，例如本地网络、网络访问、文件访问策略等；
- 如果扫码需要摄像头，应声明 Camera 权限；
- debug/release 构建路径清楚。

V1 可先交付 debug APK 或 release APK，但必须在交付说明中写清楚 APK 类型。

推荐将构建产物复制到：

```text
release/android/music_sync_player_v1.apk
```

不要让用户必须自行进入复杂的 `build/app/outputs/flutter-apk/` 目录寻找。

### 18.2 Windows exe 构建

Windows 端必须支持生成可双击启动的桌面应用。

Flutter 标准构建命令：

```bash
flutter build windows
```

构建后，Windows 产物通常不只是一个 exe，还会包含运行所需的 DLL、data 目录等文件。交付时必须保持完整目录结构。

推荐整理到：

```text
release/windows/MusicSyncPlayer/
  MusicSyncPlayer.exe
  data/
  *.dll
  其他运行所需文件
```

不要只复制 exe 文件，避免用户双击后因缺少运行文件而打不开。

### 18.3 Release 目录规范

建议项目根目录提供统一 release 输出目录：

```text
release/
  android/
    music_sync_player_v1.apk
  windows/
    MusicSyncPlayer/
      MusicSyncPlayer.exe
      data/
      *.dll
  RELEASE_NOTES.md
```

`release/` 可加入 `.gitignore`，但交付给用户时需要实际生成。

### 18.4 构建脚本建议

可以提供简单脚本辅助构建，例如：

```text
scripts/build_android_apk.ps1
scripts/build_windows_exe.ps1
scripts/package_release.ps1
```

脚本目标：

- 执行 Flutter 构建命令；
- 清理旧 release 文件；
- 复制 APK 到 release/android；
- 复制 Windows 构建产物到 release/windows/MusicSyncPlayer；
- 生成或更新 RELEASE_NOTES.md。

V1 如果暂时不写脚本，也必须在文档中提供清晰的手动构建命令和产物路径。

### 18.5 交付前检查清单

开发人员在交付前必须检查：

- `flutter analyze` 尽量无严重错误；
- Windows 端可启动；
- Android APK 可安装；
- Windows 端能导入音频；
- Windows 端能创建歌单；
- Windows 端能打开同步模式并生成二维码；
- Android 端能扫码连接；
- Android 端能同步整个歌单；
- Android 端断网后能播放已同步音乐；
- 搜索在 Windows 端和 Android 端均可使用；
- 待整理音频规则符合“未命名音频 001/002/003...”要求。

### 18.6 构建真实性和环境限制说明

如果当前开发环境没有 Android SDK、Windows 构建环境、Flutter Windows 支持或签名配置，开发人员不得声称 APK/exe 已成功生成。

必须如实说明：

- 当前已经完成到哪一步；
- 哪个构建命令无法运行；
- 缺少什么依赖；
- 用户在本地 Windows 环境中需要执行什么命令；
- 预期产物路径是什么。

