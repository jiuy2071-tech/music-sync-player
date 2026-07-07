enum AudioFormat {
  mp3('mp3'),
  flac('flac'),
  m4a('m4a'),
  wav('wav');

  const AudioFormat(this.extension);

  final String extension;

  static AudioFormat? fromExtension(String value) {
    final normalized = value.toLowerCase().replaceFirst('.', '');
    for (final format in AudioFormat.values) {
      if (format.extension == normalized) {
        return format;
      }
    }
    return null;
  }

  static AudioFormat fromStorage(String value) {
    final format = fromExtension(value);
    if (format == null) {
      throw ArgumentError.value(value, 'value', 'Unsupported audio format');
    }
    return format;
  }
}

enum DisplayNameSource {
  metadata('metadata'),
  filename('filename'),
  unnamed('unnamed');

  const DisplayNameSource(this.value);

  final String value;

  static DisplayNameSource fromStorage(String value) {
    return DisplayNameSource.values.firstWhere(
      (source) => source.value == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unsupported display name source',
      ),
    );
  }
}

enum SyncCacheStatus {
  synced('synced'),
  failed('failed'),
  deleted('deleted');

  const SyncCacheStatus(this.value);

  final String value;

  static SyncCacheStatus fromStorage(String value) {
    return SyncCacheStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unsupported sync cache status',
      ),
    );
  }
}

class SongMetadata {
  const SongMetadata({this.title, this.artist, this.album, this.durationMs});

  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
}

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.format,
    required this.fileSize,
    required this.fileHash,
    required this.localPath,
    required this.originalFileName,
    required this.displayNameSource,
    required this.isPendingReview,
    required this.createdAt,
    required this.updatedAt,
    this.durationMs,
  });

  factory Song.fromMap(Map<String, Object?> map) {
    return Song(
      id: map['id']! as String,
      title: map['title']! as String,
      artist: map['artist']! as String,
      album: map['album']! as String,
      durationMs: map['duration_ms'] as int?,
      format: AudioFormat.fromStorage(map['format']! as String),
      fileSize: map['file_size']! as int,
      fileHash: map['file_hash']! as String,
      localPath: map['local_path']! as String,
      originalFileName: map['original_file_name']! as String,
      displayNameSource: DisplayNameSource.fromStorage(
        map['display_name_source']! as String,
      ),
      isPendingReview: (map['is_pending_review']! as int) == 1,
      createdAt: DateTime.parse(map['created_at']! as String),
      updatedAt: DateTime.parse(map['updated_at']! as String),
    );
  }

  final String id;
  final String title;
  final String artist;
  final String album;
  final int? durationMs;
  final AudioFormat format;
  final int fileSize;
  final String fileHash;
  final String localPath;
  final String originalFileName;
  final DisplayNameSource displayNameSource;
  final bool isPendingReview;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'duration_ms': durationMs,
      'format': format.extension,
      'file_size': fileSize,
      'file_hash': fileHash,
      'local_path': localPath,
      'original_file_name': originalFileName,
      'display_name_source': displayNameSource.value,
      'is_pending_review': isPendingReview ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Song copyWith({
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? localPath,
    bool? isPendingReview,
    DateTime? updatedAt,
  }) {
    return Song(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      format: format,
      fileSize: fileSize,
      fileHash: fileHash,
      localPath: localPath ?? this.localPath,
      originalFileName: originalFileName,
      displayNameSource: displayNameSource,
      isPendingReview: isPendingReview ?? this.isPendingReview,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromMap(Map<String, Object?> map) {
    return Playlist(
      id: map['id']! as String,
      name: map['name']! as String,
      sortOrder: map['sort_order']! as int,
      createdAt: DateTime.parse(map['created_at']! as String),
      updatedAt: DateTime.parse(map['updated_at']! as String),
    );
  }

  final String id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class PlaylistItem {
  const PlaylistItem({
    required this.id,
    required this.playlistId,
    required this.songId,
    required this.sortOrder,
    required this.createdAt,
  });

  factory PlaylistItem.fromMap(Map<String, Object?> map) {
    return PlaylistItem(
      id: map['id']! as String,
      playlistId: map['playlist_id']! as String,
      songId: map['song_id']! as String,
      sortOrder: map['sort_order']! as int,
      createdAt: DateTime.parse(map['created_at']! as String),
    );
  }

  final String id;
  final String playlistId;
  final String songId;
  final int sortOrder;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'playlist_id': playlistId,
      'song_id': songId,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class ImportResult {
  const ImportResult({
    required this.importedSongs,
    required this.skippedFiles,
    required this.failedFiles,
    required this.pendingReviewCount,
  });

  final List<Song> importedSongs;
  final List<ImportSkippedFile> skippedFiles;
  final List<ImportFailedFile> failedFiles;
  final int pendingReviewCount;

  int get importedCount => importedSongs.length;
}

class ImportSkippedFile {
  const ImportSkippedFile({required this.path, required this.reason});

  final String path;
  final String reason;
}

class ImportFailedFile {
  const ImportFailedFile({required this.path, required this.message});

  final String path;
  final String message;
}

class SyncSession {
  const SyncSession({
    required this.sessionId,
    required this.connectCode,
    required this.host,
    required this.port,
    required this.createdAt,
  });

  final String sessionId;
  final String connectCode;
  final String host;
  final int port;
  final DateTime createdAt;

  Map<String, Object?> toQrPayload() {
    return {
      'app': 'personal_music_sync',
      'version': 1,
      'host': host,
      'port': port,
      'session_id': sessionId,
      'connect_code': connectCode,
    };
  }
}

class SyncManifest {
  const SyncManifest({required this.playlist, required this.songs});

  final Playlist playlist;
  final List<SyncManifestSong> songs;
}

class SyncManifestSong {
  const SyncManifestSong({
    required this.song,
    required this.downloadUrl,
    required this.sortOrder,
  });

  final Song song;
  final String downloadUrl;
  final int sortOrder;

  Map<String, Object?> toMap() {
    return {
      ...song.toMap(),
      'download_url': downloadUrl,
      'sort_order': sortOrder,
    };
  }
}

class SyncDownloadTask {
  const SyncDownloadTask({
    required this.songId,
    required this.downloadUrl,
    required this.expectedHash,
    required this.targetPath,
  });

  final String songId;
  final String downloadUrl;
  final String expectedHash;
  final String targetPath;
}

class SyncCacheEntry {
  const SyncCacheEntry({
    required this.id,
    required this.songId,
    required this.localCachePath,
    required this.fileHash,
    required this.status,
    required this.syncedAt,
    this.playlistId,
  });

  factory SyncCacheEntry.fromMap(Map<String, Object?> map) {
    return SyncCacheEntry(
      id: map['id']! as String,
      songId: map['song_id']! as String,
      playlistId: map['playlist_id'] as String?,
      localCachePath: map['local_cache_path']! as String,
      fileHash: map['file_hash']! as String,
      status: SyncCacheStatus.fromStorage(map['status']! as String),
      syncedAt: DateTime.parse(map['synced_at']! as String),
    );
  }

  final String id;
  final String songId;
  final String? playlistId;
  final String localCachePath;
  final String fileHash;
  final SyncCacheStatus status;
  final DateTime syncedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'song_id': songId,
      'playlist_id': playlistId,
      'local_cache_path': localCachePath,
      'file_hash': fileHash,
      'status': status.value,
      'synced_at': syncedAt.toIso8601String(),
    };
  }
}

class AppError implements Exception {
  const AppError(this.code, this.message, {this.cause});

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'AppError($code): $message';
}
