import 'package:flutter_test/flutter_test.dart';
import 'package:windows_app/windows_audio_player.dart';

void main() {
  test('reports a ready playback backend', () async {
    final player = WindowsAudioPlayer(commandProbe: (_) async => true);

    final capability = await player.inspectCapability();

    expect(capability.canPlay, isTrue);
    expect(capability.canProbeDuration, isTrue);
    expect(capability.statusMessage, '播放组件已就绪');
    await player.dispose();
  });

  test(
    'keeps non-playback features available when ffplay is missing',
    () async {
      final player = WindowsAudioPlayer(
        commandProbe: (command) async => command == 'ffprobe',
      );

      final capability = await player.inspectCapability();

      expect(capability.canPlay, isFalse);
      expect(capability.canProbeDuration, isTrue);
      expect(capability.statusMessage, contains('导入、歌单和同步仍可使用'));
      await player.dispose();
    },
  );
}
