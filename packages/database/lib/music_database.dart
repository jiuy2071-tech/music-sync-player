import 'package:music_core/music_core.dart';
import 'package:sqlite3/sqlite3.dart';

class MusicDatabase {
  MusicDatabase._(this.db);

  final Database db;

  late final SongRepository songs = SongRepository(db);
  late final PlaylistRepository playlists = PlaylistRepository(db);
  late final SyncRepository sync = SyncRepository(db);
  late final SearchRepository search = SearchRepository(db);

  static MusicDatabase open(String path) {
    final database = sqlite3.open(path);
    final musicDatabase = MusicDatabase._(database);
    musicDatabase.initialize();
    return musicDatabase;
  }

  static MusicDatabase memory() {
    final database = sqlite3.openInMemory();
    final musicDatabase = MusicDatabase._(database);
    musicDatabase.initialize();
    return musicDatabase;
  }

  void initialize() {
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute(_createSongsTable);
    db.execute(_createPlaylistsTable);
    db.execute(_createPlaylistItemsTable);
    db.execute(_createSyncCacheTable);
    db.execute(_createSyncedPlaylistsTable);
    db.execute(_createSyncOperationsTable);
    db.execute(_createIndexes);
    db.execute(_bootstrapSyncedPlaylists);
  }

  Future<T> transaction<T>(Future<T> Function() action) async {
    db.execute('BEGIN IMMEDIATE;');
    try {
      final result = await action();
      db.execute('COMMIT;');
      return result;
    } catch (error, stackTrace) {
      try {
        db.execute('ROLLBACK;');
      } catch (_) {
        // Preserve the failure that caused the transaction to be rolled back.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void close() => db.close();
}

class SongRepository {
  SongRepository(this._db);

  final Database _db;

  void upsert(Song song) {
    _db.execute('''
      INSERT INTO songs (
        id, title, artist, album, duration_ms, format, file_size, file_hash,
        local_path, original_file_name, display_name_source, is_pending_review,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        artist = excluded.artist,
        album = excluded.album,
        duration_ms = excluded.duration_ms,
        format = excluded.format,
        file_size = excluded.file_size,
        file_hash = excluded.file_hash,
        local_path = excluded.local_path,
        original_file_name = excluded.original_file_name,
        display_name_source = excluded.display_name_source,
        is_pending_review = excluded.is_pending_review,
        updated_at = excluded.updated_at
      ''', _songArgs(song));
  }

  Song? findById(String id) {
    final result = _db.select('SELECT * FROM songs WHERE id = ?', [id]);
    if (result.isEmpty) {
      return null;
    }
    return Song.fromMap(result.first);
  }

  Song? findByHash(String fileHash) {
    final result = _db.select(
      'SELECT * FROM songs WHERE file_hash = ? LIMIT 1',
      [fileHash],
    );
    if (result.isEmpty) {
      return null;
    }
    return Song.fromMap(result.first);
  }

  List<Song> all() {
    final result = _db.select('SELECT * FROM songs ORDER BY created_at DESC');
    return result.map(Song.fromMap).toList();
  }

  List<Song> pendingReview() {
    final result = _db.select(
      'SELECT * FROM songs WHERE is_pending_review = 1 ORDER BY created_at',
    );
    return result.map(Song.fromMap).toList();
  }

  int nextUnnamedAudioNumber() {
    final result = _db.select(
      '''
      SELECT title FROM songs
      WHERE display_name_source = ?
        AND title LIKE '未命名音频 %'
      ''',
      [DisplayNameSource.unnamed.value],
    );
    var maxNumber = 0;
    for (final row in result) {
      final title = row['title'] as String;
      final match = RegExp(r'^未命名音频 (\d+)$').firstMatch(title);
      if (match == null) {
        continue;
      }
      final number = int.tryParse(match.group(1)!);
      if (number != null && number > maxNumber) {
        maxNumber = number;
      }
    }
    return maxNumber + 1;
  }

  void deleteById(String id) {
    _db.execute('DELETE FROM songs WHERE id = ?', [id]);
  }
}

class PlaylistRepository {
  PlaylistRepository(this._db);

  final Database _db;

  void upsert(Playlist playlist) {
    _db.execute(
      '''
      INSERT INTO playlists (id, name, sort_order, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        sort_order = excluded.sort_order,
        updated_at = excluded.updated_at
      ''',
      [
        playlist.id,
        playlist.name,
        playlist.sortOrder,
        playlist.createdAt.toIso8601String(),
        playlist.updatedAt.toIso8601String(),
      ],
    );
  }

  Playlist? findById(String id) {
    final result = _db.select('SELECT * FROM playlists WHERE id = ?', [id]);
    if (result.isEmpty) {
      return null;
    }
    return Playlist.fromMap(result.first);
  }

  List<Playlist> all() {
    final result = _db.select(
      'SELECT * FROM playlists ORDER BY sort_order, created_at',
    );
    return result.map(Playlist.fromMap).toList();
  }

  void addSong({required PlaylistItem item}) {
    _db.execute(
      '''
      INSERT INTO playlist_items (
        id, playlist_id, song_id, sort_order, created_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(playlist_id, song_id) DO UPDATE SET
        sort_order = excluded.sort_order
      ''',
      [
        item.id,
        item.playlistId,
        item.songId,
        item.sortOrder,
        item.createdAt.toIso8601String(),
      ],
    );
  }

  void removeSong({required String playlistId, required String songId}) {
    _db.execute(
      'DELETE FROM playlist_items WHERE playlist_id = ? AND song_id = ?',
      [playlistId, songId],
    );
  }

  void clearSongs(String playlistId) {
    _db.execute('DELETE FROM playlist_items WHERE playlist_id = ?', [
      playlistId,
    ]);
  }

  List<Song> songsForPlaylist(String playlistId) {
    final result = _db.select(
      '''
      SELECT songs.* FROM songs
      INNER JOIN playlist_items ON playlist_items.song_id = songs.id
      WHERE playlist_items.playlist_id = ?
      ORDER BY playlist_items.sort_order, playlist_items.created_at
      ''',
      [playlistId],
    );
    return result.map(Song.fromMap).toList();
  }

  void deletePlaylist(String playlistId) {
    _db.execute('DELETE FROM playlists WHERE id = ?', [playlistId]);
  }
}

class SyncRepository {
  SyncRepository(this._db);

  final Database _db;

  void upsertCacheEntry(SyncCacheEntry entry) {
    _db.execute(
      '''
      INSERT INTO sync_cache (
        id, song_id, playlist_id, local_cache_path, file_hash, status, synced_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        playlist_id = excluded.playlist_id,
        local_cache_path = excluded.local_cache_path,
        file_hash = excluded.file_hash,
        status = excluded.status,
        synced_at = excluded.synced_at
      ''',
      [
        entry.id,
        entry.songId,
        entry.playlistId,
        entry.localCachePath,
        entry.fileHash,
        entry.status.value,
        entry.syncedAt.toIso8601String(),
      ],
    );
  }

  SyncCacheEntry? findCacheForSong(String songId) {
    final result = _db.select(
      'SELECT * FROM sync_cache WHERE song_id = ? LIMIT 1',
      [songId],
    );
    if (result.isEmpty) {
      return null;
    }
    return SyncCacheEntry.fromMap(result.first);
  }

  void markDeleted(String songId, DateTime deletedAt) {
    _db.execute(
      '''
      UPDATE sync_cache
      SET status = ?, synced_at = ?
      WHERE song_id = ?
      ''',
      [SyncCacheStatus.deleted.value, deletedAt.toIso8601String(), songId],
    );
  }

  void upsertPlaylistSnapshot({
    required String playlistId,
    required String sourceVersion,
    required DateTime syncedAt,
  }) {
    _db.execute(
      '''
      INSERT INTO synced_playlists (playlist_id, source_version, synced_at)
      VALUES (?, ?, ?)
      ON CONFLICT(playlist_id) DO UPDATE SET
        source_version = excluded.source_version,
        synced_at = excluded.synced_at
      ''',
      [playlistId, sourceVersion, syncedAt.toIso8601String()],
    );
  }

  List<String> syncedPlaylistIds() {
    final result = _db.select(
      'SELECT playlist_id FROM synced_playlists ORDER BY playlist_id',
    );
    return result.map((row) => row['playlist_id']! as String).toList();
  }

  String? playlistSourceVersion(String playlistId) {
    final result = _db.select(
      'SELECT source_version FROM synced_playlists WHERE playlist_id = ?',
      [playlistId],
    );
    if (result.isEmpty) {
      return null;
    }
    return result.first['source_version']! as String;
  }

  List<Song> unreferencedSyncedSongs() {
    final result = _db.select(
      '''
      SELECT songs.* FROM songs
      INNER JOIN sync_cache ON sync_cache.song_id = songs.id
      WHERE sync_cache.status = ?
        AND NOT EXISTS (
          SELECT 1 FROM playlist_items
          WHERE playlist_items.song_id = songs.id
        )
      ORDER BY songs.id
      ''',
      [SyncCacheStatus.synced.value],
    );
    return result.map(Song.fromMap).toList();
  }

  void markOperationCommitted(String operationId, DateTime committedAt) {
    _db.execute(
      '''
      INSERT INTO sync_operations (operation_id, committed_at)
      VALUES (?, ?)
      ON CONFLICT(operation_id) DO UPDATE SET
        committed_at = excluded.committed_at
      ''',
      [operationId, committedAt.toIso8601String()],
    );
  }

  bool isOperationCommitted(String operationId) {
    final result = _db.select(
      'SELECT 1 FROM sync_operations WHERE operation_id = ? LIMIT 1',
      [operationId],
    );
    return result.isNotEmpty;
  }

  List<String> committedOperationIds() {
    final result = _db.select(
      'SELECT operation_id FROM sync_operations ORDER BY committed_at',
    );
    return result.map((row) => row['operation_id']! as String).toList();
  }

  void removeCommittedOperation(String operationId) {
    _db.execute('DELETE FROM sync_operations WHERE operation_id = ?', [
      operationId,
    ]);
  }
}

class SearchRepository {
  SearchRepository(this._db);

  final Database _db;

  List<Song> searchSongs(String keyword, {bool syncedOnly = false}) {
    final pattern = _likePattern(keyword);
    final sql = syncedOnly
        ? '''
          SELECT DISTINCT songs.* FROM songs
          INNER JOIN sync_cache ON sync_cache.song_id = songs.id
          WHERE sync_cache.status = ?
            AND (
              songs.title LIKE ? OR
              songs.artist LIKE ? OR
              songs.album LIKE ? OR
              songs.original_file_name LIKE ?
            )
          ORDER BY songs.title
          '''
        : '''
          SELECT * FROM songs
          WHERE title LIKE ?
             OR artist LIKE ?
             OR album LIKE ?
             OR original_file_name LIKE ?
          ORDER BY title
          ''';
    final args = syncedOnly
        ? [SyncCacheStatus.synced.value, pattern, pattern, pattern, pattern]
        : [pattern, pattern, pattern, pattern];
    final result = _db.select(sql, args);
    return result.map(Song.fromMap).toList();
  }

  List<Playlist> searchPlaylists(String keyword, {bool syncedOnly = false}) {
    final pattern = _likePattern(keyword);
    final sql = syncedOnly
        ? '''
          SELECT playlists.* FROM playlists
          INNER JOIN synced_playlists
            ON synced_playlists.playlist_id = playlists.id
          WHERE playlists.name LIKE ?
          ORDER BY playlists.sort_order, playlists.name
          '''
        : '''
          SELECT * FROM playlists
          WHERE name LIKE ?
          ORDER BY sort_order, name
          ''';
    final args = [pattern];
    final result = _db.select(sql, args);
    return result.map(Playlist.fromMap).toList();
  }
}

List<Object?> _songArgs(Song song) {
  return [
    song.id,
    song.title,
    song.artist,
    song.album,
    song.durationMs,
    song.format.extension,
    song.fileSize,
    song.fileHash,
    song.localPath,
    song.originalFileName,
    song.displayNameSource.value,
    song.isPendingReview ? 1 : 0,
    song.createdAt.toIso8601String(),
    song.updatedAt.toIso8601String(),
  ];
}

String _likePattern(String keyword) {
  final escaped = keyword.trim().replaceAll('%', r'\%').replaceAll('_', r'\_');
  return '%$escaped%';
}

const _createSongsTable = '''
CREATE TABLE IF NOT EXISTS songs (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  album TEXT NOT NULL,
  duration_ms INTEGER,
  format TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  file_hash TEXT NOT NULL,
  local_path TEXT NOT NULL,
  original_file_name TEXT NOT NULL,
  display_name_source TEXT NOT NULL,
  is_pending_review INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

const _createPlaylistsTable = '''
CREATE TABLE IF NOT EXISTS playlists (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

const _createPlaylistItemsTable = '''
CREATE TABLE IF NOT EXISTS playlist_items (
  id TEXT PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
  FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE,
  UNIQUE (playlist_id, song_id)
);
''';

const _createSyncCacheTable = '''
CREATE TABLE IF NOT EXISTS sync_cache (
  id TEXT PRIMARY KEY,
  song_id TEXT NOT NULL,
  playlist_id TEXT,
  local_cache_path TEXT NOT NULL,
  file_hash TEXT NOT NULL,
  status TEXT NOT NULL,
  synced_at TEXT NOT NULL,
  FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE,
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE SET NULL
);
''';

const _createSyncedPlaylistsTable = '''
CREATE TABLE IF NOT EXISTS synced_playlists (
  playlist_id TEXT PRIMARY KEY,
  source_version TEXT NOT NULL,
  synced_at TEXT NOT NULL,
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
);
''';

const _createSyncOperationsTable = '''
CREATE TABLE IF NOT EXISTS sync_operations (
  operation_id TEXT PRIMARY KEY,
  committed_at TEXT NOT NULL
);
''';

const _bootstrapSyncedPlaylists = '''
INSERT OR IGNORE INTO synced_playlists (
  playlist_id, source_version, synced_at
)
SELECT
  playlist_items.playlist_id,
  'legacy',
  MAX(sync_cache.synced_at)
FROM playlist_items
INNER JOIN sync_cache ON sync_cache.song_id = playlist_items.song_id
WHERE sync_cache.status = 'synced'
GROUP BY playlist_items.playlist_id;
''';

const _createIndexes = '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_songs_file_hash ON songs(file_hash);
CREATE INDEX IF NOT EXISTS idx_songs_title ON songs(title);
CREATE INDEX IF NOT EXISTS idx_songs_pending_review ON songs(is_pending_review);
CREATE INDEX IF NOT EXISTS idx_playlists_name ON playlists(name);
CREATE INDEX IF NOT EXISTS idx_playlist_items_playlist
  ON playlist_items(playlist_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_sync_cache_song ON sync_cache(song_id);
CREATE INDEX IF NOT EXISTS idx_sync_cache_status ON sync_cache(status);
CREATE INDEX IF NOT EXISTS idx_synced_playlists_synced_at
  ON synced_playlists(synced_at);
CREATE INDEX IF NOT EXISTS idx_sync_operations_committed_at
  ON sync_operations(committed_at);
''';
