# 壹加音乐 V1 Release Notes

## Build Date

2026-07-12

## Artifacts

Windows runnable directory:

```text
D:\Projects\music_sync_player\release\windows\MusicSyncPlayer\
```

Windows executable:

```text
D:\Projects\music_sync_player\release\windows\MusicSyncPlayer\windows_app.exe
```

Android debug APK:

```text
D:\Projects\music_sync_player\release\android\music_sync_player_v1_debug.apk
```

The `release/` directory is ignored by Git and should not be committed.

## Completed V1 Features

- Windows local music library.
- Windows audio file import.
- Windows folder import.
- Supported import formats: MP3, FLAC, M4A, WAV.
- Conservative filename handling for numeric, encoded,乱码, or meaningless names.
- Pending-review names such as `未命名音频 001/002/003...`.
- Duplicate audio detection by file hash.
- Windows playlist creation, rename, delete, add song, and remove song.
- Windows search for songs and playlists.
- Windows local playback for generated MP3, FLAC, M4A, and WAV test files.
- Windows player-focused startup screen: the default page is the music library, while adding songs and Wi-Fi sync are separate pages.
- Windows bottom playback bar with current song details, play/pause, stop, elapsed time, duration, and draggable progress control.
- Windows Wi-Fi sync mode with connection code and QR payload.
- Windows sync server endpoints for connection, playlist list, playlist manifest, and audio download.
- Android QR scan connection.
- Android manual QR payload paste fallback.
- Android whole-playlist sync from Windows to local app storage.
- Android local database write for synced songs and playlists.
- Android synced-only library display.
- Android synced-only search.
- Android local cache deletion without modifying the Windows library.
- Android offline playback of locally synced files.
- Android playback progress control and clearer sync results, including local-song count and the first failure reason when a song cannot be synced.

## How To Start Windows

1. Open:

   ```text
   D:\Projects\music_sync_player\release\windows\MusicSyncPlayer\
   ```

2. Double-click `windows_app.exe`.
3. The default `音乐库` page is for searching and playing music.
4. Open `添加歌曲` when you want to import audio files or a folder.
5. Create a playlist and add songs from the music library.
6. Open `Wi-Fi 同步` to show the QR code and connection code.

The bottom playback bar supports play/pause, stop, elapsed time, and dragging the progress control. Windows playback seeks by restarting `ffplay` from the chosen position, so a short restart is expected after dragging.

Note: Windows local playback currently uses `ffplay` from the local machine to support MP3, FLAC, M4A, and WAV. If another machine does not have `ffplay` on PATH, import, playlist management, and sync can still work, but Windows-side playback needs a playback backend available on that machine.

## How To Install Android APK

1. Copy this APK to the Android phone:

   ```text
   D:\Projects\music_sync_player\release\android\music_sync_player_v1_debug.apk
   ```

2. Allow local APK installation on the phone.
3. Install and open the app.

## How To Sync Over Wi-Fi

1. Keep the Windows computer and Android phone on the same Wi-Fi.
2. Open sync mode on Windows.
3. On Android, tap `扫码` and scan the Windows QR code.
4. If scanning fails, paste the Windows QR payload into the Android text box and tap `连接电脑端`.
5. Choose a playlist and sync the whole playlist.
6. After sync, Android shows only locally synced songs and playlists.
7. Android can play already-synced songs from local storage after the Windows sync mode is closed or the network is unavailable.

## Automated Validation Passed

- `apps\windows_app`: `flutter analyze`
- `apps\windows_app`: `flutter test`
- `apps\windows_app`: `flutter build windows`
- `apps\android_app`: `flutter analyze`
- `apps\android_app`: `flutter test`
- `apps\android_app`: `flutter build apk --debug`
- Generated test audio import: MP3, FLAC, M4A, WAV.
- Generated test audio playback probe: MP3, FLAC, M4A, WAV.
- Duplicate file handling.
- Pending-review filename handling.
- Windows sync service tests.
- Android sync client tests.

## Latest Windows Player Improvements

- Unified the Windows typography with Microsoft YaHei UI and a consistent title/body/button weight scale.
- Moved previous, play/pause, and next controls to the center of the bottom player bar.
- Added playback queue controls: play next, add to queue, inspect the queue, drag to reorder, remove upcoming songs, and clear upcoming songs.
- Added sequence, repeat-all, repeat-one, and shuffle playback modes.
- Added keyboard controls: Ctrl+Space, Ctrl+Left/Right, and Alt+Left/Right.
- Verified this Windows update with `flutter analyze`, `flutter test`, and `flutter build windows`.

## Windows Visual Refresh

- Reworked the initial graphite-and-berry visual refresh after usability feedback: the Windows UI now uses a brighter fog-green layered palette with high-contrast controls.
- Kept the listening view focused: import and Wi-Fi sync remain separate pages, while search, songs, playlists, and playback stay on the main library page.
- Restyled navigation, search, lists, playlist panels, import, sync, and the full-width bottom player bar with restrained borders and spacing.
- Updated the queue to appear as a right-aligned panel rather than a centered utility dialog.
- The primary control color is forest green, with a white play icon and darker standard icons to keep every control legible.
- Added a widget test that guards the light theme and forest-green primary color.
- Verified this visual refresh with `flutter analyze`, `flutter test`, and `flutter build windows`.

## Still Needs Manual Confirmation

- Windows real file picker and folder picker interaction.
- Android camera permission dialog on a real phone.
- Android real QR scan against the Windows QR code.
- Android phone reaching the Windows sync service on the same Wi-Fi.
- Android offline playback after closing Windows sync mode or disconnecting Wi-Fi.

## Out Of Scope For V1

V1 does not include cloud sync, public remote streaming, USB sync, Bluetooth sync, covers, lyrics, recommendation algorithms, comments/social features, multi-user login, Android playlist editing, Android music import, or Android sync back to Windows.
