import 'dart:convert';

import 'package:music_core/music_core.dart';

const syncProtocolAppId = 'personal_music_sync';
const syncProtocolVersion = 1;

class SyncQrPayload {
  const SyncQrPayload({
    required this.host,
    required this.port,
    required this.sessionId,
    required this.connectCode,
    this.app = syncProtocolAppId,
    this.version = syncProtocolVersion,
  });

  factory SyncQrPayload.fromSession(SyncSession session) {
    return SyncQrPayload(
      host: session.host,
      port: session.port,
      sessionId: session.sessionId,
      connectCode: session.connectCode,
    );
  }

  factory SyncQrPayload.fromJson(Map<String, Object?> json) {
    final app = json['app'] as String?;
    final version = json['version'] as int?;
    if (app != syncProtocolAppId || version != syncProtocolVersion) {
      throw const AppError('invalid_qr_payload', '二维码不是当前应用的同步载荷');
    }
    return SyncQrPayload(
      app: app!,
      version: version!,
      host: json['host']! as String,
      port: json['port']! as int,
      sessionId: json['session_id']! as String,
      connectCode: json['connect_code']! as String,
    );
  }

  factory SyncQrPayload.fromJsonText(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw const AppError('invalid_qr_payload', '二维码内容格式无效');
    }
    return SyncQrPayload.fromJson(decoded);
  }

  final String app;
  final int version;
  final String host;
  final int port;
  final String sessionId;
  final String connectCode;

  Map<String, Object?> toJson() {
    return {
      'app': app,
      'version': version,
      'host': host,
      'port': port,
      'session_id': sessionId,
      'connect_code': connectCode,
    };
  }

  String toJsonText() => jsonEncode(toJson());
}

class SyncConnectRequest {
  const SyncConnectRequest({
    required this.sessionId,
    required this.connectCode,
  });

  factory SyncConnectRequest.fromJson(Map<String, Object?> json) {
    return SyncConnectRequest(
      sessionId: json['session_id']! as String,
      connectCode: json['connect_code']! as String,
    );
  }

  final String sessionId;
  final String connectCode;

  Map<String, Object?> toJson() {
    return {'session_id': sessionId, 'connect_code': connectCode};
  }
}

class SyncConnectResponse {
  const SyncConnectResponse({required this.ok, required this.message});

  factory SyncConnectResponse.fromJson(Map<String, Object?> json) {
    return SyncConnectResponse(
      ok: json['ok']! as bool,
      message: json['message']! as String,
    );
  }

  final bool ok;
  final String message;

  Map<String, Object?> toJson() {
    return {'ok': ok, 'message': message};
  }
}
