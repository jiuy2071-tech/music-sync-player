import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';

import 'android_audio_player.dart';
import 'android_library.dart';
import 'sync_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = await AndroidMusicLibraryLocation.resolve();
  await library.ensureReady();
  final database = MusicDatabase.open(library.databasePath);
  runApp(AndroidMusicApp(database: database, library: library));
}

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
    return MaterialApp(
      title: '壹加音乐',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A68)),
        useMaterial3: true,
      ),
      home: AndroidHomePage(database: database, library: library),
    );
  }
}

class AndroidHomePage extends StatefulWidget {
  const AndroidHomePage({
    required this.database,
    required this.library,
    super.key,
  });

  final MusicDatabase database;
  final AndroidMusicLibraryLocation library;

  @override
  State<AndroidHomePage> createState() => _AndroidHomePageState();
}

class _AndroidHomePageState extends State<AndroidHomePage> {
  late final AndroidSyncClient _syncClient;
  late final AndroidAudioPlayer _player;
  final _payloadController = TextEditingController();
  final _searchController = TextEditingController();

  SyncQrPayload? _connectedPayload;
  List<RemotePlaylist> _remotePlaylists = const [];
  List<Playlist> _localPlaylists = const [];
  List<Song> _localSongs = const [];
  List<Song> _selectedPlaylistSongs = const [];
  Playlist? _selectedLocalPlaylist;
  Song? _nowPlaying;
  String _status = '准备就绪';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _syncClient = AndroidSyncClient();
    _player = AndroidAudioPlayer();
    _reloadLocal();
  }

  @override
  void dispose() {
    _syncClient.dispose();
    _player.dispose();
    _payloadController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _reloadLocal() {
    final keyword = _searchController.text.trim();
    final playlists = widget.database.search.searchPlaylists(
      keyword,
      syncedOnly: true,
    );
    final selected = _selectedLocalPlaylist == null
        ? (playlists.isEmpty ? null : playlists.first)
        : playlists
              .where((playlist) => playlist.id == _selectedLocalPlaylist!.id)
              .firstOrNull;
    final songs = widget.database.search.searchSongs(keyword, syncedOnly: true);
    final selectedSongs = selected == null
        ? const <Song>[]
        : widget.database.playlists
              .songsForPlaylist(selected.id)
              .where(_isSyncedSong)
              .toList();
    setState(() {
      _localPlaylists = playlists;
      _selectedLocalPlaylist = selected;
      _localSongs = songs;
      _selectedPlaylistSongs = selectedSongs;
    });
  }

  bool _isSyncedSong(Song song) {
    return widget.database.sync.findCacheForSong(song.id)?.status ==
        SyncCacheStatus.synced;
  }

  Future<void> _pastePayload() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      return;
    }
    _payloadController.text = text;
  }

  Future<void> _connectToWindows() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在连接电脑端...';
    });

    try {
      final payload = SyncQrPayload.fromJsonText(_payloadController.text.trim());
      await _syncClient.connect(payload);
      final playlists = await _syncClient.fetchPlaylists(payload);
      if (!mounted) {
        return;
      }
      setState(() {
        _connectedPayload = payload;
        _remotePlaylists = playlists;
        _status = '已连接电脑端，找到 ${playlists.length} 个可同步歌单';
        _busy = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '连接失败：$error';
        _busy = false;
      });
    }
  }

  Future<void> _syncPlaylist(RemotePlaylist playlist) async {
    final payload = _connectedPayload;
    if (_busy || payload == null) {
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在同步歌单：${playlist.name}';
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
      _reloadLocal();
      setState(() {
        _status =
            '同步完成：下载 ${result.downloadedCount}，跳过 ${result.skippedCount}，失败 ${result.failedCount}';
        _busy = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '同步失败：$error';
        _busy = false;
      });
    }
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

  Future<void> _pausePlayback() async {
    try {
      await _player.pause();
      setState(() => _status = '已暂停：${_nowPlaying?.title ?? ''}');
    } catch (error) {
      setState(() => _status = '暂停失败：$error');
    }
  }

  Future<void> _resumePlayback() async {
    try {
      await _player.resume();
      setState(() => _status = '继续播放：${_nowPlaying?.title ?? ''}');
    } catch (error) {
      setState(() => _status = '继续播放失败：$error');
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _player.stop();
      setState(() {
        _nowPlaying = null;
        _status = '已停止播放';
      });
    } catch (error) {
      setState(() => _status = '停止失败：$error');
    }
  }

  Future<void> _deleteLocalCache(Song song) async {
    try {
      final file = File(song.localPath);
      if (await file.exists()) {
        await file.delete();
      }
      widget.database.sync.markDeleted(song.id, DateTime.now().toUtc());
      _reloadLocal();
      setState(() {
        if (_nowPlaying?.id == song.id) {
          _nowPlaying = null;
        }
        _status = '已删除本地缓存：${song.title}。电脑端不会受影响。';
      });
    } catch (error) {
      setState(() => _status = '删除本地缓存失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('壹加音乐 - Android 随身库')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnectionPanel(
                controller: _payloadController,
                busy: _busy,
                status: _status,
                onPaste: _pastePayload,
                onConnect: _connectToWindows,
              ),
              const SizedBox(height: 12),
              if (_remotePlaylists.isNotEmpty)
                _RemotePlaylistPanel(
                  playlists: _remotePlaylists,
                  busy: _busy,
                  onSync: _syncPlaylist,
                ),
              const SizedBox(height: 12),
              _PlaybackBar(
                nowPlaying: _nowPlaying?.title,
                onPause: _nowPlaying == null ? null : _pausePlayback,
                onResume: _nowPlaying == null ? null : _resumePlayback,
                onStop: _nowPlaying == null ? null : _stopPlayback,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (_) => _reloadLocal(),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                  labelText: '搜索已同步歌曲和歌单',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _LocalLibraryPanel(
                  playlists: _localPlaylists,
                  selectedPlaylist: _selectedLocalPlaylist,
                  playlistSongs: _selectedPlaylistSongs,
                  songs: _localSongs,
                  onSelectPlaylist: (playlist) {
                    _selectedLocalPlaylist = playlist;
                    _reloadLocal();
                  },
                  onPlay: _playSong,
                  onDeleteCache: _deleteLocalCache,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.controller,
    required this.busy,
    required this.status,
    required this.onPaste,
    required this.onConnect,
  });

  final TextEditingController controller;
  final bool busy;
  final String status;
  final VoidCallback onPaste;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('同步音乐', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '粘贴 Windows 端二维码内容',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : onPaste,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('粘贴'),
                ),
                FilledButton.icon(
                  onPressed: busy ? null : onConnect,
                  icon: const Icon(Icons.link),
                  label: const Text('连接电脑端'),
                ),
                if (busy)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(status),
          ],
        ),
      ),
    );
  }
}

