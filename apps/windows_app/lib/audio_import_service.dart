import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:path/path.dart' as p;

class AudioImportService {
  AudioImportService(this.database, {this.libraryOverride});

  final MusicDatabase database;
  final MusicLibraryLocation? libraryOverride;

  Future<ImportResult> importFiles(List<String> paths) async {
    final library = libraryOverride ?? await MusicLibraryLocation.resolve();
    await library.ensureReady();

    final imported = <Song>[];
    final skipped = <ImportSkippedFile>[];
    final failed = <ImportFailedFile>[];
    var pendingCount = 0;
    var unnamedNumber = database.songs.nextUnnamedAudioNumber();

    for (final path in paths) {
      final file = File(path);
      try {
        if (!await file.exists()) {
          failed.add(ImportFailedFile(path: path, message: '文件不存在'));
          continue;
        }

        final format = AudioFormat.fromExtension(p.extension(path));
        if (format == null) {
          skipped.add(ImportSkippedFile(path: path, reason: '格式不支持'));
          continue;
        }

        final hash = await _fileHash(file);
        if (database.songs.findByHash(hash) != null) {
          skipped.add(ImportSkippedFile(path: path, reason: '重复文件'));
          continue;
        }

        final metadata = await _readMetadata(file, format);
        final naming = _resolveName(
          path: path,
          metadata: metadata,
          unnamedNumber: unnamedNumber,
        );
        if (naming.source == DisplayNameSource.unnamed) {
          unnamedNumber++;
          pendingCount++;
        }

        final songId = 'song_${hash.substring(0, min(16, hash.length))}';
        final targetPath = p.join(
          library.audioPath,
          '$songId.${format.extension}',
        );
        final stat = await file.stat();
        final now = DateTime.now().toUtc();
        final song = Song(
          id: songId,
          title: naming.title,
          artist: naming.artist,
          album: naming.album,
          durationMs: metadata.durationMs,
          format: format,
          fileSize: stat.size,
          fileHash: hash,
          localPath: targetPath,
          originalFileName: p.basename(path),
          displayNameSource: naming.source,
          isPendingReview: naming.source == DisplayNameSource.unnamed,
          createdAt: now,
          updatedAt: now,
        );
        await file.copy(targetPath);
        try {
          database.songs.upsert(song);
        } catch (_) {
          // Do not leave an unreferenced copy behind when the database write
          // fails; the Windows side has no orphan sweep for imported files.
          final copied = File(targetPath);
          if (await copied.exists()) {
            await copied.delete().catchError((_) => copied);
          }
          rethrow;
        }
        imported.add(song);
      } catch (error) {
        failed.add(ImportFailedFile(path: path, message: error.toString()));
      }
    }

    return ImportResult(
      importedSongs: imported,
      skippedFiles: skipped,
      failedFiles: failed,
      pendingReviewCount: pendingCount,
    );
  }

  Future<ImportResult> importFolder(String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      return ImportResult(
        importedSongs: const [],
        skippedFiles: const [],
        failedFiles: [ImportFailedFile(path: folderPath, message: '文件夹不存在')],
        pendingReviewCount: 0,
      );
    }

    final paths = <String>[];
    await for (final entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          AudioFormat.fromExtension(p.extension(entity.path)) != null) {
        paths.add(entity.path);
      }
    }
    paths.sort();
    return importFiles(paths);
  }
}

class MusicLibraryLocation {
  const MusicLibraryLocation({required this.rootPath});

  final String rootPath;

  String get audioPath => p.join(rootPath, 'audio');

  String get databasePath => p.join(rootPath, 'library.db');

  static Future<MusicLibraryLocation> resolve() async {
    final configured = Platform.environment['ONEPLUS_MUSIC_LIBRARY'];
    if (configured != null && configured.trim().isNotEmpty) {
      return MusicLibraryLocation(rootPath: configured.trim());
    }
    final base = Directory('D:\\').existsSync()
        ? p.join('D:\\', 'OnePlusMusic', 'Library')
        : p.join(Directory.current.path, 'library');
    return MusicLibraryLocation(rootPath: base);
  }

  Future<void> ensureReady() async {
    await Directory(audioPath).create(recursive: true);
  }
}

class WindowsFileDialog {
  Future<List<String>> pickAudioFiles() async {
    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Multiselect = $true
$dialog.Filter = "Audio Files|*.mp3;*.flac;*.m4a;*.wav"
$dialog.Title = "选择要导入的音乐文件"
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  $dialog.FileNames | ForEach-Object { [Console]::WriteLine($_) }
}
''';
    return _runDialog(script);
  }

  Future<String?> pickFolder() async {
    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = "选择要导入的音乐文件夹"
$dialog.ShowNewFolderButton = $false
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::WriteLine($dialog.SelectedPath)
}
''';
    final result = await _runDialog(script);
    return result.isEmpty ? null : result.first;
  }

  Future<List<String>> _runDialog(String script) async {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-STA',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      throw AppError('file_dialog_failed', '打开文件选择窗口失败', cause: result.stderr);
    }
    return LineSplitter.split(
      result.stdout.toString(),
    ).map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
  }
}

