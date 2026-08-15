import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';
import 'package:path/path.dart' as p;

import 'android_library.dart';

typedef AvailableBytesProvider = Future<int> Function(String path);

class RemotePlaylist {
  const RemotePlaylist({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.songCount,
    required this.version,
  });

  factory RemotePlaylist.fromJson(Map<String, Object?> json) {
    return RemotePlaylist(
      id: json['id']! as String,
      name: json['name']! as String,
      sortOrder: json['sort_order']! as int,
      songCount: json['song_count']! as int,
      version: json['version']! as String,
    );
  }

  final String id;
  final String name;
  final int sortOrder;
  final int songCount;
  final String version;
}

class RemotePlaylistCatalog {
  const RemotePlaylistCatalog({required this.version, required this.playlists});

  final String version;
  final List<RemotePlaylist> playlists;
}

class CatalogReconcileResult {
  const CatalogReconcileResult({
    required this.removedPlaylistCount,
    required this.removedSongCount,
    required this.cleanupFailureMessages,
  });

  final int removedPlaylistCount;
  final int removedSongCount;
  final List<String> cleanupFailureMessages;
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

class SyncRecoveryResult {
  const SyncRecoveryResult({
    required this.restoredOperationCount,
    required this.completedOperationCount,
    required this.failureMessages,
  });

  final int restoredOperationCount;
  final int completedOperationCount;
  final List<String> failureMessages;
}

class AndroidSyncClient {
  AndroidSyncClient({
    HttpClient? httpClient,
    AvailableBytesProvider? availableBytesProvider,
    Duration networkTimeout = const Duration(seconds: 20),
    int maxNetworkAttempts = 3,
  }) : assert(maxNetworkAttempts > 0),
       _httpClient = httpClient ?? HttpClient(),
       _availableBytesProvider =
           availableBytesProvider ?? _androidAvailableBytes,
       _networkTimeout = networkTimeout,
       _maxNetworkAttempts = maxNetworkAttempts {
    _httpClient.connectionTimeout = networkTimeout;
  }

  final HttpClient _httpClient;
  final AvailableBytesProvider _availableBytesProvider;
  final Duration _networkTimeout;
  final int _maxNetworkAttempts;

  static Future<SyncRecoveryResult> recoverInterruptedSyncs({
    required MusicDatabase database,
    required AndroidMusicLibraryLocation library,
  }) async {
    await _cleanupStaleTrash(library);
    final stagingRoot = Directory(p.join(library.rootPath, '.sync_staging'));
    if (!await stagingRoot.exists()) {
      for (final operationId in database.sync.committedOperationIds()) {
        database.sync.removeCommittedOperation(operationId);
      }
      return const SyncRecoveryResult(
        restoredOperationCount: 0,
        completedOperationCount: 0,
        failureMessages: [],
      );
    }

    var restoredCount = 0;
    var completedCount = 0;
    final failures = <String>[];
    final foundOperationIds = <String>{};
    await for (final entity in stagingRoot.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final operationId = p.basename(entity.path);
      foundOperationIds.add(operationId);
      try {
        _requireSafeOperationId(operationId);
        final journalFile = File(p.join(entity.path, 'journal.json'));
        if (!await journalFile.exists()) {
          await entity.delete(recursive: true);
          database.sync.removeCommittedOperation(operationId);
          continue;
        }

        final journal = _SyncJournal.fromJson(
          jsonDecode(await journalFile.readAsString()) as Map<String, Object?>,
        );
        if (journal.operationId != operationId) {
          throw const FormatException('同步恢复记录与临时目录不一致');
        }

        if (database.sync.isOperationCommitted(operationId)) {
          await entity.delete(recursive: true);
          database.sync.removeCommittedOperation(operationId);
          completedCount++;
          continue;
        }

        for (final entry in journal.replacements.reversed) {
          _requireSafeAudioFileName(entry.targetName);
          _requireSafeBackupName(entry.backupName);
          final targetFile = File(p.join(library.audioPath, entry.targetName));
          final backupFile = File(
            p.join(entity.path, 'backups', entry.backupName),
          );
          _requirePathWithin(library.audioPath, targetFile.path);
          _requirePathWithin(entity.path, backupFile.path);

          if (await backupFile.exists()) {
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            await targetFile.parent.create(recursive: true);
            await backupFile.rename(targetFile.path);
          } else if (!entry.hadOriginal && await targetFile.exists()) {
            await targetFile.delete();
          }
        }
        await entity.delete(recursive: true);
        database.sync.removeCommittedOperation(operationId);
        restoredCount++;
      } catch (error) {
        failures.add('$operationId：$error');
      }
    }

    for (final operationId in database.sync.committedOperationIds()) {
      if (!foundOperationIds.contains(operationId)) {
        database.sync.removeCommittedOperation(operationId);
      }
    }
    if (await stagingRoot.exists() && await stagingRoot.list().isEmpty) {
      await stagingRoot.delete();
    }
    return SyncRecoveryResult(
      restoredOperationCount: restoredCount,
      completedOperationCount: completedCount,
      failureMessages: failures,
    );
  }

