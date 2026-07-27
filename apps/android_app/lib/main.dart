import 'package:flutter/widgets.dart';
import 'package:music_database/music_database.dart';

import 'android_library.dart';
import 'android_shell.dart';
import 'sync_client.dart';

export 'android_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = await AndroidMusicLibraryLocation.resolve();
  await library.ensureReady();
  final database = MusicDatabase.open(library.databasePath);
  await AndroidSyncClient.recoverInterruptedSyncs(
    database: database,
    library: library,
  );
  runApp(AndroidMusicApp(database: database, library: library));
}