Future<String> _fileHash(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

Future<SongMetadata> _readMetadata(File file, AudioFormat format) async {
  if (format != AudioFormat.mp3) {
    return const SongMetadata();
  }
  return _readMp3Id3v2Metadata(file);
}

Future<SongMetadata> _readMp3Id3v2Metadata(File file) async {
  final raf = await file.open();
  try {
    final header = await raf.read(10);
    if (header.length < 10 ||
        header[0] != 0x49 ||
        header[1] != 0x44 ||
        header[2] != 0x33) {
      return const SongMetadata();
    }

    // Only v2.3 and v2.4 frame layouts are handled. v2.2 uses 3-byte frame
    // IDs and is old enough that V1 does not need it.
    final major = header[3];
    if (major != 3 && major != 4) {
      return const SongMetadata();
    }
    final flags = header[5];
    final tagSize = _syncSafeInt(header.sublist(6, 10));
    List<int> bytes = await raf.read(tagSize);
    if ((flags & 0x80) != 0) {
      bytes = _deUnsynchronize(bytes);
    }

    var offset = 0;
    if ((flags & 0x40) != 0) {
      // Skip the extended header so its bytes are not misread as frames.
      if (major == 4) {
        if (bytes.length < 4) {
          return const SongMetadata();
        }
        // v2.4 extended header size includes its own 4 size bytes.
        offset = _syncSafeInt(bytes.sublist(0, 4));
      } else {
        if (bytes.length < 6) {
          return const SongMetadata();
        }
        // v2.3 extended header size excludes its own 4 size bytes.
        final extSize =
            (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
        offset = 4 + extSize;
      }
    }

    String? title;
    String? artist;
    String? album;
    // v2.3 and v2.4 frames both carry a 10-byte header
    // (4 ID + 4 size + 2 flags); only the size encoding differs.
    const frameHeaderSize = 10;
    while (offset + frameHeaderSize <= bytes.length) {
      final frameIdBytes = bytes.sublist(offset, offset + 4);
      if (!_isValidFrameId(frameIdBytes)) {
        break;
      }
      final frameId = ascii.decode(frameIdBytes);
      final sizeBytes = bytes.sublist(offset + 4, offset + 8);
      final frameSize = major == 4
          ? _syncSafeInt(sizeBytes)
          : (sizeBytes[0] << 24) |
                (sizeBytes[1] << 16) |
                (sizeBytes[2] << 8) |
                sizeBytes[3];
      if (frameSize <= 0 ||
          offset + frameHeaderSize + frameSize > bytes.length) {
        break;
      }
      final frame = bytes.sublist(
        offset + frameHeaderSize,
        offset + frameHeaderSize + frameSize,
      );
      final text = _decodeTextFrame(frame);
      switch (frameId) {
        case 'TIT2':
          title = text;
          break;
        case 'TPE1':
          artist = text;
          break;
        case 'TALB':
          album = text;
          break;
      }
      offset += frameHeaderSize + frameSize;
    }

    return SongMetadata(
      title: _blankToNull(title),
      artist: _blankToNull(artist),
      album: _blankToNull(album),
    );
  } catch (_) {
    return const SongMetadata();
  } finally {
    await raf.close();
  }
}

int _syncSafeInt(List<int> bytes) {
  return (bytes[0] << 21) | (bytes[1] << 14) | (bytes[2] << 7) | bytes[3];
}

/// Removes ID3v2 unsynchronisation (0xFF 0x00 -> 0xFF) from tag bytes.
List<int> _deUnsynchronize(List<int> bytes) {
  if (bytes.length < 2) {
    return bytes;
  }
  final result = <int>[];
  for (var index = 0; index < bytes.length; index++) {
    result.add(bytes[index]);
    if (bytes[index] == 0xFF &&
        index + 1 < bytes.length &&
        bytes[index + 1] == 0x00) {
      index++;
    }
  }
  return result;
}

/// v2.3/v2.4 frame IDs are exactly four characters from A-Z or 0-9.
bool _isValidFrameId(List<int> bytes) {
  if (bytes.length != 4) {
    return false;
  }
  for (final byte in bytes) {
    final isLetter = byte >= 0x41 && byte <= 0x5A;
    final isDigit = byte >= 0x30 && byte <= 0x39;
    if (!isLetter && !isDigit) {
      return false;
    }
  }
  return true;
}

String? _decodeTextFrame(List<int> frame) {
  if (frame.isEmpty) {
    return null;
  }
  final encoding = frame.first;
  final payload = frame.sublist(1);
  try {
    switch (encoding) {
      case 0:
        // The spec says ISO-8859-1, but several tools write UTF-8 here.
        // Prefer strict UTF-8 and fall back to Latin-1 for accented text.
        try {
          return _cleanText(utf8.decode(payload));
        } on FormatException {
          return _cleanText(latin1.decode(payload, allowInvalid: true));
        }
      case 1:
        // UTF-16 with a byte order mark.
        if (payload.length >= 2 && payload[0] == 0xFF && payload[1] == 0xFE) {
          return _cleanText(_decodeUtf16le(payload.sublist(2)));
        }
        if (payload.length >= 2 && payload[0] == 0xFE && payload[1] == 0xFF) {
          return _cleanText(_decodeUtf16be(payload.sublist(2)));
        }
        return _cleanText(_decodeUtf16be(payload));
      case 2:
        // UTF-16BE without a byte order mark.
        return _cleanText(_decodeUtf16be(payload));
      case 3:
        return _cleanText(utf8.decode(payload, allowMalformed: true));
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _cleanText(String value) {
  var cleaned = value.replaceAll('\u0000', '');
  // Drop replacement characters left by an odd trailing byte (some writers
  // terminate UTF-16 text with a single 0x00 instead of two).
  cleaned = cleaned.replaceAll(RegExp(r'\uFFFD+$'), '');
  cleaned = cleaned.trim();
  return cleaned.isEmpty ? null : cleaned;
}

/// Decodes UTF-16 little-endian code units. Surrogate pairs pass through
/// [String.fromCharCodes] unchanged, so non-BMP characters stay intact.
String _decodeUtf16le(List<int> bytes) {
  final codeUnits = <int>[];
  for (var index = 0; index + 1 < bytes.length; index += 2) {
    codeUnits.add(bytes[index] | (bytes[index + 1] << 8));
  }
  if (bytes.length.isOdd) {
    codeUnits.add(0xFFFD);
  }
  return String.fromCharCodes(codeUnits);
}

String _decodeUtf16be(List<int> bytes) {
  final codeUnits = <int>[];
  for (var index = 0; index + 1 < bytes.length; index += 2) {
    codeUnits.add((bytes[index] << 8) | bytes[index + 1]);
  }
  if (bytes.length.isOdd) {
    codeUnits.add(0xFFFD);
  }
  return String.fromCharCodes(codeUnits);
}

String? _blankToNull(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

_ResolvedName _resolveName({
  required String path,
  required SongMetadata metadata,
  required int unnamedNumber,
}) {
  final metaTitle = _blankToNull(metadata.title);
  if (metaTitle != null) {
    return _ResolvedName(
      title: metaTitle,
      artist: _blankToNull(metadata.artist) ?? '未知歌手',
      album: _blankToNull(metadata.album) ?? '未知专辑',
      source: DisplayNameSource.metadata,
    );
  }

  final baseName = p.basenameWithoutExtension(path).trim();
  final filenameParts = _parseMeaningfulFileName(baseName);
  if (filenameParts != null) {
    return _ResolvedName(
      title: filenameParts.title,
      artist: filenameParts.artist,
      album: '未知专辑',
      source: DisplayNameSource.filename,
    );
  }

  return _ResolvedName(
    title: '未命名音频 ${unnamedNumber.toString().padLeft(3, '0')}',
    artist: '未知歌手',
    album: '未知专辑',
    source: DisplayNameSource.unnamed,
  );
}

_FilenameParts? _parseMeaningfulFileName(String value) {
  if (_isMeaninglessFileName(value)) {
    return null;
  }
  final parts = value.split(RegExp(r'\s+-\s+'));
  if (parts.length == 2 &&
      !_isMeaninglessFileName(parts[0]) &&
      !_isMeaninglessFileName(parts[1])) {
    return _FilenameParts(artist: parts[0].trim(), title: parts[1].trim());
  }
  return _FilenameParts(artist: '未知歌手', title: value);
}

bool _isMeaninglessFileName(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return true;
  }
  if (RegExp(r'^[\d\s._-]+$').hasMatch(text)) {
    return true;
  }
  if (text.contains('�')) {
    return true;
  }
  if (RegExp(r'^[a-fA-F0-9]{10,}$').hasMatch(text)) {
    return true;
  }
  if (RegExp(r'^[A-Za-z0-9_-]{18,}$').hasMatch(text) && !text.contains(' ')) {
    return true;
  }
  return false;
}

class _ResolvedName {
  const _ResolvedName({
    required this.title,
    required this.artist,
    required this.album,
    required this.source,
  });

  final String title;
  final String artist;
  final String album;
  final DisplayNameSource source;
}

class _FilenameParts {
  const _FilenameParts({required this.artist, required this.title});

  final String artist;
  final String title;
}
