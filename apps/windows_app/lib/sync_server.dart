import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';

class WindowsSyncServer {
  WindowsSyncServer(this.database);

  final MusicDatabase database;

  HttpServer? _server;
  SyncSession? _session;

  SyncSession? get session => _session;

  bool get isRunning => _server != null && _session != null;

  Future<SyncSession> start() async {
    if (_server != null && _session != null) {
      return _session!;
    }

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final host = await _findLanHost();
    final session = SyncSession(
      sessionId: _randomToken(18),
      connectCode: _connectCode(),
      host: host,
      port: server.port,
      createdAt: DateTime.now().toUtc(),
    );

    _server = server;
    _session = session;
    server.listen(_handleRequest);
    return session;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _session = null;
    await server?.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      if (request.method == 'GET' && request.uri.path == '/health') {
        await _writeJson(request, {'ok': true});
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/connect') {
        await _handleConnect(request);
        return;
      }
      if (!_isAuthorized(request)) {
        await _writeJson(request, {
          'ok': false,
          'message': '连接码无效或同步模式已关闭',
        }, statusCode: HttpStatus.forbidden);
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/playlists') {
        await _writePlaylists(request);
        return;
      }
      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments.first == 'playlists' &&
          segments.last == 'manifest') {
        await _writePlaylistManifest(request, segments[1]);
        return;
      }
      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments.first == 'songs' &&
          segments.last == 'file') {
        await _writeSongFile(request, segments[1]);
        return;
      }
      await _writeJson(request, {
        'ok': false,
        'message': '接口不存在',
      }, statusCode: HttpStatus.notFound);
    } catch (_) {
      await _writeJson(request, {
        'ok': false,
        'message': '同步服务处理请求失败',
      }, statusCode: HttpStatus.internalServerError);
    }
  }

  Future<void> _handleConnect(HttpRequest request) async {
    try {
      const maximumBodyBytes = 16 * 1024;
      if (request.contentLength > maximumBodyBytes) {
        throw const FormatException('request body too large');
      }
      final bytes = BytesBuilder(copy: false);
      var receivedBytes = 0;
      await for (final chunk in request) {
        receivedBytes += chunk.length;
        if (receivedBytes > maximumBodyBytes) {
          throw const FormatException('request body too large');
        }
        bytes.add(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('request root is not an object');
      }

      final connect = SyncConnectRequest.fromJson(decoded);
      final ok =
          connect.sessionId == _session?.sessionId &&
          connect.connectCode == _session?.connectCode;
      await _writeJson(
        request,
        SyncConnectResponse(
          ok: ok,
          message: ok ? 'connected' : '连接码无效或同步模式已关闭',
        ).toJson(),
        statusCode: ok ? HttpStatus.ok : HttpStatus.forbidden,
      );
    } on Object {
      await _writeJson(
        request,
        const SyncConnectResponse(ok: false, message: '请求格式无效').toJson(),
        statusCode: HttpStatus.badRequest,
      );
    }
  }

  bool _isAuthorized(HttpRequest request) {
    final session = _session;
    if (session == null) {
      return false;
    }
    return request.uri.queryParameters['session_id'] == session.sessionId &&
        request.uri.queryParameters['connect_code'] == session.connectCode;
  }

  Future<void> _writePlaylists(HttpRequest request) async {
    final playlists = database.playlists.all();
    final entries = [
      for (final playlist in playlists)
        _playlistCatalogEntry(
          playlist,
          database.playlists.songsForPlaylist(playlist.id),
        ),
    ];
    await _writeJson(request, {
      'ok': true,
      'catalog_version': _hashJson(entries),
      'playlists': entries,
    });
  }

  Future<void> _writePlaylistManifest(
    HttpRequest request,
    String playlistId,
  ) async {
    final playlist = database.playlists.findById(playlistId);
    if (playlist == null) {
      await _writeJson(request, {
        'ok': false,
        'message': '歌单不存在',
      }, statusCode: HttpStatus.notFound);
      return;
    }

    final songs = database.playlists.songsForPlaylist(playlistId);
    await _writeJson(request, {
      'ok': true,
      'playlist_version': _playlistVersion(playlist, songs),
      'playlist': playlist.toMap(),
      'songs': [
        for (var index = 0; index < songs.length; index++)
          {
            ..._songJson(songs[index]),
            'sort_order': index,
            'download_url': _downloadUrl(songs[index].id),
          },
      ],
    });
  }

  Future<void> _writeSongFile(HttpRequest request, String songId) async {
    final song = database.songs.findById(songId);
    if (song == null) {
      await _writeJson(request, {
        'ok': false,
        'message': '歌曲不存在',
      }, statusCode: HttpStatus.notFound);
      return;
    }

    final file = File(song.localPath);
    if (!await file.exists()) {
      await _writeJson(request, {
        'ok': false,
        'message': '本地音频文件不存在',
      }, statusCode: HttpStatus.notFound);
      return;
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = _contentType(song.format);
    request.response.headers.set('X-Song-Id', song.id);
    request.response.headers.set('X-File-Hash', song.fileHash);
    request.response.headers.set(
      'content-disposition',
      'attachment; filename="${song.id}.${song.format.extension}"',
    );
    request.response.contentLength = await file.length();
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  String _downloadUrl(String songId) {
    final session = _session!;
    final encodedSongId = Uri.encodeComponent(songId);
    final query = Uri(
      queryParameters: {
        'session_id': session.sessionId,
        'connect_code': session.connectCode,
      },
    ).query;
    return 'http://${session.host}:${session.port}/songs/$encodedSongId/file?$query';
  }

  Map<String, Object?> _songJson(Song song) {
    return {
      'id': song.id,
      'title': song.title,
      'artist': song.artist,
      'album': song.album,
      'duration_ms': song.durationMs,
      'format': song.format.extension,
      'file_size': song.fileSize,
      'file_hash': song.fileHash,
      'original_file_name': song.originalFileName,
      'display_name_source': song.displayNameSource.value,
      'is_pending_review': song.isPendingReview,
    };
  }

  Map<String, Object?> _playlistCatalogEntry(
    Playlist playlist,
    List<Song> songs,
  ) {
    return {
      'id': playlist.id,
      'name': playlist.name,
      'sort_order': playlist.sortOrder,
      'song_count': songs.length,
      'version': _playlistVersion(playlist, songs),
    };
  }

  String _playlistVersion(Playlist playlist, List<Song> songs) {
    return _hashJson({
      'playlist': playlist.toMap(),
      'songs': [
        for (var index = 0; index < songs.length; index++)
          {
            'id': songs[index].id,
            'file_hash': songs[index].fileHash,
            'sort_order': index,
          },
      ],
    });
  }

  String _hashJson(Object value) {
    return sha256.convert(utf8.encode(jsonEncode(value))).toString();
  }

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, Object?> body, {
    int statusCode = HttpStatus.ok,
  }) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.headers.set('X-Content-Type-Options', 'nosniff');
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

Future<String> _findLanHost() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  final addresses = [
    for (final interface in interfaces)
      for (final address in interface.addresses) address.address,
  ];
  return selectPreferredLanHost(addresses) ??
      InternetAddress.loopbackIPv4.address;
}

String? selectPreferredLanHost(Iterable<String> addresses) {
  final usable = addresses.where(_isUsableIpv4).toList(growable: false);
  for (final address in usable) {
    if (_isPrivateLanAddress(address)) {
      return address;
    }
  }
  return usable.isEmpty ? null : usable.first;
}

bool _isUsableIpv4(String address) {
  final octets = _ipv4Octets(address);
  if (octets == null) {
    return false;
  }
  final first = octets[0];
  final second = octets[1];
  return first != 0 &&
      first != 127 &&
      !(first == 169 && second == 254) &&
      !(first == 198 && (second == 18 || second == 19)) &&
      first < 224;
}

bool _isPrivateLanAddress(String address) {
  final octets = _ipv4Octets(address);
  if (octets == null) {
    return false;
  }
  final first = octets[0];
  final second = octets[1];
  return first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

List<int>? _ipv4Octets(String address) {
  final octets = address.split('.');
  if (octets.length != 4) {
    return null;
  }
  final values = octets.map(int.tryParse).toList(growable: false);
  if (values.any((value) => value == null)) {
    return null;
  }
  final result = values.cast<int>();
  return result.any((value) => value < 0 || value > 255) ? null : result;
}

String _randomToken(int byteCount) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _connectCode() {
  final random = Random.secure();
  return List.generate(6, (_) => random.nextInt(10)).join();
}

ContentType _contentType(AudioFormat format) {
  return switch (format) {
    AudioFormat.mp3 => ContentType('audio', 'mpeg'),
    AudioFormat.flac => ContentType('audio', 'flac'),
    AudioFormat.m4a => ContentType('audio', 'mp4'),
    AudioFormat.wav => ContentType('audio', 'wav'),
  };
}
