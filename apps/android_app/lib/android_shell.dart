import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'android_audio_player.dart';
import 'android_library.dart';
import 'sync_client.dart';

class AndroidMusicApp extends StatelessWidget {
  const AndroidMusicApp({
    required this.database,
    required this.library,
    super.key,
  });

  final MusicDatabase database;
  final AndroidMusicLibraryLocation library;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _AndroidColors.forest,
      brightness: Brightness.light,
      surface: _AndroidColors.surface,
    );
    return MaterialApp(
      title: '壹加音乐',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme.copyWith(
          primary: _AndroidColors.forest,
          onPrimary: Colors.white,
          secondary: _AndroidColors.mint,
          surfaceContainerHighest: _AndroidColors.softMint,
        ),
        scaffoldBackgroundColor: _AndroidColors.canvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: _AndroidColors.canvas,
          foregroundColor: _AndroidColors.ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: _AndroidColors.surface,
          indicatorColor: _AndroidColors.softMint,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _AndroidColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _AndroidColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _AndroidColors.line),
          ),
        ),
      ),
      home: _AndroidHomePage(database: database, library: library),
    );
  }
}

class _AndroidHomePage extends StatefulWidget {
  const _AndroidHomePage({required this.database, required this.library});

  final MusicDatabase database;
  final AndroidMusicLibraryLocation library;

  @override
  State<_AndroidHomePage> createState() => _AndroidHomePageState();
}

class _AndroidHomePageState extends State<_AndroidHomePage> {
  late final AndroidSyncClient _syncClient;
  late final AndroidAudioPlayer _player;
  final _payloadController = TextEditingController();
  final _searchController = TextEditingController();

  SyncQrPayload? _connectedPayload;
  List<RemotePlaylist> _remotePlaylists = const [];
  List<Playlist> _localPlaylists = const [];
  List<Song> _localSongs = const [];
  List<Song> _selectedPlaylistSongs = const [];
  List<Song> _playQueue = const [];
  Playlist? _selectedLocalPlaylist;
  Song? _nowPlaying;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  String _status = '连接电脑后，即可把整张歌单保存到本机。';
  bool _busy = false;
  bool _isPlaying = false;
  bool _seekGestureActive = false;
  bool _showManualConnect = false;
  int _tabIndex = 0;
  int _queueIndex = -1;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<void>? _completeSubscription;

