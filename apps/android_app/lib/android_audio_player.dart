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

  Future<void> play(Song song) async {
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
