# music_database

壹加音乐的 SQLite 访问层。

创建并维护 `songs`、`playlists`、`playlist_items`、`sync_cache` 和 `synced_playlists`；提供歌曲、歌单、同步缓存、已同步歌单快照和搜索仓库。Android 搜索可限制为已经同步完成的本地内容，确保不会显示尚未下载的歌曲。

运行检查：

```powershell
flutter analyze
flutter test
```
