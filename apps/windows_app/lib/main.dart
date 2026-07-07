import 'package:flutter/material.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';
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
  SyncSession? _syncSession;
  String? _syncPayloadText;
  String _status = '准备就绪';
  String _syncStatus = '同步模式未开启';
  bool _busy = false;
  bool _syncBusy = false;

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
    _syncServer.stop();
    _player.stop();
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

  Future<void> _playSong(Song song) async {
    try {
      await _player.play(song);
      if (!mounted) {
        return;
      }
      setState(() {
        _nowPlaying = song;
        _status = '正在播放：${song.title}';
      });
    } catch (error) {
      setState(() => _status = '播放失败：$error');
    }
  }

  void _pausePlayback() {
    try {
      _player.pause();
      setState(() => _status = '已暂停：${_nowPlaying?.title ?? ''}');
    } catch (error) {
      setState(() => _status = '暂停失败：$error');
    }
  }

  void _resumePlayback() {
    try {
      _player.resume();
      setState(() => _status = '继续播放：${_nowPlaying?.title ?? ''}');
    } catch (error) {
      setState(() => _status = '继续播放失败：$error');
    }
  }

  void _stopPlayback() {
    try {
      _player.stop();
      setState(() {
        _nowPlaying = null;
        _status = '已停止播放';
      });
    } catch (error) {
      setState(() => _status = '停止失败：$error');
    }
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
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
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
      appBar: AppBar(title: const Text('壹加音乐 - Windows 主库')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(
              busy: _busy,
              libraryPath: widget.library.rootPath,
              status: _status,
              nowPlaying: _nowPlaying?.title,
              onImportFiles: _importFiles,
              onImportFolder: _importFolder,
              onPause: _pausePlayback,
              onResume: _resumePlayback,
              onStop: _stopPlayback,
            ),
            const SizedBox(height: 16),
            _SyncPanel(
              busy: _syncBusy,
              status: _syncStatus,
              session: _syncSession,
              payloadText: _syncPayloadText,
              onStart: _startSyncMode,
              onStop: _stopSyncMode,
            ),
            const SizedBox(height: 16),
            _SearchField(
              controller: _searchController,
              onChanged: (_) => _reloadAll(),
            ),
            const SizedBox(height: 16),
            _ImportSummary(result: _lastImportResult),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _SongList(
                      title: '全部歌曲',
                      songs: _songs,
                      trailingBuilder: (song) => IconButton(
                        tooltip: '加入当前歌单',
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () => _addSongToPlaylist(song),
                      ),
                      onPlay: _playSong,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _PlaylistPanel(
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
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _SongList(
                      title: '待整理音频',
                      songs: _pendingSongs,
                      onPlay: _playSong,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.busy,
    required this.libraryPath,
    required this.status,
    required this.nowPlaying,
    required this.onImportFiles,
    required this.onImportFolder,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final bool busy;
  final String libraryPath;
  final String status;
  final String? nowPlaying;
  final VoidCallback onImportFiles;
  final VoidCallback onImportFolder;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

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
                OutlinedButton.icon(
                  onPressed: nowPlaying == null ? null : onPause,
                  icon: const Icon(Icons.pause),
                  label: const Text('暂停'),
                ),
                OutlinedButton.icon(
                  onPressed: nowPlaying == null ? null : onResume,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('继续'),
                ),
                OutlinedButton.icon(
                  onPressed: nowPlaying == null ? null : onStop,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
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
            const SizedBox(height: 6),
            Text('当前播放：${nowPlaying ?? '无'}'),
            const SizedBox(height: 6),
            Text(status, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
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
                          onPressed: onPlay == null ? null : () => onPlay!(song),
                        ),
                        trailing: trailingBuilder?.call(song) ??
                            (song.isPendingReview
                                ? const Chip(label: Text('待整理'))
                                : null),
                      );
                    },
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemCount: songs.length,
                  ),
          ),
        ],
      ),
    );
  }
}