  static Future<void> _cleanupStaleTrash(
    AndroidMusicLibraryLocation library,
  ) async {
    // Files in .sync_trash are either already unlinked from the database or
    // will simply be re-downloaded on the next sync, so dropping them during
    // startup recovery is always safe.
    final trashDirectory = Directory(p.join(library.rootPath, '.sync_trash'));
    try {
      if (await trashDirectory.exists()) {
        await trashDirectory.delete(recursive: true);
      }
    } catch (_) {
      // Best effort: a stale trash file only consumes space.
    }
  }

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

  Future<RemotePlaylistCatalog> fetchPlaylistCatalog(
    SyncQrPayload payload,
  ) async {
    final response = await _getJson(_uri(payload, '/playlists', auth: true));
    if (response['ok'] != true) {
      throw AppError(
        'sync_playlists_failed',
        response['message']?.toString() ?? '获取电脑端歌单失败',
      );
    }
    final playlists = response['playlists']! as List;
    return RemotePlaylistCatalog(
      version: response['catalog_version']! as String,
      playlists: playlists
          .cast<Map<String, Object?>>()
          .map(RemotePlaylist.fromJson)
          .toList(),
    );
  }

  Future<List<RemotePlaylist>> fetchPlaylists(SyncQrPayload payload) async {
    return (await fetchPlaylistCatalog(payload)).playlists;
  }

  Future<CatalogReconcileResult> reconcileAuthoritativeCatalog({
    required RemotePlaylistCatalog catalog,
    required MusicDatabase database,
    required AndroidMusicLibraryLocation library,
  }) async {
    _requireVersion(catalog.version, 'catalog');
    final remoteIds = <String>{};
    for (final playlist in catalog.playlists) {
      _requireSafeId(playlist.id, 'playlist');
      _requireVersion(playlist.version, 'playlist');
      remoteIds.add(playlist.id);
    }
    final removedPlaylistIds = database.sync.syncedPlaylistIds()
      ..removeWhere(remoteIds.contains);
    if (removedPlaylistIds.isNotEmpty) {
      await database.transaction<void>(() async {
        for (final playlistId in removedPlaylistIds) {
          database.playlists.deletePlaylist(playlistId);
        }
      });
    }
    final cleanup = await _cleanupOrphanedSongs(database, library);
    return CatalogReconcileResult(
      removedPlaylistCount: removedPlaylistIds.length,
      removedSongCount: cleanup.removedCount,
      cleanupFailureMessages: cleanup.failureMessages,
    );
  }

  Future<PlaylistSyncResult> syncPlaylist({
    required SyncQrPayload payload,
    required RemotePlaylist remotePlaylist,
    required MusicDatabase database,
    required AndroidMusicLibraryLocation library,
  }) async {
    _requireSafeId(remotePlaylist.id, 'playlist');
    _requireVersion(remotePlaylist.version, 'playlist');
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
    final playlistVersion = manifest['playlist_version']! as String;
    _requireVersion(playlistVersion, 'playlist');
    if (playlistVersion != remotePlaylist.version) {
      throw const AppError('sync_manifest_stale', '电脑端歌单在同步期间发生变化，请刷新后重试');
    }

    final songJsonList = (manifest['songs']! as List)
        .cast<Map<String, Object?>>();
    final songIds = <String>{};
    final operationId =
        '${playlist.id}_${DateTime.now().microsecondsSinceEpoch}';
    final stagingDirectory = Directory(
      p.join(library.rootPath, '.sync_staging', operationId),
    );

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

        Uri? downloadUri;
        if (canReuse) {
          skipped++;
        } else {
          downloadUri = _validatedDownloadUri(
            payload,
            songId,
            songJson['download_url']! as String,
          );
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
            downloadUri: downloadUri,
            expectedSize: expectedSize,
            expectedHash: expectedHash,
          ),
        );
      }

