import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:path/path.dart' as p;
import 'package:windows_app/audio_import_service.dart';

void main() {
  late Directory tempDir;
  late MusicDatabase database;
  late AudioImportService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oneplus_id3_test_');
    database = MusicDatabase.memory();
    service = AudioImportService(
      database,
      libraryOverride: MusicLibraryLocation(rootPath: tempDir.path),
    );
  });

  tearDown(() async {
    database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeMp3(String name, List<int> bytes) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }

  test('reads ID3v2.3 UTF-16 tags with a byte order mark', () async {
    final file = await writeMp3(
      'utf16.mp3',
      _v23Tag([
        _textFrameV23('TIT2', 1, _utf16LeBytes('测试歌曲')),
        _textFrameV23('TPE1', 1, _utf16LeBytes('歌手甲')),
        _textFrameV23('TALB', 1, _utf16LeBytes('专辑乙')),
      ]),
    );

    final result = await service.importFiles([file.path]);

    expect(result.importedCount, 1);
    final song = database.songs.all().single;
    expect(song.title, '测试歌曲');
    expect(song.artist, '歌手甲');
    expect(song.album, '专辑乙');
    expect(song.displayNameSource, DisplayNameSource.metadata);
  });

  test('reads ID3v2.3 Latin-1 tags', () async {
    final file = await writeMp3(
      'latin1.mp3',
      _v23Tag([_textFrameV23('TIT2', 0, latin1.encode('Café'))]),
    );

    final result = await service.importFiles([file.path]);

    expect(result.importedCount, 1);
    expect(database.songs.all().single.title, 'Café');
  });

  test('reads ID3v2.4 syncsafe frame sizes', () async {
    // Long enough for the UTF-8 frame body to exceed 128 bytes, where a
    // v2.4 syncsafe size field starts to differ from a plain 32-bit value.
    final longTitle = '曲目' * 80;
    final file = await writeMp3(
      'v24.mp3',
      _v24Tag([
        _textFrameV24('TIT2', 3, utf8.encode(longTitle)),
        _textFrameV24('TPE1', 3, utf8.encode('歌手乙')),
      ]),
    );

    final result = await service.importFiles([file.path]);

    expect(result.importedCount, 1);
    final song = database.songs.all().single;
    expect(song.title, longTitle);
    expect(song.artist, '歌手乙');
  });

  test('skips an ID3v2.4 extended header before frames', () async {
    final file = await writeMp3(
      'extheader.mp3',
      _v24TagWithExtendedHeader([
        _textFrameV24('TIT2', 3, utf8.encode('扩展头后的歌名')),
      ]),
    );

    final result = await service.importFiles([file.path]);

    expect(result.importedCount, 1);
    expect(database.songs.all().single.title, '扩展头后的歌名');
  });

  test('falls back to the filename when no usable ID3 frames exist', () async {
    final file = await writeMp3('歌手丙 - 歌名丁.mp3', _audioBytes());

    final result = await service.importFiles([file.path]);

    expect(result.importedCount, 1);
    final song = database.songs.all().single;
    expect(song.title, '歌名丁');
    expect(song.artist, '歌手丙');
    expect(song.displayNameSource, DisplayNameSource.filename);
  });
}

/// Small fake MPEG frames so imported files are not empty.
List<int> _audioBytes() {
  final bytes = <int>[];
  for (var i = 0; i < 512; i++) {
    bytes
      ..add(0xFF)
      ..add(0xFB)
      ..add(0x90);
  }
  return bytes;
}

/// UTF-16 little-endian text with the ID3v2.3 BOM prefix (encoding 1).
List<int> _utf16LeBytes(String text) {
  final bytes = <int>[];
  for (final unit in text.codeUnits) {
    bytes
      ..add(unit & 0xFF)
      ..add((unit >> 8) & 0xFF);
  }
  return [0xFF, 0xFE, ...bytes];
}

List<int> _syncSafe(int value) => [
  (value >> 21) & 0x7F,
  (value >> 14) & 0x7F,
  (value >> 7) & 0x7F,
  value & 0x7F,
];

List<int> _be32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _textFrameV23(String id, int encoding, List<int> textBytes) {
  final data = [encoding, ...textBytes];
  return [...ascii.encode(id), ..._be32(data.length), 0x00, 0x00, ...data];
}

List<int> _textFrameV24(String id, int encoding, List<int> textBytes) {
  final data = [encoding, ...textBytes];
  return [...ascii.encode(id), ..._syncSafe(data.length), 0x00, 0x00, ...data];
}

List<int> _v23Tag(List<List<int>> frames) {
  final header = [
    0x49,
    0x44,
    0x33, // "ID3"
    3,
    0,
    0, // v2.3, no flags
    ..._syncSafe(_frameBytesLength(frames)),
  ];
  return [...header, ..._flattenFrames(frames), ..._audioBytes()];
}

List<int> _v24Tag(List<List<int>> frames) {
  final header = [
    0x49,
    0x44,
    0x33, // "ID3"
    4,
    0,
    0, // v2.4, no flags
    ..._syncSafe(_frameBytesLength(frames)),
  ];
  return [...header, ..._flattenFrames(frames), ..._audioBytes()];
}

List<int> _v24TagWithExtendedHeader(List<List<int>> frames) {
  // v2.4 extended header: 4-byte syncsafe size including itself + 2 flag
  // bytes, so the total is 6 bytes.
  final body = [..._syncSafe(6), 0x00, 0x00, ..._flattenFrames(frames)];
  final header = [
    0x49,
    0x44,
    0x33, // "ID3"
    4,
    0,
    0x40, // extended header flag
    ..._syncSafe(body.length),
  ];
  return [...header, ...body, ..._audioBytes()];
}

int _frameBytesLength(List<List<int>> frames) =>
    frames.fold<int>(0, (total, frame) => total + frame.length);

List<int> _flattenFrames(List<List<int>> frames) => [
  for (final frame in frames) ...frame,
];
