import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:music_core/music_core.dart';

class AndroidAudioPlayer {
  AndroidAudioPlayer();

  final AudioPlayer _player = AudioPlayer();
  Song? _currentSong;

  Song? get currentSong => _currentSong;
  Stream<Duration> get positionStream => _player.onPositionChanged;
  Stream<Duration> get durationStream => _player.onDurationChanged;
  Stream<void> get completeStream => _player.onPlayerComplete;
  Stream<bool> get playingStream =>
      _player.onPlayerStateChanged.map((state) => state == PlayerState.playing);

  /// Surfaces playback failures that happen after a track starts, since
  /// audioplayers reports them through its log stream rather than as errors
  /// on the play() future.
  Stream<String> get errorStream => _player.eventStream
      .where(
        (event) =>
            event.eventType == AudioEventType.log &&
            event.logMessage != null &&
            _looksLikePlaybackError(event.logMessage!),
      )
      .map((event) => event.logMessage!);

  Future<void> play(Song song) async {
    final file = File(song.localPath);
    if (!await file.exists()) {
      throw AppError('audio_file_missing', '本地音频文件不存在：${song.localPath}');
    }
    await _player.stop();
    await _player.play(DeviceFileSource(song.localPath));
    _currentSong = song;
  }

  Future<void> pause() => _player.pause();

  Future<void> resume() => _player.resume();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<Duration?> getDuration() => _player.getDuration();

  Future<void> stop() async {
    await _player.stop();
    _currentSong = null;
  }

  Future<void> dispose() => _player.dispose();
}

bool _looksLikePlaybackError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('error') ||
      lower.contains('fail') ||
      lower.contains('exception');
}
