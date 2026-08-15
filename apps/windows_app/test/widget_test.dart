import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_core/music_core.dart';
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
        library: const MusicLibraryLocation(rootPath: 'test_library'),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.brightness, Brightness.light);
    expect(app.theme?.colorScheme.primary, const Color(0xFF2C664C));
    expect(
      app.theme?.navigationRailTheme.selectedLabelTextStyle?.fontWeight,
      FontWeight.w600,
    );
    expect(
      app.theme?.navigationRailTheme.unselectedLabelTextStyle?.fontWeight,
      FontWeight.w400,
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/yijia_music_logo.png',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.byIcon(Icons.queue_music_outlined), findsOneWidget);
    expect(find.byType(Badge), findsNothing);
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

  testWidgets('opens the Wi-Fi sync page and shows the copy action', (
    tester,
  ) async {
    final database = MusicDatabase.memory();
    addTearDown(database.close);

    await tester.pumpWidget(
      WindowsMusicApp(
        database: database,
        library: const MusicLibraryLocation(rootPath: 'test_library'),
      ),
    );

    await tester.tap(find.byTooltip('Wi-Fi 同步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('开启同步模式'), findsOneWidget);
    expect(find.text('复制连接信息'), findsOneWidget);
  });

  testWidgets('deleting a song removes it from the whole app', (tester) async {
    final database = MusicDatabase.memory();
    addTearDown(database.close);
    const library = MusicLibraryLocation(rootPath: 'test_library');

    final now = DateTime.utc(2026, 8, 14);
    database.songs.upsert(
      Song(
        id: 'song-1',
        title: 'Unwanted',
        artist: 'Artist',
        album: 'Album',
        format: AudioFormat.mp3,
        fileSize: 3,
        fileHash: 'hash-1',
        localPath: 'outside_library/unwanted.mp3',
        originalFileName: 'unwanted.mp3',
        displayNameSource: DisplayNameSource.filename,
        isPendingReview: false,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      WindowsMusicApp(database: database, library: library),
    );
    expect(find.text('Unwanted'), findsOneWidget);

    // The row sits inside a double-tap GestureDetector, which holds the
    // gesture arena until its double-tap timeout expires, so advance the fake
    // clock past it before expecting the button's onPressed to fire.
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除歌曲'));
    await tester.pumpAndSettle();

    // The confirmation dialog explains the destructive effect.
    expect(find.textContaining('从整个应用删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(database.songs.findById('song-1'), isNull);
    expect(find.text('Unwanted'), findsNothing);
    expect(find.textContaining('已删除：Unwanted'), findsOneWidget);
  });
}
