import 'package:flutter/material.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';

import 'audio_import_service.dart';

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F7A68),
          brightness: Brightness.light,
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

class _WindowsHomePageState extends State<WindowsHomePage> {
  late final AudioImportService _importService;
  final _dialog = WindowsFileDialog();
  final _searchController = TextEditingController();

  List<Song> _songs = const [];
  List<Song> _pendingSongs = const [];
  ImportResult? _lastImportResult;
  String _status = '准备就绪';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _importService = AudioImportService(widget.database);
    _reloadSongs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reloadSongs() {
    final keyword = _searchController.text.trim();
    setState(() {
      _songs = keyword.isEmpty
          ? widget.database.songs.all()
          : widget.database.search.searchSongs(keyword);
      _pendingSongs = widget.database.songs.pendingReview();
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
      _reloadSongs();
    } catch (error) {
      setState(() {
        _status = '导入失败：$error';
        _busy = false;
      });
    }
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
              onImportFiles: _importFiles,
              onImportFolder: _importFolder,
            ),
            const SizedBox(height: 16),
            _SearchField(
              controller: _searchController,
              onChanged: (_) => _reloadSongs(),
            ),
            const SizedBox(height: 16),
            _ImportSummary(result: _lastImportResult),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _SongList(title: '全部歌曲', songs: _songs),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _SongList(title: '待整理音频', songs: _pendingSongs),
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
    required this.onImportFiles,
    required this.onImportFolder,
  });

  final bool busy;
  final String libraryPath;
  final String status;
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
            const SizedBox(height: 6),
            Text(status, style: Theme.of(context).textTheme.bodyMedium),
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
        labelText: '搜索歌曲、歌手、专辑、原始文件名',
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

class _SongList extends StatelessWidget {
  const _SongList({required this.title, required this.songs});

  final String title;
  final List<Song> songs;

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
                        trailing: song.isPendingReview
                            ? const Chip(label: Text('待整理'))
                            : null,
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
