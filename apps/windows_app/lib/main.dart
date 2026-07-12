import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';

import 'audio_import_service.dart';
import 'sync_server.dart';
import 'windows_audio_player.dart';

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
    return MaterialApp(
      title: '壹加音乐',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A68)),
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

class _WindowsHomePageState extends State<WindowsHomePage> {
  late final AudioImportService _importService;
  late final WindowsAudioPlayer _player;
  late final WindowsSyncServer _syncServer;
  final _dialog = WindowsFileDialog();
  final _searchController = TextEditingController();

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
    _reloadAll();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
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

  Future<void> _playSong(Song song) async {
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
      _progressTimer?.cancel();
      setState(() {
        _nowPlaying = null;
        _playbackPosition = _playbackDuration;
        _isPlaybackPaused = false;
        _status = '播放结束';
      });
      return;
    }
    setState(() => _playbackPosition = position);
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
    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _PlayerBar(
            song: _nowPlaying,
            status: _status,
            position: _playbackPosition,
            duration: _playbackDuration,
            isPaused: _isPlaybackPaused,
            onTogglePlayback: _nowPlaying == null ? null : _togglePlayback,
            onStop: _stopPlayback,
            onSeek: _nowPlaying == null ? null : _seekPlayback,
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final extended = constraints.maxWidth >= 1050;
          return Row(
            children: [
              NavigationRail(
                extended: extended,
                minExtendedWidth: 188,
                selectedIndex: _page.index,
                onDestinationSelected: (index) {
                  setState(() => _page = _WindowsPage.values[index]);
                },
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
              const VerticalDivider(width: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _buildPage(),
                ),
              ),
            ],
          );
        },
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
                trailingBuilder: (song) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '加入当前歌单',
                      icon: const Icon(Icons.playlist_add),
                      onPressed: () => _addSongToPlaylist(song),
                    ),
                    IconButton(
                      tooltip: '从全部歌曲移除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeSongFromLibrary(song),
                    ),
                  ],
                ),
                onPlay: _playSong,
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
                onPlaySong: _playSong,
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
            onPlay: _playSong,
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 16),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
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
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
    required this.onStop,
    required this.onSeek,
  });

  final Song? song;
  final String status;
  final Duration position;
  final Duration duration;
  final bool isPaused;
  final VoidCallback? onTogglePlayback;
  final VoidCallback onStop;
  final ValueChanged<Duration>? onSeek;

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
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  song == null ? Icons.music_note_outlined : Icons.music_note,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
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
                      const SizedBox(height: 4),
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
                IconButton(
                  tooltip: widget.isPaused ? '继续播放' : '暂停播放',
                  iconSize: 34,
                  onPressed: widget.onTogglePlayback,
                  icon: Icon(
                    widget.isPaused
                        ? Icons.play_circle_filled
                        : Icons.pause_circle_filled,
                  ),
                ),
                IconButton(
                  tooltip: '停止播放',
                  onPressed: enabled ? widget.onStop : null,
                  icon: const Icon(Icons.stop_circle_outlined),
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
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
        border: Border.all(color: Theme.of(context).dividerColor),
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
                          return ListTile(
                            dense: true,
                            title: Text(song.title),
                            subtitle: Text(song.artist),
                            leading: IconButton(
                              tooltip: '播放',
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () => onPlaySong(song),
                            ),
                            trailing: IconButton(
                              tooltip: '从歌单移除',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => onRemoveSong(song),
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
    this.trailingBuilder,
    this.onPlay,
  });

  final String title;
  final List<Song> songs;
  final Widget Function(Song song)? trailingBuilder;
  final ValueChanged<Song>? onPlay;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
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
                      return ListTile(
                        dense: true,
                        title: Text(song.title),
                        subtitle: Text(
                          '${song.artist} · ${song.album} · ${song.format.extension.toUpperCase()}',
                        ),
                        leading: IconButton(
                          tooltip: '播放',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: onPlay == null
                              ? null
                              : () => onPlay!(song),
                        ),
                        trailing:
                            trailingBuilder?.call(song) ??
                            (song.isPendingReview
                                ? const Chip(label: Text('待整理'))
                                : null),
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
