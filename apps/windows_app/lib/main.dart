import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';

import 'audio_import_service.dart';
import 'sync_server.dart';
import 'windows_audio_player.dart';

class _AppColors {
  const _AppColors._();

  static const background = Color(0xFF17181A);
  static const sidebar = Color(0xFF121315);
  static const surface = Color(0xFF202225);
  static const surfaceRaised = Color(0xFF292C30);
  static const outline = Color(0xFF383B40);
  static const primaryText = Color(0xFFF1F0EE);
  static const secondaryText = Color(0xFFA8A5A2);
  static const berry = Color(0xFFC95670);
  static const berrySoft = Color(0xFF3A222B);
  static const lime = Color(0xFFB9D267);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = await MusicLibraryLocation.resolve();
  await library.ensureReady();
  final database = MusicDatabase.open(library.databasePath);
  runApp(WindowsMusicApp(database: database, library: library));
}

class WindowsMusicApp extends StatelessWidget {
  const WindowsMusicApp({
    required this.database,
    required this.library,
    super.key,
  });

  final MusicDatabase database;
  final MusicLibraryLocation library;

  @override
  Widget build(BuildContext context) {
    const textTheme = TextTheme(
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.35,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    );
    final colorScheme = const ColorScheme.dark(
      primary: _AppColors.berry,
      onPrimary: _AppColors.primaryText,
      secondary: _AppColors.lime,
      onSecondary: _AppColors.background,
      surface: _AppColors.surface,
      onSurface: _AppColors.primaryText,
      error: Color(0xFFE77A7A),
      onError: _AppColors.background,
      outline: _AppColors.outline,
    );
    return MaterialApp(
      title: '壹加音乐',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        fontFamily: 'Microsoft YaHei UI',
        textTheme: textTheme,
        scaffoldBackgroundColor: _AppColors.background,
        dividerColor: _AppColors.outline,
        appBarTheme: const AppBarTheme(
          backgroundColor: _AppColors.background,
          foregroundColor: _AppColors.primaryText,
          elevation: 0,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: _AppColors.sidebar,
          indicatorColor: _AppColors.berrySoft,
          selectedIconTheme: IconThemeData(color: _AppColors.berry),
          selectedLabelTextStyle: TextStyle(
            color: _AppColors.primaryText,
            fontWeight: FontWeight.w500,
          ),
          unselectedIconTheme: IconThemeData(color: _AppColors.secondaryText),
          unselectedLabelTextStyle: TextStyle(color: _AppColors.secondaryText),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _AppColors.surface,
          hintStyle: const TextStyle(color: _AppColors.secondaryText),
          labelStyle: const TextStyle(color: _AppColors.secondaryText),
          prefixIconColor: _AppColors.secondaryText,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.berry, width: 1.2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _AppColors.berry,
            foregroundColor: _AppColors.primaryText,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _AppColors.primaryText,
            side: const BorderSide(color: _AppColors.outline),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          selectedTileColor: _AppColors.berrySoft,
          selectedColor: _AppColors.primaryText,
          iconColor: _AppColors.secondaryText,
          textColor: _AppColors.primaryText,
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: _AppColors.secondaryText,
            hoverColor: _AppColors.surfaceRaised,
          ),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: _AppColors.berry,
          inactiveTrackColor: _AppColors.outline,
          thumbColor: _AppColors.primaryText,
          overlayColor: _AppColors.berrySoft,
          trackHeight: 3,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: _AppColors.surfaceRaised,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: _AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        useMaterial3: true,
      ),
      home: WindowsHomePage(database: database, library: library),
    );
  }
}

class WindowsHomePage extends StatefulWidget {
  const WindowsHomePage({
    required this.database,
    required this.library,
    super.key,
  });

  final MusicDatabase database;
  final MusicLibraryLocation library;

  @override
  State<WindowsHomePage> createState() => _WindowsHomePageState();
}

enum _WindowsPage { library, import, sync }

enum _PlaybackMode { sequence, repeatAll, repeatOne, shuffle }

enum _LibrarySongAction {
  playNext,
  addToQueue,
  addToPlaylist,
  removeFromLibrary,
}

enum _PlaylistSongAction { playNext, addToQueue, removeFromPlaylist }

class _WindowsHomePageState extends State<WindowsHomePage> {
  late final AudioImportService _importService;
  late final WindowsAudioPlayer _player;
  late final WindowsSyncServer _syncServer;
  final _dialog = WindowsFileDialog();
  final _searchController = TextEditingController();
  final _random = Random();

  List<Song> _songs = const [];
  List<Song> _pendingSongs = const [];
  List<Playlist> _playlists = const [];
  List<Song> _playlistSongs = const [];
  Playlist? _selectedPlaylist;
  ImportResult? _lastImportResult;
  Song? _nowPlaying;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  Timer? _progressTimer;
  StreamSubscription<void>? _completionSubscription;
  List<Song> _queue = const [];
  int _queueIndex = -1;
  _PlaybackMode _playbackMode = _PlaybackMode.sequence;
  _WindowsPage _page = _WindowsPage.library;
  SyncSession? _syncSession;
  String? _syncPayloadText;
  String _status = '准备就绪';
  String _syncStatus = '同步模式未开启';
  bool _busy = false;
  bool _syncBusy = false;
  bool _isPlaybackPaused = false;

