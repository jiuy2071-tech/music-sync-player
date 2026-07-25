# 技术实现说明

本文件描述当前 V1 已实现的技术结构。产品范围以 [product_requirements.md](product_requirements.md) 和项目根 `agent.md` 为准。

## 1. 工程结构

```text
apps/windows_app/       Windows 主音乐库与同步服务
apps/android_app/       Android 只读随身播放器
packages/core/          Song、Playlist、同步缓存等共享模型
packages/database/      SQLite 初始化、仓库和搜索
packages/sync_protocol/ 二维码载荷与连接请求/响应模型
packages/player/        保留的未来抽象位置，当前未接入生产播放器
```

Windows 和 Android 目前使用各自的播放器适配层：

- Windows：`windows_audio_player.dart` 使用本机 `ffplay`，通过 Windows 进程挂起/恢复实现暂停，跳转进度会重新从目标位置启动播放。
- Android：`android_audio_player.dart` 使用 `audioplayers` 播放 APP 私有目录中的文件。

## 2. 本地存储

### Windows

默认音乐库根目录是 `D:\OnePlusMusic\Library`，可通过 `ONEPLUS_MUSIC_LIBRARY` 覆盖。导入后结构为：

```text
<library root>/
  audio/<song_id>.<ext>
  library.db
```

导入始终复制原始文件，不移动或删除用户选择的源文件。支持 MP3、FLAC、M4A、WAV；文件 SHA-256 相同即跳过重复导入。

### Android

Android 使用 `path_provider` 取得 APP Documents 目录：

```text
<app documents>/
  audio/<song_id>.<ext>
  library.db
```

只有同步状态为 `synced` 的歌曲和歌单会出现在 Android 本地库。删除缓存只删本机文件并把状态标为 `deleted`，不会请求 Windows 修改数据。

## 3. SQLite 数据

`packages/database` 创建以下表与索引：

| 表 | 用途 |
| --- | --- |
| `songs` | 歌曲信息、hash、本地路径和待整理状态 |
| `playlists` | 歌单名称和排序 |
| `playlist_items` | 歌单与歌曲关系；同一歌单中的同一首歌唯一 |
| `sync_cache` | Android 本地缓存路径、hash、状态和同步时间 |

`SearchRepository` 在 Android 使用 `sync_cache.status = synced` 限制歌曲和歌单搜索，避免展示尚未下载的电脑端内容。

## 4. 命名、导入与播放

1. Windows 导入计算 SHA-256，先检查数据库是否已有同 hash 文件。
2. 优先读取 MP3 ID3v2 元数据；其他格式或缺失元数据时使用保守文件名规则。
3. 数字、长编码、乱码或无意义名称会命名为 `未命名音频 001/002/...` 并标记为待整理。
4. Windows 播放前检查本地文件；`ffplay` 不可用时返回清晰错误。
5. Android 只从 APP 私有音频目录播放已同步文件。

## 5. 同一 Wi-Fi 同步

Windows 端由 `WindowsSyncServer` 在用户手动开启同步模式后监听随机端口。每次启动会生成新的 `session_id` 与 6 位 `connect_code`，关闭同步模式后立即失效。

二维码载荷：

```json
{
  "app": "personal_music_sync",
  "version": 1,
  "host": "192.168.1.10",
  "port": 37891,
  "session_id": "temporary-session-id",
  "connect_code": "123456"
}
```

### 当前 HTTP 接口

| 方法 | 路径 | 作用 |
| --- | --- | --- |
| `GET` | `/health` | 同步服务健康检查 |
| `POST` | `/connect` | 用 `session_id` 和 `connect_code` 验证连接 |
| `GET` | `/playlists` | 返回电脑端歌单列表 |
| `GET` | `/playlists/{playlistId}/manifest` | 返回整张歌单与歌曲同步清单 |
| `GET` | `/songs/{songId}/file` | 返回数据库中登记的本地音频文件 |

除 `/health` 和 `/connect` 外，接口都要求查询参数：

```text
session_id=<current session>&connect_code=<current code>
```

服务仅按数据库里的 `songId` 找文件，不接受客户端任意路径；下载响应附带歌曲 ID 和 hash。

### Android 同步步骤

1. 扫描二维码，或粘贴载荷作为备用。
2. `POST /connect` 验证会话与连接码。
3. 读取 `/playlists`，选择整张歌单。
4. 读取 manifest；hash 相同且本地文件存在时跳过下载。
5. 下载缺失或变化文件到 APP 私有 `audio/` 目录，核对 SHA-256。
6. 写入歌曲、歌单、关系和 `sync_cache`。
7. 成功后 Android 清除搜索条件、刷新本地库、选中刚同步歌单并返回音乐库。

单首下载失败不会抹掉已成功文件；结果会保留失败数量和第一个失败原因，用户可重新同步该歌单。

## 6. Android 界面与权限

Android 的底部导航为：

- `音乐库`：搜索和播放已同步歌曲。
- `歌单`：查看已同步歌单及其本地歌曲。
- `同步音乐`：优先扫码，手动粘贴为备用；连接后显示电脑端歌单。

播放器提供迷你播放器和完整播放面板，均支持播放/暂停、上一首、下一首和进度跳转。Android Manifest 已声明网络、网络状态和相机权限，并允许对局域网 HTTP 同步服务使用明文连接。

## 7. 构建与交付

Flutter 位于 `D:\Dev\flutter`，Android SDK 位于 `D:\Android\Sdk`。交付命令：

```powershell
cd D:\Projects\music_sync_player\apps\windows_app
D:\Dev\flutter\bin\flutter.bat analyze
D:\Dev\flutter\bin\flutter.bat test
D:\Dev\flutter\bin\flutter.bat build windows

cd D:\Projects\music_sync_player\apps\android_app
D:\Dev\flutter\bin\flutter.bat analyze
D:\Dev\flutter\bin\flutter.bat test
D:\Dev\flutter\bin\flutter.bat build apk --debug
```

交付时必须复制完整 Windows Release 目录，而不是单独复制 EXE：

```text
release/windows/MusicSyncPlayer/YijiaMusic.exe
release/android/music_sync_player_v1_debug.apk
```

`release/`、`build/`、`.dart_tool/`、SDK、缓存、APK 和 EXE 均被 Git 忽略。

## 8. 自动验证与人工边界

自动测试覆盖生成音频的导入、命名、重复检测和播放探测，以及 Windows 同步服务、Android 同步客户端、SQLite 查询和 Android 导航入口。项目内 `manual_test_audio/` 是非敏感生成样本且不提交。

真实 Windows 选择器、Android 相机扫码、同一 Wi-Fi 联机和离线播放仍需真机人工验收；自动构建成功不等同于这些真实场景已经验证。
