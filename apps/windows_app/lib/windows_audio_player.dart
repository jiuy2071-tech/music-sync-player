import 'dart:io';

import 'package:music_core/music_core.dart';

class WindowsAudioPlayer {
  WindowsAudioPlayer();

  Process? _process;
  Song? _currentSong;
  bool _paused = false;

  Song? get currentSong => _currentSong;

  Future<void> play(Song song) async {
    await stop();
    final file = File(song.localPath);
    if (!await file.exists()) {
      throw AppError('audio_file_missing', '本地音频文件不存在：${song.localPath}');
    }

    try {
      _process = await Process.start('ffplay', [
        '-nodisp',
        '-autoexit',
        '-loglevel',
        'quiet',
        song.localPath,
      ]);
    } on ProcessException catch (error) {
      throw AppError(
        'audio_player_unavailable',
        '本地播放需要 ffplay。当前环境未能启动 ffplay。',
        cause: error,
      );
    }

    _paused = false;
    _currentSong = song;
  }

  Future<void> pause() async {
    if (_process == null || _paused) {
      return;
    }
    _process!.stdin.write('p');
    _paused = true;
  }

  Future<void> resume() async {
    if (_process == null || !_paused) {
      return;
    }
    _process!.stdin.write('p');
    _paused = false;
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    _currentSong = null;
    _paused = false;
    if (process == null) {
      return;
    }
    process.kill();
    await process.exitCode;
  }

  Future<void> dispose() => stop();
}
