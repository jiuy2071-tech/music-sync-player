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
    required this.localSongCount,
    required this.failureMessages,
  });

  final int downloadedCount;
  final int skippedCount;
  final int failedCount;
  final int localSongCount;
  final List<String> failureMessages;

  bool get hasFailures => failedCount > 0;
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
    _requireSafeId(remotePlaylist.id, 'playlist');
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
    if (playlist.id != remotePlaylist.id) {
      throw const AppError('sync_manifest_invalid', '同步清单中的歌单与所选歌单不一致');
    }

    final songJsonList = (manifest['songs']! as List)
        .cast<Map<String, Object?>>();
    final songIds = <String>{};
    final stagingDirectory = Directory(
      p.join(
        library.rootPath,
        '.sync_staging',
        '${playlist.id}_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await stagingDirectory.create(recursive: true);

    final preparedSongs = <_PreparedSong>[];
    var skipped = 0;
    var preserveStaging = false;
    try {
      for (var index = 0; index < songJsonList.length; index++) {
        final songJson = songJsonList[index];
        final songId = songJson['id']! as String;
        _requireSafeId(songId, 'song');
        if (!songIds.add(songId)) {
          throw AppError('sync_manifest_invalid', '同步清单包含重复歌曲：$songId');
        }

        final format = AudioFormat.fromStorage(songJson['format']! as String);
        final expectedHash = songJson['file_hash']! as String;
        if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedHash)) {
          throw AppError('sync_manifest_invalid', '歌曲 $songId 的 Hash 格式无效');
        }
        final expectedSize = songJson['file_size']! as int;
        if (expectedSize <= 0) {
          throw AppError('sync_manifest_invalid', '歌曲 $songId 的文件大小无效');
        }

        final targetPath = p.join(
          library.audioPath,
          '$songId.${format.extension}',
        );
        _requirePathWithin(library.audioPath, targetPath);
        final existingCache = database.sync.findCacheForSong(songId);
        final targetFile = File(targetPath);
        final canReuse =
            existingCache?.status == SyncCacheStatus.synced &&
            existingCache?.fileHash == expectedHash &&
            await targetFile.exists() &&
            await targetFile.length() == expectedSize &&
            await _fileHash(targetFile) == expectedHash;

        File? stagedFile;
        if (canReuse) {
          skipped++;
        } else {
          final downloadUri = _validatedDownloadUri(
            payload,
            songId,
            songJson['download_url']! as String,
          );
          stagedFile = File(
            p.join(
              stagingDirectory.path,
              'downloads',
              '$index.${format.extension}',
            ),
          );
          await _downloadFile(downloadUri, stagedFile);
          final actualSize = await stagedFile.length();
          if (actualSize != expectedSize) {
            throw AppError('sync_size_mismatch', '歌曲 $songId 下载不完整');
          }
          final actualHash = await _fileHash(stagedFile);
          if (actualHash != expectedHash) {
            throw AppError('sync_hash_mismatch', '歌曲 $songId 下载文件校验失败');
          }
        }

        final now = DateTime.now().toUtc();
        final existingSong = database.songs.findById(songId);
        final song = Song(
          id: songId,
          title: songJson['title']! as String,
          artist: songJson['artist']! as String,
          album: songJson['album']! as String,
          durationMs: songJson['duration_ms'] as int?,
          format: format,
          fileSize: expectedSize,
          fileHash: expectedHash,
          localPath: targetPath,
          originalFileName: songJson['original_file_name']! as String,
          displayNameSource: DisplayNameSource.fromStorage(
            songJson['display_name_source']! as String,
          ),
          isPendingReview: _readBool(songJson['is_pending_review']),
          createdAt: existingSong?.createdAt ?? now,
          updatedAt: now,
        );
        preparedSongs.add(
          _PreparedSong(
            song: song,
            item: PlaylistItem(
              id: 'item_${playlist.id}_${song.id}',
              playlistId: playlist.id,
              songId: song.id,
              sortOrder: songJson['sort_order']! as int,
              createdAt: now,
            ),
            cache: SyncCacheEntry(
              id: 'cache_${song.id}',
              songId: song.id,
              playlistId: playlist.id,
              localCachePath: targetPath,
              fileHash: expectedHash,
              status: SyncCacheStatus.synced,
              syncedAt: now,
            ),
            targetFile: targetFile,
            stagedFile: stagedFile,
          ),
        );
      }

      final replacements = <_AppliedReplacement>[];
      try {
        await database.transaction<void>(() async {
          database.playlists.upsert(playlist);
          database.playlists.clearSongs(playlist.id);
          for (final prepared in preparedSongs) {
            database.songs.upsert(prepared.song);
            database.playlists.addSong(item: prepared.item);
            database.sync.upsertCacheEntry(prepared.cache);
          }
          for (var index = 0; index < preparedSongs.length; index++) {
            final prepared = preparedSongs[index];
            final stagedFile = prepared.stagedFile;
            if (stagedFile == null) {
              continue;
            }
            await _replaceFile(
              stagedFile: stagedFile,
              targetFile: prepared.targetFile,
              backupDirectory: Directory(
                p.join(stagingDirectory.path, 'backups'),
              ),
              backupIndex: index,
              replacements: replacements,
            );
          }
        });
      } catch (error, stackTrace) {
        try {
          await _restoreReplacements(replacements);
        } catch (restoreError) {
          preserveStaging = true;
          throw AppError(
            'sync_restore_failed',
            '同步失败，旧缓存恢复失败：$restoreError；原始错误：$error',
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }

      return PlaylistSyncResult(
        downloadedCount: preparedSongs.length - skipped,
        skippedCount: skipped,
        failedCount: 0,
        localSongCount: database.search
            .searchSongs('', syncedOnly: true)
            .length,
        failureMessages: const [],
      );
    } finally {
      if (!preserveStaging) {
        await stagingDirectory
            .delete(recursive: true)
            .catchError((_) => stagingDirectory);
      }
    }
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
    _requireSuccessfulResponse(response.statusCode, text);
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
    _requireSuccessfulResponse(response.statusCode, text);
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
    final sink = targetFile.openWrite();
    try {
      await response.pipe(sink);
    } catch (_) {
      await targetFile.delete().catchError((_) => targetFile);
      rethrow;
    }
  }

  Uri _validatedDownloadUri(
    SyncQrPayload payload,
    String songId,
    String rawUrl,
  ) {
    final uri = Uri.tryParse(rawUrl);
    final expectedPath = '/songs/$songId/file';
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host != payload.host ||
        uri.port != payload.port ||
        uri.path != expectedPath ||
        uri.queryParameters['session_id'] != payload.sessionId ||
        uri.queryParameters['connect_code'] != payload.connectCode) {
      throw AppError('sync_download_url_invalid', '歌曲 $songId 的下载地址不安全或已过期');
    }
    return uri;
  }
}

