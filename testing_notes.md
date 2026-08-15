# 自动测试与人工验收说明

## Generated Sample Status

`ffmpeg` and `ffplay` are available on this machine, so Phase 7 generated short,
non-sensitive test audio inside this project-only folder:

`manual_test_audio/`

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
- Android atomic sync rollback for incomplete downloads and Hash mismatches.
- Android storage preflight, bounded retry, session-bound download URLs and
  unsafe path rejection.
- Windows authoritative playlist versions, Android empty-playlist snapshots,
  shared-song reference protection and orphan cleanup.
- Windows startup detection for `ffplay` and `ffprobe`.

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
- Confirm numeric, encoded, garbled, or meaningless names become
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
- Delete a Windows playlist and reconnect Android; confirm the old phone
  snapshot disappears.
- Remove a shared song from one Windows playlist and confirm another synced
  playlist still keeps its local file.
- Sync an empty Windows playlist and confirm it remains visible on Android.
- Interrupt a real playlist download and confirm the previously playable phone
  snapshot remains unchanged.

## Still Needs Manual Device Confirmation

The generated samples cover the code paths, but these still need a human with a
running Windows app and an Android device:

- Use the real Windows file picker for file import.
- Use the real Windows folder picker for folder import.
- Create and rename multiple playlists through the Windows UI.
- Confirm Windows UI search behavior visually.
- On a physical phone, open Windows sync mode and scan the displayed QR code.
- Confirm the physical phone can reach the Windows machine on the same Wi-Fi.
- Confirm the physical-phone UI shows only synced content after sync.
- Delete one physical-phone cache item and confirm the Windows library is
  unchanged.
- Close Windows sync mode or disconnect Wi-Fi and confirm the physical phone
  still plays already-synced files offline.
- Install the new APK over a physical Android device that already contains
  synced content and confirm the retained songs still play.

## 2026-07-26 Emulator Upgrade Check

- Installed the latest fixed APK with `adb install -r`, preserving the
  emulator's existing APP data.
- The Android process started and remained running after the upgrade.
- Checked recent logcat output; no `FATAL EXCEPTION`, `AndroidRuntime` crash or
  Flutter startup failure was present.
- This confirms overwrite installation and startup migration on the emulator.
  It does not prove migration of a real non-empty old synced library, real
  camera scanning, same-Wi-Fi transfer or offline playback on a physical phone.

## 2026-07-27 Emulator Cross-Process Sync Check

- Started the fixed Windows release EXE and enabled its real Wi-Fi sync mode.
- Confirmed the server listened on all IPv4 interfaces and advertised the
  physical WLAN address, not the `198.18.0.1` proxy adapter.
- Used the Android app's manual paste fallback with the complete connection
  payload and connected from `emulator-5554` to the running Windows EXE.
- Android displayed the Windows playlist `新歌单` and synced the entire
  one-song playlist.
- Repeating the sync reused the existing matching local file: Android still
  showed one song, one playlist and one audio file, with no duplicate record.
- The Android private `.sync_staging` directory was empty after completion.
- Closed Windows sync mode and confirmed its listening port was gone.
- Closed the Windows EXE completely. Android retained audio focus, kept the
  pause button visible and its playback slider continued advancing from the
  local WAV file.
- Created `emulator_empty_playlist` with zero songs in the fixed Windows EXE.
  Android showed both remote playlists, synced the empty playlist, and kept it
  visible in the local playlist page without creating a song.
- Deleted the temporary playlist in Windows while the real sync service was
  running. On reconnect, Android reported that it removed one stale playlist
  and zero orphaned cache files.
- After reconciliation, Android still showed the original `新歌单` and
  `回声_master`; its private WAV remained exactly 37,446,236 bytes.
- Added `回声_master` to both `新歌单` and `shared_reference_test`, then
  synced the second playlist. Android kept two playlist references but still
  stored only one WAV file.
- Deleted `shared_reference_test` in Windows and reconnected Android. The stale
  playlist disappeared, zero orphaned cache files were removed, and the WAV
  referenced by `新歌单` remained exactly 37,446,236 bytes.
- Synced `member_change_test` with one song, removed that song through the
  Windows playlist menu, and reconnected. The remote playlist version changed
  to zero songs; resyncing updated the Android snapshot to an empty playlist
  without deleting the song still referenced by `新歌单`.
- Deleted the final temporary playlist and reconciled once more. Both apps
  returned to one playlist, one song and one formal audio file.
- This proves the current executable and APK can complete the LAN transfer and
  offline playback flow, empty-playlist sync and authoritative deletion
  reconciliation, playlist member changes and shared-file retention in the
  Android emulator. A physical phone is still required for camera permission,
  QR scanning and real device Wi-Fi behavior.

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
- Atomic download rollback, storage preflight, finite network retry, playlist
  version matching, empty snapshots, authoritative deletion reconciliation,
  reference-aware orphan cleanup and Windows playback capability detection.
- Startup recovery after a forced stop before or after the SQLite commit marker.
- Real on-disk old-schema database upgrade with non-empty songs, playlists,
  playlist items and sync cache retained.

## 2026-08-15 Open-Source Readiness Check

- All four shared packages plus the Windows and Android apps passed
  `flutter analyze`.
- All 54 automated tests passed: 20 shared-package tests, 18 Windows tests and
  16 Android tests.
- New coverage verifies literal backslash search, oversized-download aborts,
  malformed QR/connect payloads and managed-library file deletion.
- The Windows Release build and Android Debug APK build both completed.
- The fixed local Windows acceptance entry started successfully, and the
  copied delivery files matched the build outputs by SHA-256.
- The fixed APK was installed over the existing Android Studio emulator with
  `adb install -r`. Existing local music remained visible, the app reached the
  library screen, and no Android or Flutter startup crash was logged.
- Emulator overwrite installation does not verify physical-camera scanning.
- A physical phone still needs to confirm camera permission, QR scanning,
  real Wi-Fi transfer, overwrite installation and offline playback feel.
