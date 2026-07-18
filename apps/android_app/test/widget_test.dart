import 'package:android_app/android_library.dart';
import 'package:android_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database/music_database.dart';

void main() {
  testWidgets('shows the Android local-library player entry screen', (
    tester,
  ) async {
    final database = MusicDatabase.memory();
    addTearDown(database.close);

    await tester.pumpWidget(
      AndroidMusicApp(
        database: database,
        library: const AndroidMusicLibraryLocation(rootPath: 'test_library'),
      ),
    );

    expect(find.text('壹加音乐'), findsOneWidget);
    expect(find.text('你的离线随身音乐库'), findsOneWidget);
    expect(find.text('音乐库'), findsOneWidget);
    expect(find.text('同步音乐'), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.text('手机里还没有同步音乐'), findsOneWidget);
    expect(find.text('去同步音乐'), findsOneWidget);
  });

  testWidgets('opens scan-first sync with a manual fallback', (tester) async {
    final database = MusicDatabase.memory();
    addTearDown(database.close);

    await tester.pumpWidget(
      AndroidMusicApp(
        database: database,
        library: const AndroidMusicLibraryLocation(rootPath: 'test_library'),
      ),
    );

    await tester.tap(find.text('同步音乐'));
    await tester.pumpAndSettle();

    expect(find.text('扫描电脑端二维码'), findsOneWidget);
    expect(find.text('扫码失败？手动粘贴连接信息'), findsOneWidget);

    await tester.tap(find.text('扫码失败？手动粘贴连接信息'));
    await tester.pumpAndSettle();

    expect(find.text('粘贴 Windows 端二维码内容'), findsOneWidget);
    expect(find.text('连接电脑端'), findsOneWidget);
  });
}
