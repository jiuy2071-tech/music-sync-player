import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_core/music_core.dart';
import 'package:music_database/music_database.dart';

void main() {
  late MusicDatabase database;

  setUp(() {
    database = MusicDatabase.memory();
  });

  tearDown(() {
    database.close();
  });

  test('stores songs and finds duplicates by hash', () {
    final song = _song(id: 'song-1', title: '未命名音频 001');

    database.songs.upsert(song);

    expect(database.songs.findById('song-1')?.title, '未命名音频 001');
    expect(database.songs.findByHash('hash-song-1')?.id, 'song-1');
    expect(database.songs.nextUnnamedAudioNumber(), 2);
  });

  test('removing playlist does not remove song file record', () {
    final song = _song(id: 'song-1', title: 'Song A');
    final playlist = _playlist(id: 'playlist-1', name: 'Daily');
    final item = _playlistItem(
      id: 'item-1',
      playlistId: playlist.id,
      songId: song.id,
    );

    database.songs.upsert(song);
    database.playlists.upsert(playlist);
    database.playlists.addSong(item: item);
    database.playlists.deletePlaylist(playlist.id);

    expect(database.playlists.findById(playlist.id), isNull);
    expect(database.songs.findById(song.id), isNotNull);
  });

  test('same song is not duplicated inside a playlist', () {
    final song = _song(id: 'song-1', title: 'Song A');
    final playlist = _playlist(id: 'playlist-1', name: 'Daily');

    database.songs.upsert(song);
    database.playlists.upsert(playlist);
    database.playlists.addSong(
      item: _playlistItem(
        id: 'item-1',
        playlistId: playlist.id,
        songId: song.id,
      ),
    );
    database.playlists.addSong(
      item: _playlistItem(
        id: 'item-2',
        playlistId: playlist.id,
        songId: song.id,
        sortOrder: 5,
      ),
    );

    final songs = database.playlists.songsForPlaylist(playlist.id);
    expect(songs, hasLength(1));
    expect(songs.single.id, song.id);
  });

  test('removing song removes playlist and synced references', () {
    final song = _song(id: 'song-1', title: 'Song A');
    final playlist = _playlist(id: 'playlist-1', name: 'Daily');

    database.songs.upsert(song);
    database.playlists.upsert(playlist);
    database.playlists.addSong(
      item: _playlistItem(
        id: 'item-1',
        playlistId: playlist.id,
        songId: song.id,
      ),
    );
    database.sync.upsertCacheEntry(
      SyncCacheEntry(
        id: 'cache-1',
        songId: song.id,
        playlistId: playlist.id,
        localCachePath: song.localPath,
        fileHash: song.fileHash,
        status: SyncCacheStatus.synced,
        syncedAt: DateTime.utc(2026, 7, 8),
      ),
    );

    database.songs.deleteById(song.id);

    expect(database.songs.findById(song.id), isNull);
    expect(database.playlists.songsForPlaylist(playlist.id), isEmpty);
    expect(database.search.searchSongs('Song'), isEmpty);
    expect(database.search.searchSongs('Song', syncedOnly: true), isEmpty);
  });

  test('synced search only returns local synced content', () {
    final localSong = _song(id: 'song-1', title: 'Local Song');
    final remoteSong = _song(id: 'song-2', title: 'Remote Song');

    database.songs.upsert(localSong);
    database.songs.upsert(remoteSong);
    database.sync.upsertCacheEntry(
      SyncCacheEntry(
        id: 'cache-1',
        songId: localSong.id,
        localCachePath: localSong.localPath,
        fileHash: localSong.fileHash,
        status: SyncCacheStatus.synced,
        syncedAt: DateTime.utc(2026, 7, 7),
      ),
    );

    expect(database.search.searchSongs('Song'), hasLength(2));
    expect(database.search.searchSongs('Song', syncedOnly: true), hasLength(1));
    expect(
      database.search.searchSongs('Song', syncedOnly: true).single.id,
      'song-1',
    );
  });

  test('searches playlists by name', () {
    database.playlists.upsert(_playlist(id: 'playlist-1', name: 'Road Trip'));
    database.playlists.upsert(_playlist(id: 'playlist-2', name: 'Evening'));

    final result = database.search.searchPlaylists('road');

    expect(result, hasLength(1));
    expect(result.single.id, 'playlist-1');
  });

  test('search treats percent and underscore as literal characters', () {
    database.songs.upsert(_song(id: 'song-1', title: 'My 50% Mix'));
    database.songs.upsert(_song(id: 'song-2', title: 'a_b song'));
    database.songs.upsert(_song(id: 'song-3', title: 'My 50X Mix'));
    database.songs.upsert(_song(id: 'song-4', title: 'aXb song'));

    final percent = database.search.searchSongs('50%');
    expect(percent.map((song) => song.id), ['song-1']);

    final underscore = database.search.searchSongs('a_b');
    expect(underscore.map((song) => song.id), ['song-2']);
  });

  test('transaction rolls back all database changes after a failure', () async {
    final playlist = _playlist(id: 'playlist-1', name: 'Before');
    database.playlists.upsert(playlist);

    await expectLater(
      database.transaction<void>(() async {
        database.playlists.upsert(_playlist(id: playlist.id, name: 'After'));
        database.songs.upsert(_song(id: 'song-1', title: 'Temporary'));
        throw StateError('stop transaction');
      }),
      throwsStateError,
    );

    expect(database.playlists.findById(playlist.id)?.name, 'Before');
    expect(database.songs.findById('song-1'), isNull);
  });

  test('synced empty playlist remains visible on Android', () {
    final playlist = _playlist(id: 'playlist-empty', name: 'Empty playlist');
    database.playlists.upsert(playlist);
    database.sync.upsertPlaylistSnapshot(
      playlistId: playlist.id,
      sourceVersion: 'version-empty',
      syncedAt: DateTime.utc(2026, 7, 26),
    );

    final result = database.search.searchPlaylists('', syncedOnly: true);

    expect(result, hasLength(1));
    expect(result.single.id, playlist.id);
    expect(database.sync.playlistSourceVersion(playlist.id), 'version-empty');
  });

  test('finds synced songs only after all playlist references are removed', () {
    final song = _song(id: 'shared-song', title: 'Shared Song');
    final first = _playlist(id: 'playlist-1', name: 'First');
    final second = _playlist(id: 'playlist-2', name: 'Second');
    database.songs.upsert(song);
    database.playlists.upsert(first);
    database.playlists.upsert(second);
    database.playlists.addSong(
      item: _playlistItem(id: 'item-1', playlistId: first.id, songId: song.id),
    );
    database.playlists.addSong(
      item: _playlistItem(id: 'item-2', playlistId: second.id, songId: song.id),
    );
    database.sync.upsertCacheEntry(
      SyncCacheEntry(
        id: 'cache-shared-song',
        songId: song.id,
        localCachePath: song.localPath,
        fileHash: song.fileHash,
        status: SyncCacheStatus.synced,
        syncedAt: DateTime.utc(2026, 7, 26),
      ),
    );

    database.playlists.deletePlaylist(first.id);
    expect(database.sync.unreferencedSyncedSongs(), isEmpty);

    database.playlists.deletePlaylist(second.id);
    expect(database.sync.unreferencedSyncedSongs().single.id, song.id);
  });

  test('opens and upgrades an older on-disk database without losing data', () {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'oneplus_database_upgrade_',
    );
    final databasePath = '${tempDirectory.path}${Platform.pathSeparator}old.db';
    MusicDatabase? legacyDatabase;
    MusicDatabase? upgradedDatabase;
    try {
      legacyDatabase = MusicDatabase.open(databasePath);
      final song = _song(id: 'legacy-song', title: 'Legacy Song');
      final playlist = _playlist(
        id: 'legacy-playlist',
        name: 'Legacy Playlist',
      );
      legacyDatabase.songs.upsert(song);
      legacyDatabase.playlists.upsert(playlist);
      legacyDatabase.playlists.addSong(
        item: _playlistItem(
          id: 'legacy-item',
          playlistId: playlist.id,
          songId: song.id,
        ),
      );
      legacyDatabase.sync.upsertCacheEntry(
        SyncCacheEntry(
          id: 'legacy-cache',
          songId: song.id,
          playlistId: playlist.id,
          localCachePath: song.localPath,
          fileHash: song.fileHash,
          status: SyncCacheStatus.synced,
          syncedAt: DateTime.utc(2026, 7, 18),
        ),
      );
      legacyDatabase.db.execute('DROP TABLE synced_playlists');
      legacyDatabase.db.execute('DROP TABLE sync_operations');
      legacyDatabase.close();
      legacyDatabase = null;

      upgradedDatabase = MusicDatabase.open(databasePath);

      expect(upgradedDatabase.songs.findById(song.id)?.title, song.title);
      expect(
        upgradedDatabase.playlists.songsForPlaylist(playlist.id).single.id,
        song.id,
      );
      expect(
        upgradedDatabase.search.searchPlaylists('', syncedOnly: true).single.id,
        playlist.id,
      );
      expect(
        upgradedDatabase.sync.playlistSourceVersion(playlist.id),
        'legacy',
      );
      expect(upgradedDatabase.sync.committedOperationIds(), isEmpty);
    } finally {
      legacyDatabase?.close();
      upgradedDatabase?.close();
      tempDirectory.deleteSync(recursive: true);
    }
  });
}

Song _song({required String id, required String title}) {
  final now = DateTime.utc(2026, 7, 7);
  final pending = title.startsWith('未命名音频');
  return Song(
    id: id,
    title: title,
    artist: pending ? '未知歌手' : 'Artist',
    album: pending ? '未知专辑' : 'Album',
    format: AudioFormat.mp3,
    fileSize: 100,
    fileHash: 'hash-$id',
    localPath: 'audio/$id.mp3',
    originalFileName: '$id.mp3',
    displayNameSource: pending
        ? DisplayNameSource.unnamed
        : DisplayNameSource.filename,
    isPendingReview: pending,
    createdAt: now,
    updatedAt: now,
  );
}

Playlist _playlist({required String id, required String name}) {
  final now = DateTime.utc(2026, 7, 7);
  return Playlist(
    id: id,
    name: name,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
}

PlaylistItem _playlistItem({
  required String id,
  required String playlistId,
  required String songId,
  int sortOrder = 0,
}) {
  return PlaylistItem(
    id: id,
    playlistId: playlistId,
    songId: songId,
    sortOrder: sortOrder,
    createdAt: DateTime.utc(2026, 7, 7),
  );
}
