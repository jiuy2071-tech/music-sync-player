import 'package:music_core/music_core.dart';

enum MusicPlaybackState { idle, playing, paused, completed, failed }

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.state,
    this.song,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.errorMessage,
  });

  final MusicPlaybackState state;
  final Song? song;
  final Duration position;
  final Duration duration;
  final String? errorMessage;

  bool get hasTrack => song != null;
  bool get isPlaying => state == MusicPlaybackState.playing;

  Duration get boundedPosition {
    if (position < Duration.zero) {
      return Duration.zero;
    }
    if (duration > Duration.zero && position > duration) {
      return duration;
    }
    return position;
  }
}

/// Shared contract for future player adapters.
///
/// V1 keeps the Windows and Android implementations platform-specific, while
/// this interface records the behavior expected if they are unified later.
abstract interface class MusicPlayer {
  Stream<PlaybackSnapshot> get snapshots;

  PlaybackSnapshot get current;

  Future<void> play(Song song, {Duration startAt = Duration.zero});

  Future<void> pause();

  Future<void> resume();

  Future<void> seek(Duration position);

  Future<void> stop();

  Future<void> dispose();
}
