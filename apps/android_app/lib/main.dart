import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  String _status = '准备就绪';
  bool _busy = false;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<void>? _completeSubscription;

  @override
  void initState() {
    super.initState();
    _syncClient = AndroidSyncClient();
    _player = AndroidAudioPlayer();
    _positionSubscription = _player.positionStream.listen((position) {
      if (!mounted) {
        return;
      }
      setState(() => _playbackPosition = position);
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() => _playbackDuration = duration);
    });
    _completeSubscription = _player.completeStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nowPlaying = null;
        _playbackPosition = Duration.zero;
        _status = '播放结束';
      });
    });
    _reloadLocal();
  }

  @override
  void dispose() {
    _syncClient.dispose();
    _player.dispose();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _completeSubscription?.cancel();
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
    await _connectWithPayloadText(_payloadController.text.trim());
  }

  Future<void> _connectWithPayloadText(String payloadText) async {
    if (_busy) {
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
      _payloadController.text = payloadText;
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

  Future<void> _scanPayload() async {
    if (_busy) {
      return;
    }
    final payloadText = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const _QrScanPage()),
    );
    if (!mounted || payloadText == null || payloadText.trim().isEmpty) {
      return;
    }
    await _connectWithPayloadText(payloadText.trim());
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
      final firstFailure = result.failureMessages.isEmpty
          ? ''
          : '，首个失败：${result.failureMessages.first}';
      setState(() {
        _status = result.hasFailures
            ? '同步未完全成功：下载 ${result.downloadedCount}，跳过 ${result.skippedCount}，失败 ${result.failedCount}，本机现有 ${result.localSongCount} 首$firstFailure'
            : '同步完成：下载 ${result.downloadedCount}，跳过 ${result.skippedCount}，本机现有 ${result.localSongCount} 首';
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
        _playbackPosition = Duration.zero;
        _playbackDuration = song.durationMs == null
            ? Duration.zero
            : Duration(milliseconds: song.durationMs!);
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
        _playbackPosition = Duration.zero;
        _playbackDuration = Duration.zero;
        _status = '已停止播放';
      });
    } catch (error) {
      setState(() => _status = '停止失败：$error');
    }
  }

  Future<void> _seekPlayback(Duration position) async {
    try {
      await _player.seek(position);
      setState(() => _playbackPosition = position);
    } catch (error) {
      setState(() => _status = '拖动进度失败：$error');
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
                onScan: _scanPayload,
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
                position: _playbackPosition,
                duration: _playbackDuration,
                onPause: _nowPlaying == null ? null : _pausePlayback,
                onResume: _nowPlaying == null ? null : _resumePlayback,
                onStop: _nowPlaying == null ? null : _stopPlayback,
                onSeek: _nowPlaying == null ? null : _seekPlayback,
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
    required this.onScan,
    required this.onConnect,
  });

  final TextEditingController controller;
  final bool busy;
  final String status;
  final VoidCallback onPaste;
  final VoidCallback onScan;
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
                OutlinedButton.icon(
                  onPressed: busy ? null : onScan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('扫码'),
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
      appBar: AppBar(title: const Text('扫描 Windows 同步二维码')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _handleDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '无法打开摄像头：${error.errorDetails?.message ?? error.errorCode.message}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: const Text(
                '请将 Windows 端显示的二维码放入取景框',
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
    required this.position,
    required this.duration,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSeek,
  });

  final String? nowPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds;
    final currentMs = position.inMilliseconds.clamp(0, maxMs);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '当前播放：${nowPlaying ?? '无'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Text(_formatDuration(position)),
                Expanded(
                  child: Slider(
                    value: maxMs == 0 ? 0 : currentMs.toDouble(),
                    max: maxMs == 0 ? 1 : maxMs.toDouble(),
                    onChanged: onSeek == null || maxMs == 0
                        ? null
                        : (value) {
                            onSeek!(Duration(milliseconds: value.round()));
                          },
                  ),
                ),
                Text(maxMs == 0 ? '--:--' : _formatDuration(duration)),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
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
