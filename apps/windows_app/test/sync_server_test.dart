import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:windows_app/sync_server.dart';

void main() {
  late MusicDatabase database;
  late Directory tempDir;
  late WindowsSyncServer server;

  setUp(() async {
    database = MusicDatabase.memory();
    tempDir = await Directory.systemTemp.createTemp('oneplus_music_sync_test_');
    server = WindowsSyncServer(database);
  });

  tearDown(() async {
    await server.stop();
    database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('serves playlists manifests and song files after connect', () async {
    final audioFile = File('${tempDir.path}${Platform.pathSeparator}song.mp3');
    await audioFile.writeAsBytes([1, 2, 3, 4]);

    final song = _song(localPath: audioFile.path);
    final playlist = _playlist();
    database.songs.upsert(song);
    database.playlists.upsert(playlist);
    database.playlists.addSong(
      item: PlaylistItem(
        id: 'item-1',
        playlistId: playlist.id,
        songId: song.id,
        sortOrder: 0,
        createdAt: DateTime.utc(2026, 7, 7),
      ),
    );

    final session = await server.start();
    final baseUrl = 'http://127.0.0.1:${session.port}';
    final authQuery =
        'session_id=${Uri.encodeQueryComponent(session.sessionId)}'
        '&connect_code=${Uri.encodeQueryComponent(session.connectCode)}';

    final connect = await _postJson('$baseUrl/connect', {
      'session_id': session.sessionId,
      'connect_code': session.connectCode,
    });
    expect(connect['ok'], isTrue);

    final playlists = await _getJson('$baseUrl/playlists?$authQuery');
    expect(playlists['ok'], isTrue);
    expect(playlists['playlists'], hasLength(1));

    final manifest = await _getJson(
      '$baseUrl/playlists/${playlist.id}/manifest?$authQuery',
    );
    expect(manifest['ok'], isTrue);
    expect(manifest['songs'], hasLength(1));
    expect((manifest['songs'] as List).single['local_path'], isNull);

    final downloaded = await _getBytes('$baseUrl/songs/${song.id}/file?$authQuery');
    expect(downloaded, [1, 2, 3, 4]);
  });
}

Future<Map<String, Object?>> _postJson(
  String url,
  Map<String, Object?> body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return jsonDecode(text) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _getJson(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return jsonDecode(text) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}

Future<List<int>> _getBytes(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    return await response.expand((chunk) => chunk).toList();
  } finally {
    client.close(force: true);
  }
}

Song _song({required String localPath}) {
  final now = DateTime.utc(2026, 7, 7);
  return Song(
    id: 'song-1',
    title: 'Song A',
    artist: 'Artist',
    album: 'Album',
    format: AudioFormat.mp3,
    fileSize: 4,
    fileHash: 'hash-song-1',
    localPath: localPath,
    originalFileName: 'song.mp3',
    displayNameSource: DisplayNameSource.filename,
    isPendingReview: false,
    createdAt: now,
    updatedAt: now,
  );
}

Playlist _playlist() {
  final now = DateTime.utc(2026, 7, 7);
  return Playlist(
    id: 'playlist-1',
    name: 'Daily',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
}
