import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';
import 'package:path/path.dart' as p;

import 'android_library.dart';

class RemotePlaylist {
  const RemotePlaylist({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.songCount,
  });

  factory RemotePlaylist.fromJson(Map<String, Object?> json) {
    return RemotePlaylist(
      id: json['id']! as String,
      name: json['name']! as String,
      sortOrder: json['sort_order']! as int,
      songCount: json['song_count']! as int,
    );
  }

  final String id;
  final String name;
  final int sortOrder;
  final int songCount;
}

class PlaylistSyncResult {
  const PlaylistSyncResult({
    required this.downloadedCount,
    required this.skippedCount,
    required this.failedCount,
  });

  final int downloadedCount;
  final int skippedCount;
  final int failedCount;
}

class AndroidSyncClient {
  AndroidSyncClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<void> connect(SyncQrPayload payload) async {
    final response = await _postJson(_uri(payload, '/connect'), {
      'session_id': payload.sessionId,
      'connect_code': payload.connectCode,
    });
    final connect = SyncConnectResponse.fromJson(response);
    if (!connect.ok) {
      throw AppError('sync_connect_failed', connect.message);
    }
  }

  Future<List<RemotePlaylist>> fetchPlaylists(SyncQrPayload payload) async {
    final response = await _getJson(_uri(payload, '/playlists', auth: true));
    if (response['ok'] != true) {
      throw AppError(
        'sync_playlists_failed',
        response['message']?.toString() ?? '获取电脑端歌单失败',
      );
    }
    final playlists = response['playlists']! as List;
    return playlists
        .cast<Map<String, Object?>>()
        .map(RemotePlaylist.fromJson)
        .toList();
  }

  Future<PlaylistSyncResult> syncPlaylist({
    required SyncQrPayload payload,
    required RemotePlaylist remotePlaylist,
    required MusicDatabase database,
    required AndroidMusicLibraryLocation library,
  }) async {
    final manifest = await _getJson(
      _uri(payload, '/playlists/${remotePlaylist.id}/manifest', auth: true),
    );
    if (manifest['ok'] != true) {
      throw AppError(
        'sync_manifest_failed',
        manifest['message']?.toString() ?? '获取同步清单失败',
      );
    }

    final playlistJson = manifest['playlist']! as Map<String, Object?>;
    final playlist = Playlist.fromMap(playlistJson);
    database.playlists.upsert(playlist);
    database.playlists.clearSongs(playlist.id);

    final songs = (manifest['songs']! as List).cast<Map<String, Object?>>();
    var downloaded = 0;
    var skipped = 0;
    var failed = 0;

    for (final songJson in songs) {
      try {
        final songId = songJson['id']! as String;
        final format = AudioFormat.fromStorage(songJson['format']! as String);
        final expectedHash = songJson['file_hash']! as String;
        final targetPath = p.join(library.audioPath, '$songId.${format.extension}');
        final existingCache = database.sync.findCacheForSong(songId);
        final targetFile = File(targetPath);

        if (existingCache?.status == SyncCacheStatus.synced &&
            existingCache?.fileHash == expectedHash &&
            await targetFile.exists()) {
          skipped++;
        } else {
          await _downloadFile(
            Uri.parse(songJson['download_url']! as String),
            targetFile,
          );
          final actualHash = await _fileHash(targetFile);
          if (actualHash != expectedHash) {
            await targetFile.delete().catchError((_) => targetFile);
            throw AppError('sync_hash_mismatch', '下载文件校验失败');
          }
          downloaded++;
        }

        final now = DateTime.now().toUtc();
        final song = Song(
          id: songId,
          title: songJson['title']! as String,
          artist: songJson['artist']! as String,
          album: songJson['album']! as String,
          durationMs: songJson['duration_ms'] as int?,
          format: format,
          fileSize: songJson['file_size']! as int,
          fileHash: expectedHash,
          localPath: targetPath,
          originalFileName: songJson['original_file_name']! as String,
          displayNameSource: DisplayNameSource.fromStorage(
            songJson['display_name_source']! as String,
          ),
          isPendingReview: songJson['is_pending_review']! as bool,
          createdAt: now,
          updatedAt: now,
        );
        database.songs.upsert(song);
        database.playlists.addSong(
          item: PlaylistItem(
            id: 'item_${playlist.id}_${song.id}',
            playlistId: playlist.id,
            songId: song.id,
            sortOrder: songJson['sort_order']! as int,
            createdAt: now,
          ),
        );
        database.sync.upsertCacheEntry(
          SyncCacheEntry(
            id: 'cache_${song.id}',
            songId: song.id,
            playlistId: playlist.id,
            localCachePath: targetPath,
            fileHash: expectedHash,
            status: SyncCacheStatus.synced,
            syncedAt: now,
          ),
        );
      } catch (_) {
        failed++;
      }
    }

    return PlaylistSyncResult(
      downloadedCount: downloaded,
      skippedCount: skipped,
      failedCount: failed,
    );
  }

  Future<void> dispose() async {
    _httpClient.close(force: true);
  }

  Uri _uri(SyncQrPayload payload, String path, {bool auth = false}) {
    return Uri(
      scheme: 'http',
      host: payload.host,
      port: payload.port,
      path: path,
      queryParameters: auth
          ? {
              'session_id': payload.sessionId,
              'connect_code': payload.connectCode,
            }
          : null,
    );
  }

  Future<Map<String, Object?>> _getJson(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return jsonDecode(text) as Map<String, Object?>;
  }

  Future<Map<String, Object?>> _postJson(
    Uri uri,
    Map<String, Object?> body,
  ) async {
    final request = await _httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return jsonDecode(text) as Map<String, Object?>;
  }

  Future<void> _downloadFile(Uri uri, File targetFile) async {
    await targetFile.parent.create(recursive: true);
    final request = await _httpClient.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      final message = await utf8.decoder.bind(response).join();
      throw AppError('sync_download_failed', message);
    }
    final tempFile = File('${targetFile.path}.download');
    final sink = tempFile.openWrite();
    try {
      await response.pipe(sink);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
    } catch (_) {
      await tempFile.delete().catchError((_) => tempFile);
      rethrow;
    }
  }
}

Future<String> _fileHash(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
