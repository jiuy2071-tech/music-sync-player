import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AndroidMusicLibraryLocation {
  const AndroidMusicLibraryLocation({required this.rootPath});

  final String rootPath;

  String get audioPath => p.join(rootPath, 'audio');

  String get databasePath => p.join(rootPath, 'library.db');

  static Future<AndroidMusicLibraryLocation> resolve() async {
    final directory = await getApplicationDocumentsDirectory();
    return AndroidMusicLibraryLocation(rootPath: directory.path);
  }

  Future<void> ensureReady() async {
    await Directory(audioPath).create(recursive: true);
  }
}
