import 'dart:convert';
import 'dart:io';

import 'package:android_app/android_library.dart';
import 'package:android_app/sync_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';

void main() {
  late HttpServer server;
  late Directory tempDir;
  late MusicDatabase database;
  late AndroidSyncClient client;
  late SyncQrPayload payload;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oneplus_android_sync_');
    database = MusicDatabase.memory();
    client = AndroidSyncClient();

    final audioBytes = [1, 2, 3, 4, 5];
    final hash = sha256.convert(audioBytes).toString();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    payload = SyncQrPayload(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      sessionId: 'session-1',
      connectCode: '123456',
    );

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
              'name': 'Daily',
              'sort_order': 0,
              'song_count': 1,
            },
          ],
        });
        return;
      }
      if (request.method == 'GET' &&
          request.uri.path == '/playlists/playlist-1/manifest') {
        await _writeJson(request, {
          'ok': true,
          'playlist': {
            'id': 'playlist-1',
            'name': 'Daily',
            'sort_order': 0,
            'created_at': DateTime.utc(2026, 7, 8).toIso8601String(),
            'updated_at': DateTime.utc(2026, 7, 8).toIso8601String(),
          },
          'songs': [
            {
              'id': 'song-1',
              'title': 'Song A',
              'artist': 'Artist',
              'album': 'Album',
              'duration_ms': null,
              'format': 'mp3',
              'file_size': audioBytes.length,
              'file_hash': hash,
              'original_file_name': 'song-a.mp3',
              'display_name_source': 'filename',
              'is_pending_review': false,
              'sort_order': 0,
              'download_url':
                  'http://${payload.host}:${payload.port}/songs/song-1/file',
            },
          ],
        });
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/songs/song-1/file') {
        request.response.statusCode = HttpStatus.ok;
        request.response.add(audioBytes);
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

  test('connects and syncs a whole playlist into local storage', () async {
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
    expect(database.search.searchPlaylists('', syncedOnly: true), hasLength(1));
    expect(database.search.searchSongs('', syncedOnly: true), hasLength(1));
    expect(database.playlists.songsForPlaylist('playlist-1'), hasLength(1));
    expect(await File('${library.audioPath}${Platform.pathSeparator}song-1.mp3').exists(), isTrue);
  });
}

Future<void> _writeJson(
  HttpRequest request,
  Map<String, Object?> body,
) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
