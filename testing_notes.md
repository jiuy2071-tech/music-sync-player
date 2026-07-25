# 自动测试与人工验收说明

## Generated Sample Status

`ffmpeg` and `ffplay` are available on this machine, so Phase 7 generated short,
non-sensitive test audio inside this project-only folder:

```text
D:\Projects\music_sync_player\manual_test_audio\
```

I did not scan Desktop, Downloads, Documents, WeChat, browser data, system music
libraries, or any other private directory. No real user music files were used.

Generated files:

```text
normal_artist - normal_title.mp3
001.flac
a8f39c2024.m4a
random_code_839201.wav
duplicate_source.mp3
duplicate_copy.mp3
```

These files are ignored by Git through `manual_test_audio/` and must not be
committed.

## Automated Acceptance Results

Passed with generated samples:

- File import for MP3, FLAC, M4A, and WAV.
- Folder import from `manual_test_audio/`.
- Normal MP3 metadata recognition for `normal_artist - normal_title.mp3`.
- Numeric, encoded, and meaningless filenames entering pending review as
  `未命名音频 001/002/003...`.
- Duplicate MP3 hash detection with `duplicate_source.mp3` and
  `duplicate_copy.mp3`.
- Imported files copied into the app library path without modifying originals.
- Windows playback probe for generated MP3, FLAC, M4A, and WAV using `ffplay`.
- Windows sync server connect, playlist list, manifest, and file download.
- Android sync client connect, playlist fetch, whole-playlist sync, local file
  write, local database write, and synced-only visibility.
- Android music-library, playlist and sync navigation entry; scan-first flow and
  manual-paste fallback UI.
- Android local-player controls: play/pause state, previous/next queue actions
  and seek wiring are covered by application-level tests and build validation.

Builds passed:

- Windows: `flutter build windows`.
- Android: `flutter build apk --debug`.

## Manual Acceptance Checklist

Windows import:

- Select individual MP3, FLAC, M4A, and WAV files.
- Select a folder containing supported audio files.
- Confirm imported files are copied into the app library and originals are not
  moved or deleted.
- Confirm normal filenames are identified conservatively.
- Confirm numeric, encoded,乱码, or meaningless names become
  `未命名音频 001/002/003...` and appear in pending review.
- Confirm duplicate files are skipped by hash and do not create duplicate songs.

Windows library:

- Create multiple playlists.
- Add the same song to multiple playlists.
- Confirm adding the same song twice to one playlist does not duplicate it.
- Search by song title, artist, album, original filename, and playlist name.
- Play MP3, FLAC, M4A, and WAV locally where the Windows playback backend
  supports them.

Windows sync mode:

- Open Wi-Fi sync mode manually.
- Confirm a connection address, 6-digit connection code, QR code, and JSON
  payload are shown.
- Confirm closing sync mode disables the session.

Android sync:

- Paste or scan the Windows QR payload.
- Connect to the Windows sync service on the same Wi-Fi.
- Confirm Android shows the Windows playlist list.
- Sync an entire playlist.
- Confirm downloaded audio files exist in the Android app local directory.
- Confirm Android local database shows only synced songs and synced playlists.
- Search synced songs and playlists on Android.
- Delete local cache for one song and confirm the Windows library is unchanged.
- Turn off Wi-Fi or close Windows sync mode and confirm Android can still play
  already-synced songs offline.

## Still Needs Manual Device Confirmation

The generated samples cover the code paths, but these still need a human with a
running Windows app and an Android device:

- Use the real Windows file picker for file import.
- Use the real Windows folder picker for folder import.
- Create and rename multiple playlists through the Windows UI.
- Confirm Windows UI search behavior visually.
- Open Windows sync mode and scan or paste the displayed QR payload on Android.
- Confirm the Android device can reach the Windows machine on the same Wi-Fi.
- Confirm Android UI shows only synced content after sync.
- Delete one Android local cache item and confirm the Windows library is
  unchanged.
- Close Windows sync mode or disconnect Wi-Fi and confirm Android still plays
  already-synced files offline.

## 当前自动覆盖

Automated tests currently cover:

- Core model storage round trips.
- Database duplicate song hash lookup.
- Playlist deletion without deleting song records.
- Prevention of duplicate playlist items.
- Search restricted to synced local content.
- Sync QR payload and connect request/response round trips.
- Windows sync server connect, playlist, manifest, and file download endpoints.
- Android sync client connect, playlist fetch, whole-playlist sync, local file
  write, local database write, and synced-only search visibility.
- Windows generated-audio import and playback probes.
