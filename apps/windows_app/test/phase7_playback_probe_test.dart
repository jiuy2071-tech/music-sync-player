import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_core/music_core.dart';
import 'package:path/path.dart' as p;
import 'package:windows_app/windows_audio_player.dart';

void main() {
  test('plays generated Phase 7 samples through Windows player', () async {
    final projectRoot = Directory.current.parent.parent;
    final sampleDir = Directory(p.join(projectRoot.path, 'manual_test_audio'));
    if (!sampleDir.existsSync()) {
      markTestSkipped('manual_test_audio is not present');
      return;
    }

    final player = WindowsAudioPlayer();
    addTearDown(player.stop);

    for (final entry in [
      (AudioFormat.mp3, 'normal_artist - normal_title.mp3'),
      (AudioFormat.flac, '001.flac'),
      (AudioFormat.m4a, 'a8f39c2024.m4a'),
      (AudioFormat.wav, 'random_code_839201.wav'),
    ]) {
      final file = File(p.join(sampleDir.path, entry.$2));
      expect(file.existsSync(), isTrue);
      final stat = await file.stat();
      final song = Song(
        id: 'probe_${entry.$1.extension}',
        title: entry.$2,
        artist: 'test',
        album: 'test',
        format: entry.$1,
        fileSize: stat.size,
        fileHash: 'probe-${entry.$1.extension}',
        localPath: file.path,
        originalFileName: entry.$2,
        displayNameSource: DisplayNameSource.filename,
        isPendingReview: false,
        createdAt: DateTime.utc(2026, 7, 8),
        updatedAt: DateTime.utc(2026, 7, 8),
      );

      await player.play(song);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      player.stop();
    }
  });
}