class _PreparedSong {
  const _PreparedSong({
    required this.song,
    required this.item,
    required this.cache,
    required this.targetFile,
    required this.stagedFile,
  });

  final Song song;
  final PlaylistItem item;
  final SyncCacheEntry cache;
  final File targetFile;
  final File? stagedFile;
}

class _AppliedReplacement {
  const _AppliedReplacement({
    required this.targetFile,
    required this.backupFile,
  });

  final File targetFile;
  final File? backupFile;
}

Future<void> _replaceFile({
  required File stagedFile,
  required File targetFile,
  required Directory backupDirectory,
  required int backupIndex,
  required List<_AppliedReplacement> replacements,
}) async {
  await targetFile.parent.create(recursive: true);
  File? backupFile;
  if (await targetFile.exists()) {
    await backupDirectory.create(recursive: true);
    backupFile = File(p.join(backupDirectory.path, '$backupIndex.backup'));
    await targetFile.rename(backupFile.path);
  }

  replacements.add(
    _AppliedReplacement(targetFile: targetFile, backupFile: backupFile),
  );
  await stagedFile.rename(targetFile.path);
}

Future<void> _restoreReplacements(
  List<_AppliedReplacement> replacements,
) async {
  for (final replacement in replacements.reversed) {
    if (await replacement.targetFile.exists()) {
      await replacement.targetFile.delete();
    }
    final backupFile = replacement.backupFile;
    if (backupFile != null && await backupFile.exists()) {
      await backupFile.rename(replacement.targetFile.path);
    }
  }
}

void _requireSafeId(String value, String field) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
    throw AppError('sync_manifest_invalid', '同步清单中的 $field ID 不安全');
  }
}

void _requirePathWithin(String parentPath, String childPath) {
  final normalizedParent = p.normalize(p.absolute(parentPath));
  final normalizedChild = p.normalize(p.absolute(childPath));
  if (!p.isWithin(normalizedParent, normalizedChild)) {
    throw const AppError('sync_path_unsafe', '同步文件路径超出 APP 私有音乐目录');
  }
}

void _requireSuccessfulResponse(int statusCode, String responseBody) {
  if (statusCode < HttpStatus.ok || statusCode >= HttpStatus.multipleChoices) {
    throw AppError('sync_http_failed', '同步服务返回 $statusCode：$responseBody');
  }
}

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is int) {
    return value != 0;
  }
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}

Future<String> _fileHash(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
