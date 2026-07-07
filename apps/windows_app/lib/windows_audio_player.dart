import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:music_core/music_core.dart';

typedef _MciSendStringNative =
    Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32, IntPtr);
typedef _MciSendStringDart =
    int Function(Pointer<Utf16>, Pointer<Utf16>, int, int);

class WindowsAudioPlayer {
  WindowsAudioPlayer() {
    _mciSendString = DynamicLibrary.open(
      'winmm.dll',
    ).lookupFunction<_MciSendStringNative, _MciSendStringDart>('mciSendStringW');
  }

  static const _alias = 'oneplus_music_player';

  late final _MciSendStringDart _mciSendString;
  Song? _currentSong;

  Song? get currentSong => _currentSong;

  Future<void> play(Song song) async {
    stop();
    _send('open "${song.localPath}" alias $_alias');
    _send('play $_alias');
    _currentSong = song;
  }

  void pause() {
    if (_currentSong != null) {
      _send('pause $_alias');
    }
  }

  void resume() {
    if (_currentSong != null) {
      _send('resume $_alias');
    }
  }

  void stop() {
    _send('close $_alias', throwOnError: false);
    _currentSong = null;
  }

  int? positionMs() {
    if (_currentSong == null) {
      return null;
    }
    return int.tryParse(_send('status $_alias position'));
  }

  int? durationMs() {
    if (_currentSong == null) {
      return null;
    }
    return int.tryParse(_send('status $_alias length'));
  }

  String _send(String command, {bool throwOnError = true}) {
    final commandPtr = command.toNativeUtf16();
    final buffer = calloc<Uint16>(256).cast<Utf16>();
    try {
      final result = _mciSendString(commandPtr, buffer, 256, 0);
      if (result != 0 && throwOnError) {
        throw AppError('audio_playback_failed', '本地播放命令失败：$command');
      }
      return buffer.toDartString();
    } finally {
      calloc.free(commandPtr);
      calloc.free(buffer);
    }
  }
}