  @override
  void initState() {
    super.initState();
    _syncClient = AndroidSyncClient();
    _player = AndroidAudioPlayer();
    _positionSubscription = _player.positionStream.listen((position) {
      if (mounted && !_seekGestureActive) {
        setState(() => _playbackPosition = position);
      }
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (mounted) {
        setState(() => _playbackDuration = duration);
      }
    });
    _playingSubscription = _player.playingStream.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
      }
    });
    _completeSubscription = _player.completeStream.listen((_) => _playNext());
    _reloadLocal();
  }

  @override
  void dispose() {
    _syncClient.dispose();
    _player.dispose();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _completeSubscription?.cancel();
    _payloadController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _reloadLocal({String? selectPlaylistId}) {
    final keyword = _searchController.text.trim();
    final playlists = widget.database.search.searchPlaylists(
      keyword,
      syncedOnly: true,
    );
    final wantedId = selectPlaylistId ?? _selectedLocalPlaylist?.id;
    Playlist? selected;
    for (final playlist in playlists) {
      if (playlist.id == wantedId) {
        selected = playlist;
        break;
      }
    }
    selected ??= playlists.isEmpty ? null : playlists.first;
    final songs = widget.database.search.searchSongs(keyword, syncedOnly: true);
    final selectedSongs = selected == null
        ? const <Song>[]
        : widget.database.playlists
              .songsForPlaylist(selected.id)
              .where(_isSyncedSong)
              .toList();
    if (!mounted) {
      return;
    }
    setState(() {
      _localPlaylists = playlists;
      _localSongs = songs;
      _selectedLocalPlaylist = selected;
      _selectedPlaylistSongs = selectedSongs;
    });
  }

  bool _isSyncedSong(Song song) =>
      widget.database.sync.findCacheForSong(song.id)?.status ==
      SyncCacheStatus.synced;

  Future<void> _pastePayload() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text == null || text.isEmpty) {
      return;
    }
    setState(() {
      _showManualConnect = true;
      _payloadController.text = text;
    });
  }

  Future<void> _scanPayload() async {
    if (_busy) {
      return;
    }
    final payloadText = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrScanPage()));
    if (!mounted || payloadText == null || payloadText.trim().isEmpty) {
      return;
    }
    await _connectWithPayloadText(payloadText.trim());
  }

  Future<void> _connectToWindows() =>
      _connectWithPayloadText(_payloadController.text.trim());

  Future<void> _connectWithPayloadText(String payloadText) async {
    if (_busy || payloadText.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在连接电脑端...';
    });
    try {
      final payload = SyncQrPayload.fromJsonText(payloadText);
      await _syncClient.connect(payload);
      final playlists = await _syncClient.fetchPlaylists(payload);
      if (!mounted) {
        return;
      }
      setState(() {
        _payloadController.text = payloadText;
        _connectedPayload = payload;
        _remotePlaylists = playlists;
        _busy = false;
        _status = playlists.isEmpty
            ? '已连接电脑端，但电脑端还没有可同步歌单。'
            : '已连接电脑端，找到 ${playlists.length} 张歌单。';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '连接失败：$error';
        });
      }
    }
  }

  Future<void> _syncPlaylist(RemotePlaylist playlist) async {
    final payload = _connectedPayload;
    if (_busy || payload == null) {
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在同步《${playlist.name}》...';
    });
    try {
      final result = await _syncClient.syncPlaylist(
        payload: payload,
        remotePlaylist: playlist,
        database: widget.database,
        library: widget.library,
      );
      if (!mounted) {
        return;
      }
      _searchController.clear();
      _reloadLocal(selectPlaylistId: playlist.id);
      final firstFailure = result.failureMessages.isEmpty
          ? ''
          : ' 首个失败：${result.failureMessages.first}';
      setState(() {
        _busy = false;
        _tabIndex = 0;
        _status = result.hasFailures
            ? '同步完成：本机已有 ${result.localSongCount} 首，失败 ${result.failedCount} 首。$firstFailure'
            : '同步完成：${playlist.name} 已保存，本机现有 ${result.localSongCount} 首歌曲。';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_status), behavior: SnackBarBehavior.floating),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '同步失败：$error';
        });
      }
    }
  }

  Future<void> _playSong(Song song, {List<Song>? queue}) async {
    final songs = List<Song>.unmodifiable(
      (queue == null || queue.isEmpty) ? _localSongs : queue,
    );
    final queueIndex = songs.indexWhere((item) => item.id == song.id);
    try {
      await _player.play(song);
      final measuredDuration = await _player.getDuration();
      if (!mounted) {
        return;
      }
      final importedDuration = song.durationMs == null
          ? Duration.zero
          : Duration(milliseconds: song.durationMs!);
      setState(() {
        _playQueue = songs;
        _queueIndex = queueIndex;
        _nowPlaying = song;
        _isPlaying = true;
        _playbackPosition = Duration.zero;
        _playbackDuration =
            measuredDuration != null && measuredDuration > Duration.zero
            ? measuredDuration
            : importedDuration;
        _status = '正在播放：${song.title}';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = '播放失败：$error');
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_nowPlaying == null) {
      return;
    }
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.resume();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = '播放状态切换失败：$error');
      }
    }
  }

  Future<void> _playPrevious() async {
    if (_playQueue.isEmpty) {
      return;
    }
    final index = _queueIndex <= 0 ? 0 : _queueIndex - 1;
    await _playSong(_playQueue[index], queue: _playQueue);
  }

  Future<void> _playNext() async {
    if (_playQueue.isEmpty || _queueIndex < 0) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _nowPlaying = null;
          _playbackPosition = Duration.zero;
        });
      }
      return;
    }
    final index = _queueIndex + 1;
    if (index >= _playQueue.length) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playbackPosition = Duration.zero;
          _status = '播放结束';
        });
      }
      return;
    }
    await _playSong(_playQueue[index], queue: _playQueue);
  }

  Future<void> _seekPlayback(Duration position) async {
    try {
      await _player.seek(position);
      if (mounted) {
        setState(() => _playbackPosition = position);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = '拖动进度失败：$error');
      }
    }
  }

  void _setSeekGestureActive(bool active) {
    _seekGestureActive = active;
  }

  Future<void> _confirmDeleteCache(Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除本地缓存？'),
        content: Text('《${song.title}》会从手机移除，电脑端的歌曲和歌单不会受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteLocalCache(song);
    }
  }

  Future<void> _deleteLocalCache(Song song) async {
    try {
      if (_nowPlaying?.id == song.id) {
        await _player.stop();
      }
      final file = File(song.localPath);
      if (await file.exists()) {
        await file.delete();
      }
      widget.database.sync.markDeleted(song.id, DateTime.now().toUtc());
      _reloadLocal();
      if (mounted) {
        setState(() {
          if (_nowPlaying?.id == song.id) {
            _nowPlaying = null;
            _isPlaying = false;
            _playbackPosition = Duration.zero;
            _playbackDuration = Duration.zero;
          }
          _status = '已删除本地缓存，电脑端不会受影响。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = '删除本地缓存失败：$error');
      }
    }
  }

  void _openNowPlaying() {
    final song = _nowPlaying;
    if (song == null) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _AndroidColors.surface,
      builder: (_) => _NowPlayingSheet(
        song: song,
        position: _playbackPosition,
        duration: _playbackDuration,
        positionStream: _player.positionStream.where(
          (_) => !_seekGestureActive,
        ),
        durationStream: _player.durationStream,
        isPlaying: _isPlaying,
        onPrevious: _playPrevious,
        onToggle: _togglePlayback,
        onNext: _playNext,
        onSeek: _seekPlayback,
        onSeekGestureChanged: _setSeekGestureActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _LibraryPage(
        controller: _searchController,
        songs: _localSongs,
        status: _status,
        onSearchChanged: (_) => _reloadLocal(),
        onPlay: (song) => _playSong(song, queue: _localSongs),
        onDelete: _confirmDeleteCache,
        onOpenSync: () => setState(() => _tabIndex = 2),
      ),
      _PlaylistPage(
        playlists: _localPlaylists,
        selected: _selectedLocalPlaylist,
        songs: _selectedPlaylistSongs,
        onSelect: (playlist) => _reloadLocal(selectPlaylistId: playlist.id),
        onPlay: (song) => _playSong(song, queue: _selectedPlaylistSongs),
        onDelete: _confirmDeleteCache,
        onOpenSync: () => setState(() => _tabIndex = 2),
      ),
      _SyncPage(
        controller: _payloadController,
        connected: _connectedPayload != null,
        busy: _busy,
        status: _status,
        playlists: _remotePlaylists,
        showManualConnect: _showManualConnect,
        onScan: _scanPayload,
        onPaste: _pastePayload,
        onConnect: _connectToWindows,
        onToggleManual: () =>
            setState(() => _showManualConnect = !_showManualConnect),
        onSync: _syncPlaylist,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const _BrandHeader(),
        actions: [
          IconButton(
            tooltip: '刷新本地音乐库',
            onPressed: _reloadLocal,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: _tabIndex, children: pages),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_nowPlaying != null)
            _MiniPlayer(
              song: _nowPlaying!,
              position: _playbackPosition,
              duration: _playbackDuration,
              isPlaying: _isPlaying,
              onTap: _openNowPlaying,
              onPrevious: _playPrevious,
              onToggle: _togglePlayback,
              onNext: _playNext,
              onSeek: _seekPlayback,
              onSeekGestureChanged: _setSeekGestureActive,
            ),
          NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (index) => setState(() => _tabIndex = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: '音乐库',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music_outlined),
                selectedIcon: Icon(Icons.queue_music),
                label: '歌单',
              ),
              NavigationDestination(
                icon: Icon(Icons.sync_outlined),
                selectedIcon: Icon(Icons.sync),
                label: '同步音乐',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/branding/yijia_music_logo.png',
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '壹加音乐',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _AndroidColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '你的离线随身音乐库',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _AndroidColors.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _LibraryPage extends StatelessWidget {
  const _LibraryPage({
    required this.controller,
    required this.songs,
    required this.status,
    required this.onSearchChanged,
    required this.onPlay,
    required this.onDelete,
    required this.onOpenSync,
  });

  final TextEditingController controller;
  final List<Song> songs;
  final String status;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Song> onPlay;
  final ValueChanged<Song> onDelete;
  final VoidCallback onOpenSync;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: controller,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: '搜索已同步的歌曲和歌手',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            children: [
              Text(
                '本地歌曲',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${songs.length} 首',
                style: const TextStyle(color: _AndroidColors.muted),
              ),
            ],
          ),
        ),
        Expanded(
          child: songs.isEmpty
              ? _EmptyLibrary(status: status, onOpenSync: onOpenSync)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: songs.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    indent: 68,
                    color: _AndroidColors.line,
                  ),
                  itemBuilder: (_, index) => _SongRow(
                    song: songs[index],
                    onPlay: () => onPlay(songs[index]),
                    onDelete: () => onDelete(songs[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _PlaylistPage extends StatelessWidget {
  const _PlaylistPage({
    required this.playlists,
    required this.selected,
    required this.songs,
    required this.onSelect,
    required this.onPlay,
    required this.onDelete,
    required this.onOpenSync,
  });

  final List<Playlist> playlists;
  final Playlist? selected;
  final List<Song> songs;
  final ValueChanged<Playlist> onSelect;
  final ValueChanged<Song> onPlay;
  final ValueChanged<Song> onDelete;
  final VoidCallback onOpenSync;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return _EmptyLibrary(
        status: '同步整张电脑歌单后，它会只保存在这台手机里。',
        onOpenSync: onOpenSync,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          child: Text(
            '已同步歌单',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, index) {
              final playlist = playlists[index];
              final active = playlist.id == selected?.id;
              return SizedBox(
                width: 156,
                child: Material(
                  color: active
                      ? _AndroidColors.softMint
                      : _AndroidColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelect(playlist),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.queue_music_rounded,
                            color: active
                                ? _AndroidColors.forest
                                : _AndroidColors.muted,
                          ),
                          const Spacer(),
                          Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            selected?.name ?? '歌单内容',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        if (songs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('这张歌单暂时没有可播放的本地歌曲。')),
          )
        else
          ...songs.map(
            (song) => _SongRow(
              song: song,
              onPlay: () => onPlay(song),
              onDelete: () => onDelete(song),
            ),
          ),
      ],
    );
  }
}

class _SyncPage extends StatelessWidget {
  const _SyncPage({
    required this.controller,
    required this.connected,
    required this.busy,
    required this.status,
    required this.playlists,
    required this.showManualConnect,
    required this.onScan,
    required this.onPaste,
    required this.onConnect,
    required this.onToggleManual,
    required this.onSync,
  });

  final TextEditingController controller;
  final bool connected;
  final bool busy;
  final String status;
  final List<RemotePlaylist> playlists;
  final bool showManualConnect;
  final VoidCallback onScan;
  final VoidCallback onPaste;
  final VoidCallback onConnect;
  final VoidCallback onToggleManual;
  final ValueChanged<RemotePlaylist> onSync;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        Text(
          '同步音乐',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          '同一 Wi-Fi 下，扫描电脑端二维码后按整张歌单下载到本机。',
          style: TextStyle(color: _AndroidColors.muted),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: busy ? null : onScan,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: _AndroidColors.forest,
          ),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('扫描电脑端二维码'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: busy ? null : onToggleManual,
          icon: const Icon(Icons.keyboard_rounded),
          label: Text(showManualConnect ? '收起手动连接' : '扫码失败？手动粘贴连接信息'),
        ),
        if (showManualConnect) ...[
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: '粘贴 Windows 端二维码内容'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onPaste,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('粘贴'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onConnect,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('连接电脑端'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _StatusBanner(text: status, busy: busy, connected: connected),
        if (playlists.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            '电脑端歌单',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...playlists.map(
            (playlist) => Material(
              color: _AndroidColors.surface,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(
                  Icons.playlist_play_rounded,
                  color: _AndroidColors.forest,
                ),
                title: Text(playlist.name),
                subtitle: Text('${playlist.songCount} 首歌曲'),
                trailing: FilledButton(
                  onPressed: busy ? null : () => onSync(playlist),
                  child: const Text('同步'),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.text,
    required this.busy,
    required this.connected,
  });

  final String text;
  final bool busy;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = busy
        ? _AndroidColors.gold
        : connected
        ? _AndroidColors.forest
        : _AndroidColors.muted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _AndroidColors.surface,
        border: Border.all(color: _AndroidColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              connected
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              color: color,
            ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.status, required this.onOpenSync});

  final String status;
  final VoidCallback onOpenSync;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: _AndroidColors.softMint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.library_music_outlined,
                size: 34,
                color: _AndroidColors.forest,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '手机里还没有同步音乐',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _AndroidColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onOpenSync,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('去同步音乐'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.onPlay,
    required this.onDelete,
  });

  final Song song;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _AndroidColors.softMint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: _AndroidColors.forest,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${song.artist} · ${song.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _AndroidColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_SongAction>(
                tooltip: '歌曲操作',
                onSelected: (action) {
                  if (action == _SongAction.deleteCache) {
                    onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _SongAction.deleteCache,
                    child: Text('删除本地缓存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SongAction { deleteCache }

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    required this.song,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.onTap,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.onSeek,
    required this.onSeekGestureChanged,
  });

  final Song song;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final Future<void> Function(Duration) onSeek;
  final ValueChanged<bool> onSeekGestureChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _AndroidColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          children: [
            Row(
              children: [
                InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _AndroidColors.softMint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: _AndroidColors.forest,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _AndroidColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '上一首',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton.filled(
                  tooltip: isPlaying ? '暂停' : '播放',
                  onPressed: onToggle,
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  tooltip: '下一首',
                  onPressed: onNext,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
            SizedBox(
              height: 32,
              child: _PlaybackSeekSlider(
                position: position,
                duration: duration,
                onSeek: onSeek,
                onSeekGestureChanged: onSeekGestureChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingSheet extends StatelessWidget {
  const _NowPlayingSheet({
    required this.song,
    required this.position,
    required this.duration,
    required this.positionStream,
    required this.durationStream,
    required this.isPlaying,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.onSeek,
    required this.onSeekGestureChanged,
  });

  final Song song;
  final Duration position;
  final Duration duration;
  final Stream<Duration> positionStream;
  final Stream<Duration> durationStream;
  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final Future<void> Function(Duration) onSeek;
  final ValueChanged<bool> onSeekGestureChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: _AndroidColors.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: 180,
              height: 180,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _AndroidColors.softMint,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.music_note_rounded,
                size: 72,
                color: _AndroidColors.forest,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              song.artist,
              style: const TextStyle(color: _AndroidColors.muted),
            ),
            const SizedBox(height: 18),
            StreamBuilder<Duration>(
              stream: positionStream,
              initialData: position,
              builder: (context, positionSnapshot) {
                final livePosition = positionSnapshot.data ?? position;
                return StreamBuilder<Duration>(
                  stream: durationStream,
                  initialData: duration,
                  builder: (context, durationSnapshot) {
                    final liveDuration = durationSnapshot.data ?? duration;
                    return Column(
                      children: [
                        _PlaybackSeekSlider(
                          position: livePosition,
                          duration: liveDuration,
                          onSeek: onSeek,
                          onSeekGestureChanged: onSeekGestureChanged,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(livePosition)),
                            Text(
                              liveDuration == Duration.zero
                                  ? '--:--'
                                  : _formatDuration(liveDuration),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 34,
                  tooltip: '上一首',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                const SizedBox(width: 20),
                IconButton.filled(
                  iconSize: 36,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(72, 72),
                    backgroundColor: _AndroidColors.forest,
                  ),
                  tooltip: isPlaying ? '暂停' : '播放',
                  onPressed: onToggle,
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 20),
                IconButton(
                  iconSize: 34,
                  tooltip: '下一首',
                  onPressed: onNext,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackSeekSlider extends StatefulWidget {
  const _PlaybackSeekSlider({
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onSeekGestureChanged,
  });

  final Duration position;
  final Duration duration;
  final Future<void> Function(Duration) onSeek;
  final ValueChanged<bool> onSeekGestureChanged;

  @override
  State<_PlaybackSeekSlider> createState() => _PlaybackSeekSliderState();
}

class _PlaybackSeekSliderState extends State<_PlaybackSeekSlider> {
  double? _previewValue;
  bool _dragging = false;

  @override
  void dispose() {
    if (_dragging) {
      widget.onSeekGestureChanged(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.duration.inMilliseconds;
    final enabled = max > 0;
    final position = widget.position.inMilliseconds.clamp(0, max).toDouble();
    final value = (_previewValue ?? position).clamp(0, max).toDouble();

    return Slider(
      value: enabled ? value : 0,
      max: enabled ? max.toDouble() : 1,
      onChangeStart: enabled ? _startDrag : null,
      onChanged: enabled ? _updatePreview : null,
      onChangeEnd: enabled
          ? (next) {
              _updatePreview(next);
              unawaited(_commitSeek(next));
            }
          : null,
    );
  }

  void _startDrag(double value) {
    if (!_dragging) {
      _dragging = true;
      widget.onSeekGestureChanged(true);
    }
    _updatePreview(value);
  }

  void _updatePreview(double value) {
    setState(() => _previewValue = value);
  }

  Future<void> _commitSeek(double value) async {
    try {
      await widget.onSeek(Duration(milliseconds: value.round()));
    } finally {
      if (_dragging) {
        _dragging = false;
        widget.onSeekGestureChanged(false);
      }
      if (mounted) {
        setState(() => _previewValue = null);
      }
    }
  }
}

class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _handled = false;

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      try {
        SyncQrPayload.fromJsonText(value);
      } catch (_) {
        continue;
      }
      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描电脑端同步二维码')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _handleDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '无法打开摄像头：${error.errorDetails?.message ?? error.errorCode.message}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: const Text(
                '请将 Windows 端的二维码放入取景框',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

abstract final class _AndroidColors {
  static const canvas = Color(0xFFF2F4F0);
  static const surface = Color(0xFFFCFDF9);
  static const softMint = Color(0xFFDCECE2);
  static const mint = Color(0xFF77B79A);
  static const forest = Color(0xFF2C664C);
  static const ink = Color(0xFF183128);
  static const muted = Color(0xFF65756D);
  static const line = Color(0xFFD0D8D1);
  static const gold = Color(0xFFC99528);
}
