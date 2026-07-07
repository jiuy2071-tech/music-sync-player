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
