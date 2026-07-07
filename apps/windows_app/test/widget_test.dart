import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database/music_database.dart';
import 'package:windows_app/audio_import_service.dart';
import 'package:windows_app/main.dart';

void main() {
  testWidgets('shows Windows library import screen', (tester) async {
    final database = MusicDatabase.memory();
    addTearDown(database.close);

    await tester.pumpWidget(
      WindowsMusicApp(
        database: database,
        library: const MusicLibraryLocation(
          rootPath: r'D:\OnePlusMusic\Library',
        ),
      ),
    );

    expect(find.text('壹加音乐 - Windows 主库'), findsOneWidget);
    expect(find.text('导入音频文件'), findsOneWidget);
    expect(find.text('导入文件夹'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });
}