  @override
  void initState() {
    super.initState();
    _importService = AudioImportService(widget.database);
    _player = WindowsAudioPlayer();
    _syncServer = WindowsSyncServer(widget.database);
    _completionSubscription = _player.completionStream.listen((_) {
      if (mounted) {
        _handlePlaybackCompleted();
      }
    });
    _reloadAll();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _completionSubscription?.cancel();
    _syncServer.stop();
    _player.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _reloadAll() {
    final keyword = _searchController.text.trim();
    final playlists = keyword.isEmpty
        ? widget.database.playlists.all()
        : widget.database.search.searchPlaylists(keyword);
    final selected = _selectedPlaylist == null
        ? (playlists.isEmpty ? null : playlists.first)
        : playlists
              .where((playlist) => playlist.id == _selectedPlaylist!.id)
              .firstOrNull;
    setState(() {
      _songs = keyword.isEmpty
          ? widget.database.songs.all()
          : widget.database.search.searchSongs(keyword);
      _pendingSongs = widget.database.songs.pendingReview();
      _playlists = playlists;
      _selectedPlaylist = selected;
      _playlistSongs = selected == null
          ? const []
          : widget.database.playlists.songsForPlaylist(selected.id);
    });
  }

  Future<void> _importFiles() async {
    await _runImport(() async {
      final paths = await _dialog.pickAudioFiles();
      if (paths.isEmpty) {
        return null;
      }
      return _importService.importFiles(paths);
    });
  }

  Future<void> _importFolder() async {
    await _runImport(() async {
      final folder = await _dialog.pickFolder();
      if (folder == null) {
        return null;
      }
      return _importService.importFolder(folder);
    });
  }

  Future<void> _runImport(Future<ImportResult?> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在导入...';
    });