      final bytesToDownload = preparedSongs
          .where((prepared) => prepared.downloadUri != null)
          .fold<int>(0, (total, prepared) => total + prepared.expectedSize);
      await _ensureAvailableStorage(
        libraryPath: library.rootPath,
        bytesToDownload: bytesToDownload,
      );

      await stagingDirectory.create(recursive: true);
      for (var index = 0; index < preparedSongs.length; index++) {
        final prepared = preparedSongs[index];
        final downloadUri = prepared.downloadUri;
        if (downloadUri == null) {
          continue;
        }
        final stagedFile = File(
          p.join(
            stagingDirectory.path,
            'downloads',
            '$index.${prepared.song.format.extension}',
          ),
        );
        prepared.stagedFile = stagedFile;
        await _downloadFile(
          downloadUri,
          stagedFile,
          expectedSize: prepared.expectedSize,
        );
        final actualSize = await stagedFile.length();
        if (actualSize != prepared.expectedSize) {
          throw AppError('sync_size_mismatch', '歌曲 ${prepared.song.id} 下载不完整');
        }
        final actualHash = await _fileHash(stagedFile);
        if (actualHash != prepared.expectedHash) {
          throw AppError(
            'sync_hash_mismatch',
            '歌曲 ${prepared.song.id} 下载文件校验失败',
          );
        }
      }

      final replacementPlans = <_ReplacementPlan>[];
      for (var index = 0; index < preparedSongs.length; index++) {
        final prepared = preparedSongs[index];
        final stagedFile = prepared.stagedFile;
        if (stagedFile == null) {
          continue;
        }
        final targetName = p.basename(prepared.targetFile.path);
        _requireSafeAudioFileName(targetName);
        replacementPlans.add(
          _ReplacementPlan(
            stagedFile: stagedFile,
            targetFile: prepared.targetFile,
            backupFile: File(
              p.join(stagingDirectory.path, 'backups', '$index.backup'),
            ),
            hadOriginal: await prepared.targetFile.exists(),
          ),
        );
      }
      final journal = _SyncJournal(
        operationId: operationId,
        replacements: replacementPlans
            .map(
              (plan) => _SyncJournalEntry(
                targetName: p.basename(plan.targetFile.path),
                backupName: p.basename(plan.backupFile.path),
                hadOriginal: plan.hadOriginal,
              ),
            )
            .toList(),
      );
      await File(
        p.join(stagingDirectory.path, 'journal.json'),
      ).writeAsString(jsonEncode(journal.toJson()), flush: true);

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
          database.sync.upsertPlaylistSnapshot(
            playlistId: playlist.id,
            sourceVersion: playlistVersion,
            syncedAt: DateTime.now().toUtc(),
          );
          for (final plan in replacementPlans) {
            await _replaceFile(plan: plan, replacements: replacements);
          }
          database.sync.markOperationCommitted(
            operationId,
            DateTime.now().toUtc(),
          );
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

      try {
        await stagingDirectory.delete(recursive: true);
        database.sync.removeCommittedOperation(operationId);
      } catch (_) {
        preserveStaging = true;
      }

