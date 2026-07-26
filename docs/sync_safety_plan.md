# V1 同步安全与主端对账

## 目标与边界

Windows 是唯一数据主端。Android 只保存已同步歌单快照和本地音频缓存，不会反向修改电脑曲库。

本轮只加强同一 Wi-Fi 下的单向同步可靠性，不增加云同步、远程在线播放、USB、蓝牙、封面、歌词、手机端编辑歌单或手机端导入音乐。

## 必须保持的规则

1. 下载或校验失败时，手机原有歌单和可播放缓存保持不变。
2. 新音频只能在文件大小和 SHA-256 都正确后进入正式缓存。
3. 歌曲、歌单关系、缓存状态和已同步快照必须在同一个 SQLite 事务中提交。
4. 电脑删除歌单后，手机下次连接会移除对应旧快照。
5. 歌曲只有在没有任何本地歌单引用时才能作为孤儿缓存清理。
6. 下载地址必须属于当前二维码中的主机、端口、会话和连接码。
7. 手机手动连接的备用方式是“粘贴完整连接信息”，不是只输入 6 位连接码。

## 当前代码位置

| 责任 | 文件 |
| --- | --- |
| Android 临时下载、校验、事务、替换、重试、空间检查和对账 | `apps/android_app/lib/sync_client.dart` |
| Android 系统剩余空间接口 | `apps/android_app/android/app/src/main/kotlin/com/example/android_app/MainActivity.kt` |
| Android 连接后刷新与对账结果提示 | `apps/android_app/lib/android_shell.dart` |
| Windows 权威歌单清单、版本和受限下载 | `apps/windows_app/lib/sync_server.dart` |
| SQLite 表、事务、快照、引用和搜索 | `packages/database/lib/music_database.dart` |
| Android 负面回归测试 | `apps/android_app/test/sync_client_test.dart` |
| Windows 协议回归测试 | `apps/windows_app/test/sync_server_test.dart` |
| 数据库事务与引用测试 | `packages/database/test/music_database_test.dart` |

## 数据库结构

- `songs`：本地歌曲信息和正式缓存路径。
- `playlists`：手机保留的歌单快照。
- `playlist_items`：歌单对歌曲的实际引用，也是孤儿判断依据。
- `sync_cache`：歌曲缓存 Hash、路径、状态和同步时间。
- `synced_playlists`：已同步歌单、Windows 内容版本和同步时间；空歌单也能靠此表显示。

旧 Android 数据库启动时会把已有的非空同步歌单补入 `synced_playlists`，不清空原有歌曲。

## 协议字段

`GET /playlists` 返回：

```json
{
  "ok": true,
  "catalog_version": "<SHA-256>",
  "playlists": [
    {
      "id": "playlist-id",
      "name": "歌单名",
      "sort_order": 0,
      "song_count": 12,
      "version": "<SHA-256>"
    }
  ]
}
```

`GET /playlists/{playlistId}/manifest` 额外返回 `playlist_version`。Android 发现列表版本与清单版本不一致时会停止本次同步并要求刷新，避免把歌单变化前后的数据混在一起。

音频下载地址仍携带当前 `session_id` 和 `connect_code`。Android 会确认协议、主机、端口、路径和两个会话字段都与当前连接一致。

## 安全同步顺序

1. 连接 Windows 并取得权威歌单清单。
2. 移除 Windows 已删除的本地歌单快照。
3. 选择整张歌单并读取带版本的 manifest。
4. 检查歌曲 ID、Hash、文件大小、下载地址和目标路径。
5. 核对已有缓存；只计算确实需要下载的空间。
6. 检查手机剩余空间并保留 16 MB 安全余量。
7. 下载到 APP 私有 `.sync_staging`，检查大小和 SHA-256。
8. 在 SQLite 事务中写入歌曲、歌单关系、缓存和歌单快照。
9. 正式缓存先改名为备份，再把已校验临时文件原子改名到正式位置。
10. 任何提交或替换错误都会回滚数据库并恢复旧文件。
11. 根据 `playlist_items` 引用清理孤儿；共用歌曲不会误删。
12. 清理结果返回 Android 界面，失败项保留给下次处理。

## 已覆盖的负面测试

| 场景 | 预期 |
| --- | --- |
| 下载内容短于 manifest 大小 | 旧歌单和旧文件保持不变 |
| 下载内容 Hash 错误 | 不替换原本可播放的缓存 |
| 歌曲 ID 尝试路径越界 | 写文件前拒绝 |
| 手机空间不足 | 不发起音频下载，不修改数据库 |
| Windows 第一次返回临时错误 | 使用同一会话有限重试 |
| 同步空歌单 | Android 仍能显示空歌单 |
| 一首歌属于两张歌单 | 删除一张歌单不删除共用文件 |
| 最后一个歌单引用被删除 | 音频与数据库孤儿一起清理 |
| 数据库事务中途抛错 | 所有写入回滚 |
| Windows 歌单成员变化 | 清单版本和歌单版本发生变化 |

## 仍需真机确认

- 下载过程中关闭 Wi-Fi、关闭 Windows 同步模式和结束 Windows 程序。
- 大文件下载超过 20 秒但持续有数据时不会被误判为超时。
- 手机真实空间接近不足时的系统可用空间数值和提示。
- 电脑删除歌单、移除歌曲、创建空歌单后，重新连接和重新同步的实际结果。
- 多张歌单共用同一音频时，连续删除和离线播放结果。
- Android 安装新 APK 后从旧数据库自动补齐同步歌单快照。

## 后续顺序

P0 只剩真机断网、旧数据库升级和主端删除回归，以及 Windows 播放后端的启动能力检查。P1 才考虑同步进度、取消和失败项重试；P2 才考虑排序、后台同步、性能与无障碍。V1 不扩展云端或双向同步。