    try {
      final result = await action();
      if (result == null) {
        setState(() {
          _status = '已取消导入';
          _busy = false;
        });
        return;
      }
      setState(() {
        _lastImportResult = result;
        _status =
            '导入完成：成功 ${result.importedCount}，跳过 ${result.skippedFiles.length}，失败 ${result.failedFiles.length}，待整理 ${result.pendingReviewCount}';
        _busy = false;
      });
      _reloadAll();
    } catch (error) {
      setState(() {
        _status = '导入失败：$error';
        _busy = false;
      });
    }
  }

  Future<void> _createPlaylist() async {
    final name = await _askForName(title: '新建歌单', initialValue: '新歌单');
    if (!mounted || name == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    final playlist = Playlist(
      id: 'playlist_${now.microsecondsSinceEpoch}',
      name: name,
      sortOrder: _playlists.length,
      createdAt: now,
      updatedAt: now,
    );
    widget.database.playlists.upsert(playlist);
    _selectedPlaylist = playlist;
    _reloadAll();
  }

  Future<void> _renamePlaylist() async {
    final playlist = _selectedPlaylist;
    if (playlist == null) {
      return;
    }
    final name = await _askForName(title: '重命名歌单', initialValue: playlist.name);
    if (!mounted || name == null) {
      return;
    }
    widget.database.playlists.upsert(
      Playlist(
        id: playlist.id,
        name: name,
        sortOrder: playlist.sortOrder,
        createdAt: playlist.createdAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    _reloadAll();
  }

  Future<void> _deletePlaylist() async {
    final playlist = _selectedPlaylist;
    if (playlist == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除“${playlist.name}”吗？歌曲文件和主库歌曲不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    widget.database.playlists.deletePlaylist(playlist.id);
    setState(() {
      _selectedPlaylist = null;
      _status = '已删除歌单：${playlist.name}。歌曲文件不会被删除。';
    });
    _reloadAll();
  }

  void _addSongToPlaylist(Song song) {
    final playlist = _selectedPlaylist;
    if (playlist == null) {
      setState(() => _status = '请先创建或选择一个歌单');
      return;
    }
    final now = DateTime.now().toUtc();
    widget.database.playlists.addSong(
      item: PlaylistItem(
        id: 'item_${now.microsecondsSinceEpoch}',
        playlistId: playlist.id,
        songId: song.id,
        sortOrder: _playlistSongs.length,
        createdAt: now,
      ),
    );
    setState(() => _status = '已加入歌单：${song.title}');
    _reloadAll();
  }

  void _removeSongFromPlaylist(Song song) {
    final playlist = _selectedPlaylist;
    if (playlist == null) {
      return;
    }
    widget.database.playlists.removeSong(
      playlistId: playlist.id,
      songId: song.id,
    );
    setState(() => _status = '已从歌单移除：${song.title}。主库歌曲不会删除。');
    _reloadAll();
  }

  Future<void> _removeSongFromLibrary(Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出全部歌曲'),
        content: Text(
          '确定把“${song.title}”从全部歌曲移除吗？\n'
          '这只会删除本应用音乐库中的记录和复制音频，不会删除你最初导入的原始文件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    try {
      if (_nowPlaying?.id == song.id) {
        await _player.stop();
        _nowPlaying = null;
      }
      widget.database.songs.deleteById(song.id);
      final deletedCopy = await _deleteLibraryCopy(song);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = deletedCopy
            ? '已从全部歌曲移除：${song.title}。原始导入文件不会删除。'
            : '已从全部歌曲移除：${song.title}。未删除音频文件，因为它不在本应用音乐库目录。';
      });
      _reloadAll();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = '移除失败：$error');
    }
  }

  Future<bool> _deleteLibraryCopy(Song song) async {
    final file = File(song.localPath);
    final audioRoot = p.normalize(
      Directory(widget.library.audioPath).absolute.path,
    );
    final filePath = p.normalize(file.absolute.path);
    final rootPrefix = audioRoot.endsWith(p.separator)
        ? audioRoot
        : '$audioRoot${p.separator}';
    if (!filePath.toLowerCase().startsWith(rootPrefix.toLowerCase())) {
      return false;
    }
    if (!await file.exists()) {
      return false;
    }
    await file.delete();
    return true;
  }

  Future<void> _playSong(Song song, {List<Song>? context}) async {
    final source = List<Song>.from(context ?? _songs);
    if (source.isEmpty) {
      source.add(song);
    }
    final index = source.indexWhere((item) => item.id == song.id);
    if (index < 0) {
      source.insert(0, song);
    }
    setState(() {
      _queue = source;
      _queueIndex = index < 0 ? 0 : index;
    });
    await _startPlayback(song);
  }

  Future<void> _startPlayback(Song song) async {
    try {
      await _player.play(song);
      final duration = song.durationMs == null
          ? await _player.probeDuration(song)
          : Duration(milliseconds: song.durationMs!);
      if (!mounted) {
        return;
      }
      setState(() {
        _nowPlaying = song;
        _playbackPosition = Duration.zero;
        _playbackDuration = duration ?? Duration.zero;
        _isPlaybackPaused = false;
        _status = '正在播放：${song.title}';
      });
      _startProgressTimer();
    } catch (error) {
      setState(() => _status = '播放失败：$error');
    }
  }

  Future<void> _pausePlayback() async {
    try {
      await _player.pause();
      _syncPlaybackPosition();
      setState(() {
        _isPlaybackPaused = true;
        _status = '已暂停：${_nowPlaying?.title ?? ''}';
      });
    } catch (error) {
      setState(() => _status = '暂停失败：$error');
    }
  }

  Future<void> _resumePlayback() async {
    try {
      await _player.resume();
      _startProgressTimer();
      setState(() {
        _isPlaybackPaused = false;
        _status = '继续播放：${_nowPlaying?.title ?? ''}';
      });
    } catch (error) {
      setState(() => _status = '继续播放失败：$error');
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _player.stop();
      _progressTimer?.cancel();
      setState(() {
        _nowPlaying = null;
        _playbackPosition = Duration.zero;
        _playbackDuration = Duration.zero;
        _isPlaybackPaused = false;
        _status = '已停止播放';
      });
    } catch (error) {
      setState(() => _status = '停止失败：$error');
    }
  }

  Future<void> _playQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    setState(() => _queueIndex = index);
    await _startPlayback(_queue[index]);
  }

  Future<void> _previousTrack() async {
    if (_nowPlaying == null) {
      return;
    }
    if (_playbackPosition >= const Duration(seconds: 5)) {
      await _seekPlayback(Duration.zero);
      return;
    }
    if (_queue.isEmpty) {
      await _seekPlayback(Duration.zero);
      return;
    }
    var previousIndex = _queueIndex - 1;
    if (previousIndex < 0 && _playbackMode == _PlaybackMode.repeatAll) {
      previousIndex = _queue.length - 1;
    }
    if (previousIndex < 0) {
      await _seekPlayback(Duration.zero);
      return;
    }
    await _playQueueIndex(previousIndex);
  }

  Future<void> _nextTrack({bool automatic = false}) async {
    if (_queue.isEmpty || _queueIndex < 0) {
      return;
    }
    if (automatic && _playbackMode == _PlaybackMode.repeatOne) {
      await _playQueueIndex(_queueIndex);
      return;
    }

    int? nextIndex;
    if (_playbackMode == _PlaybackMode.shuffle && _queue.length > 1) {
      final candidates = List<int>.generate(_queue.length, (index) => index)
        ..remove(_queueIndex);
      nextIndex = candidates[_random.nextInt(candidates.length)];
    } else if (_queueIndex + 1 < _queue.length) {
      nextIndex = _queueIndex + 1;
    } else if (_playbackMode == _PlaybackMode.repeatAll) {
      nextIndex = 0;
    }

    if (nextIndex == null) {
      if (automatic) {
        _progressTimer?.cancel();
        setState(() {
          _nowPlaying = null;
          _playbackPosition = Duration.zero;
          _playbackDuration = Duration.zero;
          _isPlaybackPaused = false;
          _status = '播放列表已结束';
        });
      } else {
        setState(() => _status = '已经是最后一首');
      }
      return;
    }
    await _playQueueIndex(nextIndex);
  }

  void _handlePlaybackCompleted() {
    _progressTimer?.cancel();
    unawaited(_nextTrack(automatic: true));
  }

  void _enqueue(Song song, {required bool playNext}) {
    if (_nowPlaying == null) {
      unawaited(_playSong(song, context: [song]));
      return;
    }
    if (_queue.any((item) => item.id == song.id)) {
      setState(() => _status = '“${song.title}”已在播放队列中');
      return;
    }
    final updated = List<Song>.from(_queue);
    final insertAt = playNext ? _queueIndex + 1 : updated.length;
    updated.insert(insertAt.clamp(0, updated.length), song);
    setState(() {
      _queue = updated;
      _status = playNext ? '已设为下一首：${song.title}' : '已加入播放队列：${song.title}';
    });
  }

  void _removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    if (index == _queueIndex) {
      setState(() => _status = '当前正在播放，不能从队列移除');
      return;
    }
    final updated = List<Song>.from(_queue)..removeAt(index);
    setState(() {
      _queue = updated;
      if (index < _queueIndex) {
        _queueIndex--;
      }
    });
  }

  void _reorderQueue(int oldIndex, int newIndex) {
    final updated = List<Song>.from(_queue);
    final song = updated.removeAt(oldIndex);
    updated.insert(newIndex, song);
    final currentId = _nowPlaying?.id;
    setState(() {
      _queue = updated;
      _queueIndex = currentId == null
          ? -1
          : updated.indexWhere((item) => item.id == currentId);
    });
  }

  void _clearUpcomingQueue() {
    final current = _nowPlaying;
    setState(() {
      _queue = current == null ? const [] : [current];
      _queueIndex = current == null ? -1 : 0;
      _status = '已清空待播放队列';
    });
  }

  void _setPlaybackMode(_PlaybackMode mode) {
    setState(() {
      _playbackMode = mode;
      _status = '播放模式：${_playbackModeLabel(mode)}';
    });
  }

  Future<void> _seekPlayback(Duration position) async {
    try {
      await _player.seek(position);
      if (!mounted) {
        return;
      }
      setState(() => _playbackPosition = position);
      _startProgressTimer();
    } catch (error) {
      setState(() => _status = '拖动进度失败：$error');
    }
  }

  Future<void> _togglePlayback() {
    return _isPlaybackPaused ? _resumePlayback() : _pausePlayback();
  }

  Future<void> _seekRelative(Duration offset) {
    final maximum = _playbackDuration > Duration.zero
        ? _playbackDuration
        : Duration(days: 1);
    var target = _playbackPosition + offset;
    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (target > maximum) {
      target = maximum;
    }
    return _seekPlayback(target);
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || _nowPlaying == null) {
        return;
      }
      _syncPlaybackPosition();
    });
  }

  void _syncPlaybackPosition() {
    final position = _player.position;
    if (_playbackDuration > Duration.zero && position >= _playbackDuration) {
      setState(() => _playbackPosition = _playbackDuration);
      return;
    }
    setState(() => _playbackPosition = position);
  }

  Future<void> _openQueue() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _QueueDialog(
          queue: _queue,
          currentIndex: _queueIndex,
          onPlayAt: (index) {
            Navigator.of(context).pop();
            unawaited(_playQueueIndex(index));
          },
          onRemoveAt: (index) {
            _removeFromQueue(index);
            setDialogState(() {});
          },
          onReorder: (oldIndex, newIndex) {
            _reorderQueue(oldIndex, newIndex);
            setDialogState(() {});
          },
          onClearUpcoming: () {
            _clearUpcomingQueue();
            setDialogState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _startSyncMode() async {
    if (_syncBusy) {
      return;
    }
    setState(() {
      _syncBusy = true;
      _syncStatus = '正在开启同步模式...';
    });
    try {
      final session = await _syncServer.start();
      final payload = SyncQrPayload.fromSession(session).toJsonText();
      if (!mounted) {
        return;
      }
      setState(() {
        _syncSession = session;
        _syncPayloadText = payload;
        _syncStatus = '同步模式已开启，等待手机连接';
        _syncBusy = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncStatus = '同步模式开启失败：$error';
        _syncBusy = false;
      });
    }
  }

  Future<void> _stopSyncMode() async {
    if (_syncBusy) {
      return;
    }
    setState(() {
      _syncBusy = true;
      _syncStatus = '正在关闭同步模式...';
    });
    try {
      await _syncServer.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _syncSession = null;
        _syncPayloadText = null;
        _syncStatus = '同步模式未开启';
        _syncBusy = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncStatus = '同步模式关闭失败：$error';
        _syncBusy = false;
      });
    }
  }

  Future<String?> _askForName({
    required String title,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space, control: true): () {
          if (_nowPlaying != null) {
            unawaited(_togglePlayback());
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () {
          if (_nowPlaying != null) {
            unawaited(_previousTrack());
          }
        },
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
        ): () {
          if (_nowPlaying != null) {
            unawaited(_nextTrack());
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () {
          if (_nowPlaying != null) {
            unawaited(_seekRelative(const Duration(seconds: -5)));
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () {
          if (_nowPlaying != null) {
            unawaited(_seekRelative(const Duration(seconds: 5)));
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          bottomNavigationBar: SafeArea(
            top: false,
            child: _PlayerBar(
              song: _nowPlaying,
              status: _status,
              position: _playbackPosition,
              duration: _playbackDuration,
              isPaused: _isPlaybackPaused,
              onTogglePlayback: _nowPlaying == null ? null : _togglePlayback,
              onPrevious: _nowPlaying == null ? null : _previousTrack,
              onNext: _nowPlaying == null ? null : _nextTrack,
              onStop: _stopPlayback,
              onSeek: _nowPlaying == null ? null : _seekPlayback,
              playbackMode: _playbackMode,
              onSelectPlaybackMode: _setPlaybackMode,
              queueLength: _queue.length,
              onOpenQueue: _openQueue,
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final extended = constraints.maxWidth >= 1050;
              return Row(
                children: [
                  NavigationRail(
                    extended: extended,
                    minWidth: 76,
                    minExtendedWidth: 216,
                    useIndicator: true,
                    groupAlignment: -0.78,
                    selectedIndex: _page.index,
                    onDestinationSelected: (index) {
                      setState(() => _page = _WindowsPage.values[index]);
                    },
                    leading: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 28, 18, 32),
                      child: extended
                          ? const Text('壹加音乐', style: TextStyle(fontSize: 20))
                          : const Icon(Icons.graphic_eq),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.library_music_outlined),
                        selectedIcon: Icon(Icons.library_music),
                        label: Text('音乐库'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.add_circle_outline),
                        selectedIcon: Icon(Icons.add_circle),
                        label: Text('添加歌曲'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.wifi_tethering_outlined),
                        selectedIcon: Icon(Icons.wifi_tethering),
                        label: Text('Wi-Fi 同步'),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1, color: _AppColors.outline),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        constraints.maxWidth >= 1050 ? 32 : 20,
                        28,
                        constraints.maxWidth >= 1050 ? 32 : 20,
                        24,
                      ),
                      child: _buildPage(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPage() {
    return switch (_page) {
      _WindowsPage.library => _buildLibraryPage(),
      _WindowsPage.import => _buildImportPage(),
      _WindowsPage.sync => _buildSyncPage(),
    };
  }

  Widget _buildLibraryPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          title: '音乐库',
          subtitle: '${_songs.length} 首歌曲 · ${_playlists.length} 个歌单',
          actions: [
            FilledButton.icon(
              onPressed: () => setState(() => _page = _WindowsPage.import),
              icon: const Icon(Icons.add),
              label: const Text('添加歌曲'),
            ),
            IconButton(
              tooltip: 'Wi-Fi 同步',
              onPressed: () => setState(() => _page = _WindowsPage.sync),
              icon: const Icon(Icons.wifi_tethering),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SearchField(
          controller: _searchController,
          onChanged: (_) => _reloadAll(),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final songList = _SongList(
                title: '全部歌曲',
                songs: _songs,
                nowPlayingId: _nowPlaying?.id,
                trailingBuilder: (song) => PopupMenuButton<_LibrarySongAction>(
                  tooltip: '更多操作',
                  onSelected: (action) {
                    switch (action) {
                      case _LibrarySongAction.playNext:
                        _enqueue(song, playNext: true);
                        break;
                      case _LibrarySongAction.addToQueue:
                        _enqueue(song, playNext: false);
                        break;
                      case _LibrarySongAction.addToPlaylist:
                        _addSongToPlaylist(song);
                        break;
                      case _LibrarySongAction.removeFromLibrary:
                        unawaited(_removeSongFromLibrary(song));
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _LibrarySongAction.playNext,
                      child: Text('播放下一首'),
                    ),
                    PopupMenuItem(
                      value: _LibrarySongAction.addToQueue,
                      child: Text('加入播放队列'),
                    ),
                    PopupMenuItem(
                      value: _LibrarySongAction.addToPlaylist,
                      child: Text('加入当前歌单'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: _LibrarySongAction.removeFromLibrary,
                      child: Text('从全部歌曲移除'),
                    ),
                  ],
                ),
                onPlay: (song) => _playSong(song, context: _songs),
              );
              final playlists = _PlaylistPanel(
                playlists: _playlists,
                selected: _selectedPlaylist,
                selectedSongs: _playlistSongs,
                onSelect: (playlist) {
                  _selectedPlaylist = playlist;
                  _reloadAll();
                },
                onCreate: _createPlaylist,
                onRename: _renamePlaylist,
                onDelete: _deletePlaylist,
                onRemoveSong: _removeSongFromPlaylist,
                onPlaySong: (song) => _playSong(song, context: _playlistSongs),
                onPlayNext: (song) => _enqueue(song, playNext: true),
                onAddToQueue: (song) => _enqueue(song, playNext: false),
                nowPlayingId: _nowPlaying?.id,
              );
              if (constraints.maxWidth < 820) {
                return Column(
                  children: [
                    Expanded(flex: 3, child: songList),
                    const SizedBox(height: 16),
                    Expanded(flex: 2, child: playlists),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 3, child: songList),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: playlists),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildImportPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(title: '添加歌曲', subtitle: '导入后会复制到本应用音乐库，不会移动原始文件'),
        const SizedBox(height: 20),
        _Toolbar(
          busy: _busy,
          libraryPath: widget.library.rootPath,
          onImportFiles: _importFiles,
          onImportFolder: _importFolder,
        ),
        const SizedBox(height: 16),
        _ImportSummary(result: _lastImportResult),
        const SizedBox(height: 16),
        Expanded(
          child: _SongList(
            title: '待整理音频',
            songs: _pendingSongs,
            nowPlayingId: _nowPlaying?.id,
            onPlay: (song) => _playSong(song, context: _pendingSongs),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageHeader(title: 'Wi-Fi 同步', subtitle: '让手机扫描二维码后同步整张歌单'),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            child: _SyncPanel(
              busy: _syncBusy,
              status: _syncStatus,
              session: _syncSession,
              payloadText: _syncPayloadText,
              onStart: _startSyncMode,
              onStop: _stopSyncMode,
            ),
          ),
        ),
      ],
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: _AppColors.secondaryText),
        ),
      ],
    );
    final actionRow = Wrap(spacing: 8, runSpacing: 8, children: actions);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (actions.isEmpty) {
          return heading;
        }
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 16), actionRow],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            actionRow,
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.busy,
    required this.libraryPath,
    required this.onImportFiles,
    required this.onImportFolder,
  });

  final bool busy;
  final String libraryPath;
  final VoidCallback onImportFiles;
  final VoidCallback onImportFolder;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AppColors.surface,
        border: Border.all(color: _AppColors.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onImportFiles,
                  icon: const Icon(Icons.audio_file),
                  label: const Text('导入音频文件'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onImportFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('导入文件夹'),
                ),
                if (busy)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('音乐库目录：$libraryPath'),
          ],
        ),
      ),
    );
  }
}

class _PlayerBar extends StatefulWidget {
  const _PlayerBar({
    required this.song,
    required this.status,
    required this.position,
    required this.duration,
    required this.isPaused,
    required this.onTogglePlayback,
    required this.onPrevious,
    required this.onNext,
    required this.onStop,
    required this.onSeek,
    required this.playbackMode,
    required this.onSelectPlaybackMode,
    required this.queueLength,
    required this.onOpenQueue,
  });

  final Song? song;
  final String status;
  final Duration position;
  final Duration duration;
  final bool isPaused;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onStop;
  final ValueChanged<Duration>? onSeek;
  final _PlaybackMode playbackMode;
  final ValueChanged<_PlaybackMode> onSelectPlaybackMode;
  final int queueLength;
  final VoidCallback onOpenQueue;

  @override
  State<_PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<_PlayerBar> {
  double? _dragValue;

  @override
  void didUpdateWidget(covariant _PlayerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song?.id != widget.song?.id) {
      _dragValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final enabled = song != null;
    final maxMs = widget.duration.inMilliseconds;
    final currentMs =
        _dragValue ?? widget.position.inMilliseconds.clamp(0, maxMs).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AppColors.surface,
        border: const Border(top: BorderSide(color: _AppColors.outline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          song == null
                              ? Icons.music_note_outlined
                              : Icons.music_note,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song?.title ?? '选择一首歌曲开始播放',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song == null
                                    ? widget.status
                                    : '${song.artist} · ${song.album}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '上一首',
                          onPressed: widget.onPrevious,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        IconButton(
                          tooltip: widget.isPaused ? '继续播放' : '暂停播放',
                          iconSize: 42,
                          onPressed: widget.onTogglePlayback,
                          style: IconButton.styleFrom(
                            backgroundColor: _AppColors.berry,
                            foregroundColor: _AppColors.primaryText,
                            minimumSize: const Size(54, 54),
                          ),
                          icon: Icon(
                            widget.isPaused
                                ? Icons.play_circle_filled
                                : Icons.pause_circle_filled,
                          ),
                        ),
                        IconButton(
                          tooltip: '下一首',
                          onPressed: widget.onNext,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PopupMenuButton<_PlaybackMode>(
                          tooltip:
                              '播放模式：${_playbackModeLabel(widget.playbackMode)}',
                          icon: Icon(_playbackModeIcon(widget.playbackMode)),
                          onSelected: widget.onSelectPlaybackMode,
                          itemBuilder: (context) => [
                            for (final mode in _PlaybackMode.values)
                              CheckedPopupMenuItem(
                                value: mode,
                                checked: mode == widget.playbackMode,
                                child: Text(_playbackModeLabel(mode)),
                              ),
                          ],
                        ),
                        IconButton(
                          tooltip: '播放队列（${widget.queueLength}）',
                          onPressed: widget.onOpenQueue,
                          icon: Badge(
                            isLabelVisible: widget.queueLength > 0,
                            label: Text('${widget.queueLength}'),
                            child: const Icon(Icons.queue_music_outlined),
                          ),
                        ),
                        IconButton(
                          tooltip: '停止播放',
                          onPressed: enabled ? widget.onStop : null,
                          icon: const Icon(Icons.stop_circle_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  _formatDuration(Duration(milliseconds: currentMs.round())),
                ),
                Expanded(
                  child: Slider(
                    value: maxMs == 0 ? 0 : currentMs.toDouble(),
                    max: maxMs == 0 ? 1 : maxMs.toDouble(),
                    onChanged: widget.onSeek == null || maxMs == 0
                        ? null
                        : (value) {
                            setState(() => _dragValue = value);
                          },
                    onChangeEnd: widget.onSeek == null || maxMs == 0
                        ? null
                        : (value) {
                            setState(() => _dragValue = null);
                            widget.onSeek!(
                              Duration(milliseconds: value.round()),
                            );
                          },
                  ),
                ),
                Text(maxMs == 0 ? '--:--' : _formatDuration(widget.duration)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

String _playbackModeLabel(_PlaybackMode mode) {
  return switch (mode) {
    _PlaybackMode.sequence => '顺序播放',
    _PlaybackMode.repeatAll => '列表循环',
    _PlaybackMode.repeatOne => '单曲循环',
    _PlaybackMode.shuffle => '随机播放',
  };
}

IconData _playbackModeIcon(_PlaybackMode mode) {
  return switch (mode) {
    _PlaybackMode.sequence => Icons.format_list_numbered,
    _PlaybackMode.repeatAll => Icons.repeat,
    _PlaybackMode.repeatOne => Icons.repeat_one,
    _PlaybackMode.shuffle => Icons.shuffle,
  };
}

class _QueueDialog extends StatelessWidget {
  const _QueueDialog({
    required this.queue,
    required this.currentIndex,
    required this.onPlayAt,
    required this.onRemoveAt,
    required this.onReorder,
    required this.onClearUpcoming,
  });

  final List<Song> queue;
  final int currentIndex;
  final ValueChanged<int> onPlayAt;
  final ValueChanged<int> onRemoveAt;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onClearUpcoming;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      alignment: Alignment.centerRight,
      insetPadding: const EdgeInsets.only(left: 360, top: 18, bottom: 18),
      backgroundColor: _AppColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        ),
      ),
      title: Row(
        children: [
          const Icon(Icons.queue_music),
          const SizedBox(width: 8),
          Text('播放队列（${queue.length}）'),
        ],
      ),
      content: SizedBox(
        width: 420,
        height: MediaQuery.sizeOf(context).height - 160,
        child: queue.isEmpty
            ? const Center(child: Text('播放队列为空'))
            : ReorderableListView.builder(
                itemCount: queue.length,
                onReorderItem: onReorder,
                itemBuilder: (context, index) {
                  final song = queue[index];
                  final isCurrent = index == currentIndex;
                  return ListTile(
                    key: ValueKey(song.id),
                    selected: isCurrent,
                    leading: Icon(
                      isCurrent ? Icons.equalizer : Icons.drag_handle,
                    ),
                    title: Text(song.title),
                    subtitle: Text('${song.artist} · ${song.album}'),
                    onTap: () => onPlayAt(index),
                    trailing: IconButton(
                      tooltip: isCurrent ? '当前正在播放' : '从队列移除',
                      onPressed: isCurrent ? null : () => onRemoveAt(index),
                      icon: const Icon(Icons.close),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: queue.length > 1 ? onClearUpcoming : null,
          child: const Text('清空待播放'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class _SyncPanel extends StatelessWidget {
  const _SyncPanel({
    required this.busy,
    required this.status,
    required this.session,
    required this.payloadText,
    required this.onStart,
    required this.onStop,
  });

  final bool busy;
  final String status;
  final SyncSession? session;
  final String? payloadText;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final active = session != null && payloadText != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AppColors.surface,
        border: Border.all(color: _AppColors.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Wi-Fi 同步模式',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      FilledButton.icon(
                        onPressed: busy || active ? null : onStart,
                        icon: const Icon(Icons.sync),
                        label: const Text('开启同步模式'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy || !active ? null : onStop,
                        icon: const Icon(Icons.close),
                        label: const Text('关闭同步模式'),
                      ),
                      if (busy)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(status),
                  if (session != null) ...[
                    const SizedBox(height: 8),
                    Text('连接地址：http://${session!.host}:${session!.port}'),
                    const SizedBox(height: 4),
                    Text(
                      '连接码：${session!.connectCode}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                  if (payloadText != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      payloadText!,
                      maxLines: 3,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (payloadText != null) ...[
              const SizedBox(width: 16),
              QrImageView(
                data: payloadText!,
                version: QrVersions.auto,
                size: 156,
                backgroundColor: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.search),
        labelText: '搜索歌曲、歌手、专辑、原始文件名、歌单',
      ),
    );
  }
}

class _ImportSummary extends StatelessWidget {
  const _ImportSummary({required this.result});

  final ImportResult? result;

  @override
  Widget build(BuildContext context) {
    if (result == null) {
      return const SizedBox.shrink();
    }
    final value = result!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AppColors.berrySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '上次导入：成功 ${value.importedCount} 首，跳过 ${value.skippedFiles.length} 个，失败 ${value.failedFiles.length} 个，待整理 ${value.pendingReviewCount} 首',
        ),
      ),
    );
  }
}

class _PlaylistPanel extends StatelessWidget {
  const _PlaylistPanel({
    required this.playlists,
    required this.selected,
    required this.selectedSongs,
    required this.onSelect,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    required this.onRemoveSong,
    required this.onPlaySong,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.nowPlayingId,
  });

  final List<Playlist> playlists;
  final Playlist? selected;
  final List<Song> selectedSongs;
  final ValueChanged<Playlist> onSelect;
  final VoidCallback onCreate;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final ValueChanged<Song> onRemoveSong;
  final ValueChanged<Song> onPlaySong;
  final ValueChanged<Song> onPlayNext;
  final ValueChanged<Song> onAddToQueue;
  final String? nowPlayingId;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('歌单', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            tooltip: '新建歌单',
            onPressed: onCreate,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '重命名歌单',
            onPressed: selected == null ? null : onRename,
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: '删除歌单',
            onPressed: selected == null ? null : onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AppColors.surface,
        border: Border.all(color: _AppColors.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < 180) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      playlists.isEmpty
                          ? '暂无歌单'
                          : '已显示 ${playlists.length} 个歌单',
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Flexible(
                flex: 1,
                child: playlists.isEmpty
                    ? const Center(child: Text('暂无歌单'))
                    : ListView.builder(
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          return ListTile(
                            dense: true,
                            selected: playlist.id == selected?.id,
                            title: Text(playlist.name),
                            onTap: () => onSelect(playlist),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  selected == null
                      ? '歌单内容'
                      : '${selected!.name}（${selectedSongs.length}）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Flexible(
                flex: 2,
                child: selectedSongs.isEmpty
                    ? const Center(child: Text('当前歌单暂无歌曲'))
                    : ListView.separated(
                        itemBuilder: (context, index) {
                          final song = selectedSongs[index];
                          return GestureDetector(
                            onDoubleTap: () => onPlaySong(song),
                            child: ListTile(
                              dense: true,
                              selected: song.id == nowPlayingId,
                              title: Text(song.title),
                              subtitle: Text(song.artist),
                              leading: IconButton(
                                tooltip: '播放',
                                icon: Icon(
                                  song.id == nowPlayingId
                                      ? Icons.equalizer
                                      : Icons.play_arrow,
                                ),
                                onPressed: () => onPlaySong(song),
                              ),
                              trailing: PopupMenuButton<_PlaylistSongAction>(
                                tooltip: '更多操作',
                                onSelected: (action) {
                                  switch (action) {
                                    case _PlaylistSongAction.playNext:
                                      onPlayNext(song);
                                      break;
                                    case _PlaylistSongAction.addToQueue:
                                      onAddToQueue(song);
                                      break;
                                    case _PlaylistSongAction.removeFromPlaylist:
                                      onRemoveSong(song);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: _PlaylistSongAction.playNext,
                                    child: Text('播放下一首'),
                                  ),
                                  PopupMenuItem(
                                    value: _PlaylistSongAction.addToQueue,
                                    child: Text('加入播放队列'),
                                  ),
                                  PopupMenuDivider(),
                                  PopupMenuItem(
                                    value:
                                        _PlaylistSongAction.removeFromPlaylist,
                                    child: Text('从歌单移除'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemCount: selectedSongs.length,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SongList extends StatelessWidget {
  const _SongList({
    required this.title,
    required this.songs,
    this.nowPlayingId,
    this.trailingBuilder,
    this.onPlay,
  });

  final String title;
  final List<Song> songs;
  final String? nowPlayingId;
  final Widget Function(Song song)? trailingBuilder;
  final ValueChanged<Song>? onPlay;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AppColors.surface,
        border: Border.all(color: _AppColors.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '$title（${songs.length}）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: songs.isEmpty
                ? const Center(child: Text('暂无内容'))
                : ListView.separated(
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      final isPlaying = song.id == nowPlayingId;
                      return GestureDetector(
                        onDoubleTap: onPlay == null
                            ? null
                            : () => onPlay!(song),
                        child: ListTile(
                          dense: true,
                          selected: isPlaying,
                          title: Text(song.title),
                          subtitle: Text(
                            '${song.artist} · ${song.album} · ${song.format.extension.toUpperCase()}',
                          ),
                          leading: IconButton(
                            tooltip: '播放',
                            icon: Icon(
                              isPlaying ? Icons.equalizer : Icons.play_arrow,
                            ),
                            onPressed: onPlay == null
                                ? null
                                : () => onPlay!(song),
                          ),
                          trailing:
                              trailingBuilder?.call(song) ??
                              (song.isPendingReview
                                  ? const Chip(label: Text('待整理'))
                                  : null),
                        ),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemCount: songs.length,
                  ),
          ),
        ],
      ),
    );
  }
}
