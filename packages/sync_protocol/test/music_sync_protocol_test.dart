import 'package:flutter_test/flutter_test.dart';
import 'package:music_core/music_core.dart';
import 'package:music_sync_protocol/music_sync_protocol.dart';

void main() {
  test('creates qr payload from sync session', () {
    final session = SyncSession(
      sessionId: 'session-1',
      connectCode: '123456',
      host: '192.168.1.10',
      port: 37891,
      createdAt: DateTime.utc(2026, 7, 7),
    );

    final payload = SyncQrPayload.fromSession(session);

    expect(payload.toJson(), {
      'app': 'personal_music_sync',
      'version': 1,
      'host': '192.168.1.10',
      'port': 37891,
      'session_id': 'session-1',
      'connect_code': '123456',
    });
  });

  test('round trips qr payload json text', () {
    const payload = SyncQrPayload(
      host: '192.168.1.10',
      port: 37891,
      sessionId: 'session-1',
      connectCode: '123456',
    );

    final restored = SyncQrPayload.fromJsonText(payload.toJsonText());

    expect(restored.host, payload.host);
    expect(restored.port, payload.port);
    expect(restored.sessionId, payload.sessionId);
    expect(restored.connectCode, payload.connectCode);
  });

  test('round trips connect request and response', () {
    const request = SyncConnectRequest(
      sessionId: 'session-1',
      connectCode: '123456',
    );
    const response = SyncConnectResponse(ok: true, message: 'connected');

    expect(SyncConnectRequest.fromJson(request.toJson()).connectCode, '123456');
    expect(SyncConnectResponse.fromJson(response.toJson()).ok, isTrue);
  });

  test('rejects malformed or unsafe qr payloads with an app error', () {
    expect(
      () => SyncQrPayload.fromJsonText('{not-json'),
      throwsA(
        isA<AppError>().having(
          (error) => error.code,
          'code',
          'invalid_qr_payload',
        ),
      ),
    );
    expect(
      () => SyncQrPayload.fromJson({
        'app': syncProtocolAppId,
        'version': syncProtocolVersion,
        'host': '192.168.1.10/path',
        'port': 70000,
        'session_id': '../session',
        'connect_code': '123',
      }),
      throwsA(isA<AppError>()),
    );
  });

  test('rejects malformed connect messages', () {
    expect(
      () => SyncConnectRequest.fromJson({
        'session_id': 'session-1',
        'connect_code': '12ab56',
      }),
      throwsA(
        isA<AppError>().having(
          (error) => error.code,
          'code',
          'invalid_connect_request',
        ),
      ),
    );
    expect(
      () => SyncConnectResponse.fromJson({'ok': 'yes', 'message': true}),
      throwsA(isA<AppError>()),
    );
  });
}
