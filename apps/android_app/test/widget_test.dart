import 'package:android_app/android_library.dart';
import 'package:android_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database/music_database.dart';

void main() {
  testWidgets('shows Android sync and local library screen', (tester) async {
    final database = MusicDatabase.memory();
    addTearDown(database.close);

    await tester.pumpWidget(
      AndroidMusicApp(
        database: database,
        library: const AndroidMusicLibraryLocation(rootPath: 'test_library'),
      ),
    );

    expect(find.text('壹加音乐 - Android 随身库'), findsOneWidget);
    expect(find.text('同步音乐'), findsOneWidget);
    expect(find.text('扫码'), findsOneWidget);
    expect(find.text('连接电脑端'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text('暂无已同步歌单'), findsOneWidget);
  });
}
