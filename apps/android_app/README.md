# 壹加音乐 Android 应用

Android 是只读随身播放器：扫码连接 Windows、按整张歌单同步、只显示已同步内容，并离线播放本机文件。

## 主要入口

- `lib/android_shell.dart`：音乐库、歌单、同步音乐三页界面与播放器交互。
- `lib/sync_client.dart`：连接 Windows、下载清单与文件、写入本地数据库。
- `lib/android_audio_player.dart`：`audioplayers` 本地文件播放适配。
- `lib/android_library.dart`：APP Documents 下的音频与 SQLite 路径。

## 验证

```powershell
D:\Dev\flutter\bin\flutter.bat analyze
D:\Dev\flutter\bin\flutter.bat test
D:\Dev\flutter\bin\flutter.bat build apk --debug
```

交付 APK：`..\..\release\android\music_sync_player_v1_debug.apk`。相机扫码、同一 Wi-Fi 连接和离线播放需在真机上确认。
