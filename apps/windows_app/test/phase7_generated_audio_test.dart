import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:path/path.dart' as p;
import 'package:windows_app/audio_import_service.dart';

void main() {
  test('imports generated Phase 7 audio samples safely', () async {
    final projectRoot = Directory.current.parent.parent;
    final sampleDir = Directory(p.join(projectRoot.path, 'manual_test_audio'));
    if (!sampleDir.existsSync()) {
      markTestSkipped('manual_test_audio is not present');
      return;
    }

    final files = [
      'normal_artist - normal_title.mp3',
      '001.flac',
      'a8f39c2024.m4a',
      'random_code_839201.wav',
      'duplicate_source.mp3',
      'duplicate_copy.mp3',
    ].map((name) => p.join(sampleDir.path, name)).toList();

    for (final file in files) {
      expect(File(file).existsSync(), isTrue, reason: file);
    }

    final tempLibrary = await Directory.systemTemp.createTemp(
      'oneplus_phase7_import_',
    );
    final database = MusicDatabase.memory();
    addTearDown(database.close);
    addTearDown(() async {
      if (await tempLibrary.exists()) {
        await tempLibrary.delete(recursive: true);
      }
    });

    final service = AudioImportService(
      database,
      libraryOverride: MusicLibraryLocation(rootPath: tempLibrary.path),
    );

    final result = await service.importFiles(files);

    expect(result.importedCount, 5);
    expect(result.skippedFiles, hasLength(1));
    expect(result.skippedFiles.single.reason, '重复文件');
    expect(result.failedFiles, isEmpty);

    final songs = database.songs.all();
    expect(songs.map((song) => song.format).toSet(), {
      AudioFormat.mp3,
      AudioFormat.flac,
      AudioFormat.m4a,
      AudioFormat.wav,
    });
    expect(
      songs.where((song) => song.title == 'normal_title').single.artist,
      'normal_artist',
    );

    final pending = database.songs.pendingReview();
    expect(pending.map((song) => song.title), contains('未命名音频 001'));
    expect(pending.map((song) => song.title), contains('未命名音频 002'));
    expect(pending.map((song) => song.title), contains('未命名音频 003'));
    expect(result.pendingReviewCount, 3);

    for (final song in songs) {
      expect(File(song.localPath).existsSync(), isTrue);
      expect(
        song.localPath.startsWith(p.join(tempLibrary.path, 'audio')),
        isTrue,
      );
    }
  });

  test('imports generated Phase 7 audio folder safely', () async {
    final projectRoot = Directory.current.parent.parent;
    final sampleDir = Directory(p.join(projectRoot.path, 'manual_test_audio'));
    if (!sampleDir.existsSync()) {
      markTestSkipped('manual_test_audio is not present');
      return;
    }

    final tempLibrary = await Directory.systemTemp.createTemp(
      'oneplus_phase7_folder_import_',
    );
    final database = MusicDatabase.memory();
    addTearDown(database.close);
    addTearDown(() async {
      if (await tempLibrary.exists()) {
        await tempLibrary.delete(recursive: true);
      }
    });

    final service = AudioImportService(
      database,
      libraryOverride: MusicLibraryLocation(rootPath: tempLibrary.path),
    );

    final result = await service.importFolder(sampleDir.path);

    expect(result.importedCount, 5);
    expect(result.skippedFiles, hasLength(1));
    expect(result.failedFiles, isEmpty);
    expect(database.songs.all(), hasLength(5));
  });
}
