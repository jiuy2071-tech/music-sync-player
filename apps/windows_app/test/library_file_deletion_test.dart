import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_core/music_core.dart';
import 'package:path/path.dart' as p;
import 'package:windows_app/audio_import_service.dart';

void main() {
  test('deletes only copies inside the managed library', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'yijia_library_delete_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final library = MusicLibraryLocation(rootPath: tempDirectory.path);
    await library.ensureReady();
    final managedFile = File(p.join(library.audioPath, 'song-1.mp3'));
    final outsideFile = File(p.join(tempDirectory.parent.path, 'outside.mp3'));
    await managedFile.writeAsBytes([1, 2, 3]);
    await outsideFile.writeAsBytes([4, 5, 6]);
    addTearDown(() async {
      if (await outsideFile.exists()) {
        await outsideFile.delete();
      }
    });

    final managedDeleted = await deleteManagedLibraryCopy(
      song: _song('song-1', managedFile.path),
      library: library,
    );
    final outsideDeleted = await deleteManagedLibraryCopy(
      song: _song('song-2', outsideFile.path),
      library: library,
    );

    expect(managedDeleted, isTrue);
    expect(await managedFile.exists(), isFalse);
    expect(outsideDeleted, isFalse);
    expect(await outsideFile.exists(), isTrue);
  });
}

Song _song(String id, String localPath) {
  final now = DateTime.utc(2026, 8, 15);
  return Song(
    id: id,
    title: id,
    artist: 'Artist',
    album: 'Album',
    format: AudioFormat.mp3,
    fileSize: 3,
    fileHash: 'hash-$id',
    localPath: localPath,
    originalFileName: '$id.mp3',
    displayNameSource: DisplayNameSource.filename,
    isPendingReview: false,
    createdAt: now,
    updatedAt: now,
  );
}
