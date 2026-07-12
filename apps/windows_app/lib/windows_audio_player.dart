import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:music_core/music_core.dart';

class WindowsAudioPlayer {
  WindowsAudioPlayer();

  Process? _process;
  Song? _currentSong;
  bool _paused = false;
  Duration _basePosition = Duration.zero;
  final Stopwatch _stopwatch = Stopwatch();

  Song? get currentSong => _currentSong;
  Duration get position {
    if (_currentSong == null) {
      return Duration.zero;
    }
    return _basePosition + _stopwatch.elapsed;
  }

  Future<void> play(Song song, {Duration startAt = Duration.zero}) async {
    await stop();
    await _start(song, startAt: startAt);
  }

  Future<void> _start(Song song, {required Duration startAt}) async {
    final file = File(song.localPath);
    if (!await file.exists()) {
      throw AppError('audio_file_missing', '本地音频文件不存在：${song.localPath}');
    }

    try {
      final args = [
        if (startAt > Duration.zero) ...[
          '-ss',
          (startAt.inMilliseconds / 1000).toStringAsFixed(3),
        ],
        '-nodisp',
        '-autoexit',
        '-loglevel',
        'quiet',
        song.localPath,
      ];
      _process = await Process.start('ffplay', args);
    } on ProcessException catch (error) {
      throw AppError(
        'audio_player_unavailable',
        '本地播放需要 ffplay。当前环境未能启动 ffplay。',
        cause: error,
      );
    }

    _paused = false;
    _basePosition = startAt;
    _stopwatch
      ..reset()
      ..start();
    _currentSong = song;
  }

  Future<void> pause() async {
    final process = _process;
    if (process == null || _paused) {
      return;
    }
    if (Platform.isWindows) {
      _suspendProcess(process);
    } else {
      process.stdin.write('p');
    }
    _basePosition = position;
    _stopwatch.stop();
    _paused = true;
  }

  Future<void> resume() async {
    final process = _process;
    if (process == null || !_paused) {
      return;
    }
    if (Platform.isWindows) {
      _resumeProcess(process);
    } else {
      process.stdin.write('p');
    }
    _stopwatch.start();
    _paused = false;
  }

  Future<void> seek(Duration position) async {
    final song = _currentSong;
    if (song == null) {
      return;
    }
    final wasPaused = _paused;
    await stop();
    await _start(song, startAt: position);
    if (wasPaused) {
      await pause();
    }
  }

  Future<Duration?> probeDuration(Song song) async {
    try {
      final result = await Process.run('ffprobe', [
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        song.localPath,
      ]);
      if (result.exitCode != 0) {
        return null;
      }
      final seconds = double.tryParse(result.stdout.toString().trim());
      if (seconds == null || seconds <= 0) {
        return null;
      }
      return Duration(milliseconds: (seconds * 1000).round());
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    final process = _process;
    final wasPaused = _paused;
    _process = null;
    _currentSong = null;
    _paused = false;
    _basePosition = Duration.zero;
    _stopwatch
      ..stop()
      ..reset();
    if (process == null) {
      return;
    }

    if (Platform.isWindows && wasPaused) {
      try {
        _resumeProcess(process);
      } catch (_) {
        // The process may have already exited. Stop should still finish cleanly.
      }
    }

    process.kill();
    await _waitForExitOrKill(process);
  }

  Future<void> dispose() => stop();

  Future<void> _waitForExitOrKill(Process process) async {
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 700));
      return;
    } on TimeoutException {
      // Fall through to the stronger Windows tree kill below.
    }

    if (Platform.isWindows) {
      await Process.run('taskkill.exe', ['/PID', '${process.pid}', '/T', '/F']);
    }

    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Keep the UI responsive even if the OS refuses to report process exit.
    }
  }

  static void _suspendProcess(Process process) {
    final handle = _openProcess(_processSuspendResume, 0, process.pid);
    if (handle == 0) {
      throw AppError('audio_pause_failed', '无法暂停当前播放进程。');
    }
    try {
      final result = _ntSuspendProcess(handle);
      if (result != 0) {
        throw AppError('audio_pause_failed', '无法暂停当前播放进程。');
      }
    } finally {
      _closeHandle(handle);
    }
  }

  static void _resumeProcess(Process process) {
    final handle = _openProcess(_processSuspendResume, 0, process.pid);
    if (handle == 0) {
      throw AppError('audio_resume_failed', '无法继续当前播放进程。');
    }
    try {
      final result = _ntResumeProcess(handle);
      if (result != 0) {
        throw AppError('audio_resume_failed', '无法继续当前播放进程。');
      }
    } finally {
      _closeHandle(handle);
    }
  }

  static const int _processSuspendResume = 0x0800;

  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final DynamicLibrary _ntdll = DynamicLibrary.open('ntdll.dll');

  static final int Function(int desiredAccess, int inheritHandle, int processId)
  _openProcess = _kernel32
      .lookupFunction<
        IntPtr Function(
          Uint32 desiredAccess,
          Int32 inheritHandle,
          Uint32 processId,
        ),
        int Function(int desiredAccess, int inheritHandle, int processId)
      >('OpenProcess');

  static final int Function(int handle) _closeHandle = _kernel32
      .lookupFunction<Int32 Function(IntPtr handle), int Function(int handle)>(
        'CloseHandle',
      );

  static final int Function(int handle) _ntSuspendProcess = _ntdll
      .lookupFunction<
        Int32 Function(IntPtr processHandle),
        int Function(int processHandle)
      >('NtSuspendProcess');

  static final int Function(int handle) _ntResumeProcess = _ntdll
      .lookupFunction<
        Int32 Function(IntPtr processHandle),
        int Function(int processHandle)
      >('NtResumeProcess');
}
