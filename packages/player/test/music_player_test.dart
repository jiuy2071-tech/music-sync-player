import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/music_player.dart';

void main() {
  test('bounds playback position to a known duration', () {
    const beforeStart = PlaybackSnapshot(
      state: MusicPlaybackState.paused,
      position: Duration(seconds: -2),
      duration: Duration(minutes: 3),
    );
    const afterEnd = PlaybackSnapshot(
      state: MusicPlaybackState.playing,
      position: Duration(minutes: 4),
      duration: Duration(minutes: 3),
    );

    expect(beforeStart.boundedPosition, Duration.zero);
    expect(afterEnd.boundedPosition, const Duration(minutes: 3));
    expect(afterEnd.isPlaying, isTrue);
    expect(afterEnd.hasTrack, isFalse);
  });
}
