import 'package:flutter_test/flutter_test.dart';
import 'package:music_core/music_core.dart';

void main() {
  test('recognizes supported audio formats', () {
    expect(AudioFormat.fromExtension('.mp3'), AudioFormat.mp3);
    expect(AudioFormat.fromExtension('FLAC'), AudioFormat.flac);
    expect(AudioFormat.fromExtension('aac'), isNull);
  });

  test('round-trips song storage map', () {
    final now = DateTime.utc(2026, 7, 7, 10);
    final song = Song(
      id: 'song-1',
      title: '未命名音频 001',
      artist: '未知歌手',
      album: '未知专辑',
      format: AudioFormat.mp3,
      fileSize: 1234,
      fileHash: 'hash',
      localPath: 'library/audio/song-1.mp3',
      originalFileName: '001.mp3',
      displayNameSource: DisplayNameSource.unnamed,
      isPendingReview: true,
      createdAt: now,
      updatedAt: now,
    );

    final restored = Song.fromMap(song.toMap());

    expect(restored.id, song.id);
    expect(restored.title, '未命名音频 001');
    expect(restored.artist, '未知歌手');
    expect(restored.displayNameSource, DisplayNameSource.unnamed);
    expect(restored.isPendingReview, isTrue);
  });

  test('creates QR payload without long term secrets', () {
    final session = SyncSession(
      sessionId: 'session',
      connectCode: '123456',
      host: '192.168.1.10',
      port: 37891,
      createdAt: DateTime.utc(2026),
    );

    expect(session.toQrPayload(), {
      'app': 'personal_music_sync',
      'version': 1,
      'host': '192.168.1.10',
      'port': 37891,
      'session_id': 'session',
      'connect_code': '123456',
    });
  });
}