class _RemotePlaylistPanel extends StatelessWidget {
  const _RemotePlaylistPanel({
    required this.playlists,
    required this.busy,
    required this.onSync,
  });

  final List<RemotePlaylist> playlists;
  final bool busy;
  final ValueChanged<RemotePlaylist> onSync;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListView.separated(
          itemCount: playlists.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return ListTile(
              dense: true,
              title: Text(playlist.name),
              subtitle: Text('${playlist.songCount} 首'),
              trailing: FilledButton(
                onPressed: busy ? null : () => onSync(playlist),
                child: const Text('同步整张歌单'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlaybackBar extends StatelessWidget {
  const _PlaybackBar({
    required this.nowPlaying,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final String? nowPlaying;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('当前播放：${nowPlaying ?? '无'}'),
        IconButton(
          tooltip: '暂停',
          onPressed: onPause,
          icon: const Icon(Icons.pause),
        ),
        IconButton(
          tooltip: '继续',
          onPressed: onResume,
          icon: const Icon(Icons.play_arrow),
        ),
        IconButton(
          tooltip: '停止',
          onPressed: onStop,
          icon: const Icon(Icons.stop),
        ),
      ],
    );
  }
}

class _LocalLibraryPanel extends StatelessWidget {
  const _LocalLibraryPanel({
    required this.playlists,
    required this.selectedPlaylist,
    required this.playlistSongs,
    required this.songs,
    required this.onSelectPlaylist,
    required this.onPlay,
    required this.onDeleteCache,
  });

  final List<Playlist> playlists;
  final Playlist? selectedPlaylist;
  final List<Song> playlistSongs;
  final List<Song> songs;
  final ValueChanged<Playlist> onSelectPlaylist;
  final ValueChanged<Song> onPlay;
  final ValueChanged<Song> onDeleteCache;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        final children = [
          _PlaylistList(
            playlists: playlists,
            selected: selectedPlaylist,
            selectedSongs: playlistSongs,
            onSelect: onSelectPlaylist,
            onPlay: onPlay,
            onDeleteCache: onDeleteCache,
          ),
          _SongList(
            title: '已同步歌曲',
            songs: songs,
            onPlay: onPlay,
            onDeleteCache: onDeleteCache,
          ),
        ];
        if (narrow) {
          return Column(
            children: [
              Expanded(child: children[0]),
              const SizedBox(height: 12),
              Expanded(child: children[1]),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 12),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }
}

class _PlaylistList extends StatelessWidget {
  const _PlaylistList({
    required this.playlists,
    required this.selected,
    required this.selectedSongs,
    required this.onSelect,
    required this.onPlay,
    required this.onDeleteCache,
  });

  final List<Playlist> playlists;
  final Playlist? selected;
  final List<Song> selectedSongs;
  final ValueChanged<Playlist> onSelect;
  final ValueChanged<Song> onPlay;
  final ValueChanged<Song> onDeleteCache;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '已同步歌单（${playlists.length}）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
          if (constraints.maxHeight < 180) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title,
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      playlists.isEmpty
                          ? '暂无已同步歌单'
                          : '当前歌单：${selected?.name ?? playlists.first.name}',
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              title,
              SizedBox(
                height: 112,
                child: playlists.isEmpty
                    ? const Center(child: Text('暂无已同步歌单'))
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
              Expanded(
                child: _SongList(
                  title: selected == null ? '歌单内容' : selected!.name,
                  songs: selectedSongs,
                  onPlay: onPlay,
                  onDeleteCache: onDeleteCache,
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
    required this.onPlay,
    required this.onDeleteCache,
  });

  final String title;
  final List<Song> songs;
  final ValueChanged<Song> onPlay;
  final ValueChanged<Song> onDeleteCache;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final header = Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '$title（${songs.length}）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
          if (constraints.maxHeight < 100) {
            return SingleChildScrollView(child: header);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const Divider(height: 1),
              Expanded(
                child: songs.isEmpty
                    ? const Center(child: Text('暂无内容'))
                    : ListView.separated(
                        itemCount: songs.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          return ListTile(
                            dense: true,
                            title: Text(song.title),
                            subtitle: Text('${song.artist} · ${song.album}'),
                            leading: IconButton(
                              tooltip: '离线播放',
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () => onPlay(song),
                            ),
                            trailing: IconButton(
                              tooltip: '删除本地缓存',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => onDeleteCache(song),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
