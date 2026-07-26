import 'dart:convert';
import 'dart:io';

import 'package:android_app/android_library.dart';
import 'package:android_app/sync_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';
import 'package:path/path.dart' as p;

void main() {
  late HttpServer server;
  late Directory tempDir;
  late MusicDatabase database;
  late AndroidSyncClient client;
  late SyncQrPayload payload;
  late Map<String, List<int>> responseBytes;
  late List<Map<String, Object?>> Function() manifestSongs;
  late String manifestPlaylistName;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oneplus_android_sync_');
    database = MusicDatabase.memory();
    client = AndroidSyncClient();
    responseBytes = {
      'song-1': [1, 2, 3, 4, 5],
    };
    manifestPlaylistName = 'Daily';

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    payload = SyncQrPayload(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      sessionId: 'session-1',
      connectCode: '123456',
    );
    manifestSongs = () => [
      _manifestSong(
        payload: payload,
        id: 'song-1',
        expectedBytes: responseBytes['song-1']!,
      ),
    ];

    server.listen((request) async {
      if (request.method == 'POST' && request.uri.path == '/connect') {
        await _writeJson(request, {'ok': true, 'message': 'connected'});
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/playlists') {
        await _writeJson(request, {
          'ok': true,
          'playlists': [
            {
              'id': 'playlist-1',
              'name': manifestPlaylistName,
              'sort_order': 0,
              'song_count': manifestSongs().length,
            },
          ],
        });
        return;
      }
      if (request.method == 'GET' &&
          request.uri.path == '/playlists/playlist-1/manifest') {
        await _writeJson(request, {
          'ok': true,
          'playlist': _playlist(
            id: 'playlist-1',
            name: manifestPlaylistName,
          ).toMap(),
          'songs': manifestSongs(),
        });
        return;
      }
      if (request.method == 'GET' &&
          request.uri.pathSegments.length == 3 &&
          request.uri.pathSegments.first == 'songs' &&
          request.uri.pathSegments.last == 'file') {
        final songId = request.uri.pathSegments[1];
        final bytes = responseBytes[songId];
        if (bytes == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.add(bytes);
        }
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDown(() async {
    await client.dispose();
    database.close();
    await server.close(force: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('connects and atomically syncs a whole playlist', () async {
    final library = AndroidMusicLibraryLocation(rootPath: tempDir.path);
    await library.ensureReady();

    await client.connect(payload);
    final playlists = await client.fetchPlaylists(payload);
    expect(playlists, hasLength(1));

    final result = await client.syncPlaylist(
      payload: payload,
      remotePlaylist: playlists.single,
      database: database,
      library: library,
    );

    expect(result.downloadedCount, 1);
    expect(result.skippedCount, 0);
    expect(result.failedCount, 0);
    expect(result.localSongCount, 1);
    expect(result.failureMessages, isEmpty);
    expect(database.search.searchPlaylists('', syncedOnly: true), hasLength(1));
    expect(database.search.searchSongs('', syncedOnly: true), hasLength(1));
    expect(database.playlists.songsForPlaylist('playlist-1'), hasLength(1));
    expect(
      await File(p.join(library.audioPath, 'song-1.mp3')).readAsBytes(),
      responseBytes['song-1'],
    );
  });

  test('incomplete download keeps the previous playlist and cache', () async {
    final library = AndroidMusicLibraryLocation(rootPath: tempDir.path);
    await library.ensureReady();
    final oldFile = await _seedLocalPlaylist(
      database: database,
      library: library,
      playlistName: 'Before sync',
      songId: 'old-song',
      bytes: [7, 7, 7],
    );

    responseBytes = {
      'new-song': [8, 8],
    };
    manifestPlaylistName = 'After sync';
    manifestSongs = () => [
      _manifestSong(
        payload: payload,
        id: 'new-song',
        expectedBytes: [8, 8, 8, 8],
      ),
    ];

    await expectLater(
      _syncRemotePlaylist(
        client: client,
        payload: payload,
        database: database,
        library: library,
      ),
      throwsA(isA<AppError>()),
    );

    expect(database.playlists.findById('playlist-1')?.name, 'Before sync');
    expect(
      database.playlists.songsForPlaylist('playlist-1').single.id,
      'old-song',
    );
    expect(await oldFile.readAsBytes(), [7, 7, 7]);
    expect(
      await File(p.join(library.audioPath, 'new-song.mp3')).exists(),
      isFalse,
    );
  });

  test('hash mismatch does not replace a playable old cache file', () async {
    final library = AndroidMusicLibraryLocation(rootPath: tempDir.path);
    await library.ensureReady();
    final oldFile = await _seedLocalPlaylist(
      database: database,
      library: library,
      playlistName: 'Daily',
      songId: 'song-1',
      bytes: [1, 1, 1, 1],
    );
    final oldHash = database.songs.findById('song-1')!.fileHash;

    responseBytes = {
      'song-1': [9, 9, 9, 9],
    };
    manifestSongs = () => [
      _manifestSong(
        payload: payload,
        id: 'song-1',
        expectedBytes: [2, 2, 2, 2],
      ),
    ];

    await expectLater(
      _syncRemotePlaylist(
        client: client,
        payload: payload,
        database: database,
        library: library,
      ),
      throwsA(isA<AppError>()),
    );

    expect(await oldFile.readAsBytes(), [1, 1, 1, 1]);
    expect(database.songs.findById('song-1')?.fileHash, oldHash);
    expect(database.sync.findCacheForSong('song-1')?.fileHash, oldHash);
  });

  test('verified update replaces the old file and database together', () async {
    final library = AndroidMusicLibraryLocation(rootPath: tempDir.path);
    await library.ensureReady();
    final oldFile = await _seedLocalPlaylist(
      database: database,
      library: library,
      playlistName: 'Before sync',
      songId: 'song-1',
      bytes: [1, 1, 1],
    );

    final newBytes = [2, 2, 2, 2, 2];
    responseBytes = {'song-1': newBytes};
    manifestPlaylistName = 'After sync';
    manifestSongs = () => [
      _manifestSong(payload: payload, id: 'song-1', expectedBytes: newBytes),
    ];

    final result = await _syncRemotePlaylist(
      client: client,
      payload: payload,
      database: database,
      library: library,
    );

    final newHash = sha256.convert(newBytes).toString();
    expect(result.downloadedCount, 1);
    expect(await oldFile.readAsBytes(), newBytes);
    expect(database.playlists.findById('playlist-1')?.name, 'After sync');
    expect(database.songs.findById('song-1')?.fileHash, newHash);
    expect(database.sync.findCacheForSong('song-1')?.fileHash, newHash);
  });

  test('unsafe song id is rejected before any file is written', () async {
    final library = AndroidMusicLibraryLocation(rootPath: tempDir.path);
    await library.ensureReady();
    manifestSongs = () => [
      _manifestSong(
        payload: payload,
        id: '../escape',
        expectedBytes: [1, 2, 3],
      ),
    ];

    await expectLater(
      _syncRemotePlaylist(
        client: client,
        payload: payload,
        database: database,
        library: library,
      ),
      throwsA(isA<AppError>()),
    );

    expect(database.songs.all(), isEmpty);
    expect(
      await File(p.join(tempDir.parent.path, 'escape.mp3')).exists(),
      isFalse,
    );
  });
}

Future<PlaylistSyncResult> _syncRemotePlaylist({
  required AndroidSyncClient client,
  required SyncQrPayload payload,
  required MusicDatabase database,
  required AndroidMusicLibraryLocation library,
}) {
  return client.syncPlaylist(
    payload: payload,
    remotePlaylist: const RemotePlaylist(
      id: 'playlist-1',
      name: 'Remote',
      sortOrder: 0,
      songCount: 1,
    ),
    database: database,
    library: library,
  );
}

Map<String, Object?> _manifestSong({
  required SyncQrPayload payload,
  required String id,
  required List<int> expectedBytes,
}) {
  final query = Uri(
    queryParameters: {
      'session_id': payload.sessionId,
      'connect_code': payload.connectCode,
    },
  ).query;
  return {
    'id': id,
    'title': 'Song $id',
    'artist': 'Artist',
    'album': 'Album',
    'duration_ms': null,
    'format': 'mp3',
    'file_size': expectedBytes.length,
    'file_hash': sha256.convert(expectedBytes).toString(),
    'original_file_name': '$id.mp3',
    'display_name_source': 'filename',
    'is_pending_review': 0,
    'sort_order': 0,
    'download_url':
        'http://${payload.host}:${payload.port}/songs/$id/file?$query',
  };
}

Future<File> _seedLocalPlaylist({
  required MusicDatabase database,
  required AndroidMusicLibraryLocation library,
  required String playlistName,
  required String songId,
  required List<int> bytes,
}) async {
  final file = File(p.join(library.audioPath, '$songId.mp3'));
  await file.writeAsBytes(bytes);
  final song = _song(id: songId, localPath: file.path, bytes: bytes);
  final playlist = _playlist(id: 'playlist-1', name: playlistName);
  database.songs.upsert(song);
  database.playlists.upsert(playlist);
  database.playlists.addSong(
    item: PlaylistItem(
      id: 'item_${playlist.id}_$songId',
      playlistId: playlist.id,
      songId: songId,
      sortOrder: 0,
      createdAt: DateTime.utc(2026, 7, 8),
    ),
  );
  database.sync.upsertCacheEntry(
    SyncCacheEntry(
      id: 'cache_$songId',
      songId: songId,
      playlistId: playlist.id,
      localCachePath: file.path,
      fileHash: song.fileHash,
      status: SyncCacheStatus.synced,
      syncedAt: DateTime.utc(2026, 7, 8),
    ),
  );
  return file;
}

Song _song({
  required String id,
  required String localPath,
  required List<int> bytes,
}) {
  final now = DateTime.utc(2026, 7, 8);
  return Song(
    id: id,
    title: 'Song $id',
    artist: 'Artist',
    album: 'Album',
    format: AudioFormat.mp3,
    fileSize: bytes.length,
    fileHash: sha256.convert(bytes).toString(),
    localPath: localPath,
    originalFileName: '$id.mp3',
    displayNameSource: DisplayNameSource.filename,
    isPendingReview: false,
    createdAt: now,
    updatedAt: now,
  );
}

Playlist _playlist({required String id, required String name}) {
  final now = DateTime.utc(2026, 7, 8);
  return Playlist(
    id: id,
    name: name,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _writeJson(HttpRequest request, Map<String, Object?> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
