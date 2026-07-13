import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database/music_database.dart';
import 'package:windows_app/audio_import_service.dart';
import 'package:windows_app/main.dart';

void main() {
  testWidgets('opens the player-focused Windows music library', (tester) async {
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

    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.byIcon(Icons.queue_music_outlined), findsOneWidget);
    expect(find.text('音乐库'), findsAtLeastNWidgets(1));
    expect(find.text('选择一首歌曲开始播放'), findsOneWidget);
    final addSongsButton = find.widgetWithText(FilledButton, '添加歌曲');
    expect(addSongsButton, findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);

    await tester.tap(addSongsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('导入音频文件'), findsOneWidget);
    expect(find.text('导入文件夹'), findsOneWidget);
    expect(find.textContaining('待整理音频'), findsOneWidget);
  });
}
