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
        await file.copy(targetPath);

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

        database.songs.upsert(song);
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

    final tagSize = _syncSafeInt(header.sublist(6, 10));
    final bytes = await raf.read(tagSize);
    var offset = 0;
    String? title;
    String? artist;
    String? album;

    while (offset + 10 <= bytes.length) {
      final frameId = ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final frameSize = _frameSize(bytes.sublist(offset + 4, offset + 8));
      if (frameSize <= 0 || offset + 10 + frameSize > bytes.length) {
        break;
      }
      final frame = bytes.sublist(offset + 10, offset + 10 + frameSize);
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
      offset += 10 + frameSize;
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

int _frameSize(List<int> bytes) {
  return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
}

String? _decodeTextFrame(List<int> frame) {
  if (frame.isEmpty) {
    return null;
  }
  final encoding = frame.first;
  final payload = frame.sublist(1);
  try {
    if (encoding == 0 || encoding == 3) {
      return utf8
          .decode(payload, allowMalformed: true)
          .replaceAll('\u0000', '')
          .trim();
    }
    if (encoding == 1 || encoding == 2) {
      return String.fromCharCodes(payload).replaceAll('\u0000', '').trim();
    }
  } catch (_) {
    return null;
  }
  return null;
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