      final cleanup = await _cleanupOrphanedSongs(database, library);
      return PlaylistSyncResult(
        downloadedCount: preparedSongs
            .where((prepared) => prepared.downloadUri != null)
            .length,
        skippedCount: skipped,
        failedCount: cleanup.failureMessages.length,
        localSongCount: database.search
            .searchSongs('', syncedOnly: true)
            .length,
        failureMessages: cleanup.failureMessages,
      );
    } finally {
      if (!preserveStaging) {
        await stagingDirectory
            .delete(recursive: true)
            .catchError((_) => stagingDirectory);
      }
    }
  }

  Future<void> _ensureAvailableStorage({
    required String libraryPath,
    required int bytesToDownload,
  }) async {
    if (bytesToDownload == 0) {
      return;
    }
    const minimumHeadroom = 16 * 1024 * 1024;
    final requiredBytes = bytesToDownload + minimumHeadroom;
    final availableBytes = await _availableBytesProvider(libraryPath);
    if (availableBytes < requiredBytes) {
      throw AppError(
        'sync_insufficient_storage',
        '手机空间不足，需要至少 ${_formatMegabytes(requiredBytes)}，'
            '当前可用 ${_formatMegabytes(availableBytes)}',
      );
    }
  }

  Future<_OrphanCleanupResult> _cleanupOrphanedSongs(
    MusicDatabase database,
    AndroidMusicLibraryLocation library,
  ) async {
    final orphanedSongs = database.sync.unreferencedSyncedSongs();
    if (orphanedSongs.isEmpty) {
      return const _OrphanCleanupResult(removedCount: 0, failureMessages: []);
    }

    final trashDirectory = Directory(p.join(library.rootPath, '.sync_trash'));
    var removedCount = 0;
    final failures = <String>[];
    for (var index = 0; index < orphanedSongs.length; index++) {
      final song = orphanedSongs[index];
      final sourceFile = File(song.localPath);
      if (!_isPathWithin(library.audioPath, sourceFile.path)) {
        database.sync.markDeleted(song.id, DateTime.now().toUtc());
        failures.add('${song.title}：缓存路径不安全，未删除磁盘文件');
        continue;
      }

      File? trashFile;
      try {
        if (await sourceFile.exists()) {
          await trashDirectory.create(recursive: true);
          trashFile = File(
            p.join(
              trashDirectory.path,
              '${DateTime.now().microsecondsSinceEpoch}_$index.trash',
            ),
          );
          await sourceFile.rename(trashFile.path);
        }
        try {
          await database.transaction<void>(() async {
            database.songs.deleteById(song.id);
          });
        } catch (_) {
          if (trashFile != null && await trashFile.exists()) {
            await trashFile.rename(sourceFile.path);
          }
          rethrow;
        }
        if (trashFile != null && await trashFile.exists()) {
          await trashFile.delete();
        }
        removedCount++;
      } catch (error) {
        failures.add('${song.title}：$error');
      }
    }
    if (await trashDirectory.exists() && await trashDirectory.list().isEmpty) {
      await trashDirectory.delete();
    }
    return _OrphanCleanupResult(
      removedCount: removedCount,
      failureMessages: failures,
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
    return _withNetworkRetry(() async {
      final request = await _httpClient.getUrl(uri).timeout(_networkTimeout);
      final response = await request.close().timeout(_networkTimeout);
      final text = await _readResponseText(response);
      _requireSuccessfulResponse(response.statusCode, text);
      return _decodeJsonObject(text);
    });
  }

  Future<Map<String, Object?>> _postJson(
    Uri uri,
    Map<String, Object?> body,
  ) async {
    return _withNetworkRetry(() async {
      final request = await _httpClient.postUrl(uri).timeout(_networkTimeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(_networkTimeout);
      final text = await _readResponseText(response);
      _requireSuccessfulResponse(response.statusCode, text);
      return _decodeJsonObject(text);
    });
  }

  Future<void> _downloadFile(
    Uri uri,
    File targetFile, {
    required int expectedSize,
  }) async {
    await targetFile.parent.create(recursive: true);
    await _withNetworkRetry(() async {
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      final request = await _httpClient.getUrl(uri).timeout(_networkTimeout);
      final response = await request.close().timeout(_networkTimeout);
      if (response.statusCode != HttpStatus.ok) {
        final message = await _readResponseText(
          response,
          maximumBytes: 64 * 1024,
        );
        if (_isTransientStatusCode(response.statusCode)) {
          throw _TransientSyncException(
            '同步服务暂时不可用（${response.statusCode}）：$message',
          );
        }
        throw AppError('sync_download_failed', message);
      }
      final declaredLength = response.contentLength;
      if (declaredLength > expectedSize) {
        throw const AppError('sync_size_mismatch', '下载文件超过同步清单声明的大小');
      }
      final sink = targetFile.openWrite();
      var receivedBytes = 0;
      try {
        await for (final chunk in response.timeout(_networkTimeout)) {
          receivedBytes += chunk.length;
          if (receivedBytes > expectedSize) {
            throw const AppError('sync_size_mismatch', '下载文件超过同步清单声明的大小');
          }
          sink.add(chunk);
        }
        await sink.flush();
      } catch (error, stackTrace) {
        await sink.close();
        await targetFile.delete().catchError((_) => targetFile);
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        await sink.close();
      }
      if (receivedBytes != expectedSize) {
        await targetFile.delete().catchError((_) => targetFile);
        throw const AppError('sync_size_mismatch', '下载文件大小与同步清单不一致');
      }
    });
  }

  Future<String> _readResponseText(
    HttpClientResponse response, {
    int maximumBytes = 2 * 1024 * 1024,
  }) async {
    final bytes = BytesBuilder(copy: false);
    var receivedBytes = 0;
    await for (final chunk in response.timeout(_networkTimeout)) {
      receivedBytes += chunk.length;
      if (receivedBytes > maximumBytes) {
        throw const AppError('sync_response_too_large', '同步服务返回的数据过大');
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }

  Future<T> _withNetworkRetry<T>(Future<T> Function() action) async {
    for (var attempt = 1; attempt <= _maxNetworkAttempts; attempt++) {
      try {
        return await action();
      } catch (error) {
        final shouldRetry =
            attempt < _maxNetworkAttempts && _isRetryableNetworkError(error);
        if (!shouldRetry) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
    throw StateError('Unreachable network retry state');
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
  _PreparedSong({
    required this.song,
    required this.item,
    required this.cache,
    required this.targetFile,
    required this.downloadUri,
    required this.expectedSize,
    required this.expectedHash,
  });

  final Song song;
  final PlaylistItem item;
  final SyncCacheEntry cache;
  final File targetFile;
  final Uri? downloadUri;
  final int expectedSize;
  final String expectedHash;
  File? stagedFile;
}

class _AppliedReplacement {
  const _AppliedReplacement({
    required this.targetFile,
    required this.backupFile,
  });

  final File targetFile;
  final File? backupFile;
}

class _ReplacementPlan {
  const _ReplacementPlan({
    required this.stagedFile,
    required this.targetFile,
    required this.backupFile,
    required this.hadOriginal,
  });

  final File stagedFile;
  final File targetFile;
  final File backupFile;
  final bool hadOriginal;
}

class _SyncJournal {
  const _SyncJournal({required this.operationId, required this.replacements});

  factory _SyncJournal.fromJson(Map<String, Object?> json) {
    final operationId = json['operation_id'];
    final replacements = json['replacements'];
    if (operationId is! String || replacements is! List) {
      throw const FormatException('同步恢复记录格式无效');
    }
    return _SyncJournal(
      operationId: operationId,
      replacements: replacements
          .map(
            (entry) => _SyncJournalEntry.fromJson(
              (entry as Map).cast<String, Object?>(),
            ),
          )
          .toList(),
    );
  }

  final String operationId;
  final List<_SyncJournalEntry> replacements;

  Map<String, Object?> toJson() => {
    'operation_id': operationId,
    'replacements': replacements.map((entry) => entry.toJson()).toList(),
  };
}

class _SyncJournalEntry {
  const _SyncJournalEntry({
    required this.targetName,
    required this.backupName,
    required this.hadOriginal,
  });

  factory _SyncJournalEntry.fromJson(Map<String, Object?> json) {
    final targetName = json['target_name'];
    final backupName = json['backup_name'];
    final hadOriginal = json['had_original'];
    if (targetName is! String ||
        backupName is! String ||
        hadOriginal is! bool) {
      throw const FormatException('同步恢复文件记录格式无效');
    }
    return _SyncJournalEntry(
      targetName: targetName,
      backupName: backupName,
      hadOriginal: hadOriginal,
    );
  }

  final String targetName;
  final String backupName;
  final bool hadOriginal;

  Map<String, Object?> toJson() => {
    'target_name': targetName,
    'backup_name': backupName,
    'had_original': hadOriginal,
  };
}

class _OrphanCleanupResult {
  const _OrphanCleanupResult({
    required this.removedCount,
    required this.failureMessages,
  });

  final int removedCount;
  final List<String> failureMessages;
}

Future<void> _replaceFile({
  required _ReplacementPlan plan,
  required List<_AppliedReplacement> replacements,
}) async {
  await plan.targetFile.parent.create(recursive: true);
  File? backupFile;
  final targetExists = await plan.targetFile.exists();
  if (targetExists != plan.hadOriginal) {
    throw const AppError('sync_local_file_changed', '本地缓存文件在同步期间发生变化，请重试');
  }
  if (targetExists) {
    await plan.backupFile.parent.create(recursive: true);
    backupFile = plan.backupFile;
    await plan.targetFile.rename(backupFile.path);
  }

  replacements.add(
    _AppliedReplacement(targetFile: plan.targetFile, backupFile: backupFile),
  );
  await plan.stagedFile.rename(plan.targetFile.path);
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

void _requireSafeOperationId(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,180}$').hasMatch(value)) {
    throw const FormatException('同步临时目录名称无效');
  }
}

void _requireSafeAudioFileName(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}\.(mp3|flac|m4a|wav)$').hasMatch(value)) {
    throw const FormatException('同步恢复目标文件名无效');
  }
}

void _requireSafeBackupName(String value) {
  if (!RegExp(r'^\d+\.backup$').hasMatch(value)) {
    throw const FormatException('同步恢复备份文件名无效');
  }
}

void _requireVersion(String value, String field) {
  if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value)) {
    throw AppError('sync_manifest_invalid', '同步清单中的 $field 版本无效');
  }
}

void _requirePathWithin(String parentPath, String childPath) {
  if (!_isPathWithin(parentPath, childPath)) {
    throw const AppError('sync_path_unsafe', '同步文件路径超出 APP 私有音乐目录');
  }
}

bool _isPathWithin(String parentPath, String childPath) {
  final normalizedParent = p.normalize(p.absolute(parentPath));
  final normalizedChild = p.normalize(p.absolute(childPath));
  return p.isWithin(normalizedParent, normalizedChild);
}

void _requireSuccessfulResponse(int statusCode, String responseBody) {
  if (statusCode < HttpStatus.ok || statusCode >= HttpStatus.multipleChoices) {
    if (_isTransientStatusCode(statusCode)) {
      throw _TransientSyncException('同步服务暂时不可用（$statusCode）：$responseBody');
    }
    throw AppError('sync_http_failed', '同步服务返回 $statusCode：$responseBody');
  }
}

Map<String, Object?> _decodeJsonObject(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('JSON root is not an object');
    }
    return decoded;
  } on FormatException catch (error) {
    throw AppError('sync_response_invalid', '同步服务返回的数据格式无效', cause: error);
  }
}

bool _isTransientStatusCode(int statusCode) {
  return statusCode == HttpStatus.requestTimeout ||
      statusCode == HttpStatus.tooManyRequests ||
      statusCode >= HttpStatus.internalServerError;
}

bool _isRetryableNetworkError(Object error) {
  return error is SocketException ||
      error is HttpException ||
      error is TimeoutException ||
      error is _TransientSyncException;
}

class _TransientSyncException implements Exception {
  const _TransientSyncException(this.message);

  final String message;

  @override
  String toString() => message;
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

Future<int> _androidAvailableBytes(String path) async {
  const channel = MethodChannel('music_sync_player/storage');
  final bytes = await channel.invokeMethod<int>('getAvailableBytes', {
    'path': path,
  });
  if (bytes == null || bytes < 0) {
    throw const AppError('sync_storage_check_failed', '无法读取手机剩余空间');
  }
  return bytes;
}

String _formatMegabytes(int bytes) {
  final megabytes = bytes / (1024 * 1024);
  return '${megabytes.toStringAsFixed(megabytes < 10 ? 1 : 0)} MB';
}
