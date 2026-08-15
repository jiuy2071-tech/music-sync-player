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
    final app = json['app'];
    final version = json['version'];
    if (app != syncProtocolAppId || version != syncProtocolVersion) {
      throw const AppError('invalid_qr_payload', '二维码不是当前应用的同步载荷');
    }
    final host = _requiredString(json, 'host', '二维码缺少电脑地址');
    final port = json['port'];
    final sessionId = _requiredString(json, 'session_id', '二维码缺少同步会话');
    final connectCode = _requiredString(json, 'connect_code', '二维码缺少连接码');
    if (host.length > 253 || host.contains(RegExp(r'[\s/?#]'))) {
      throw const AppError('invalid_qr_payload', '二维码中的电脑地址无效');
    }
    if (port is! int || port < 1 || port > 65535) {
      throw const AppError('invalid_qr_payload', '二维码中的端口无效');
    }
    if (!_safeSessionId.hasMatch(sessionId)) {
      throw const AppError('invalid_qr_payload', '二维码中的同步会话无效');
    }
    if (!_connectCode.hasMatch(connectCode)) {
      throw const AppError('invalid_qr_payload', '二维码中的连接码无效');
    }
    return SyncQrPayload(
      app: app as String,
      version: version as int,
      host: host,
      port: port,
      sessionId: sessionId,
      connectCode: connectCode,
    );
  }

  factory SyncQrPayload.fromJsonText(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?>) {
        throw const AppError('invalid_qr_payload', '二维码内容格式无效');
      }
      return SyncQrPayload.fromJson(decoded);
    } on AppError {
      rethrow;
    } on FormatException catch (error) {
      throw AppError('invalid_qr_payload', '二维码内容格式无效', cause: error);
    }
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
    final sessionId = _requiredString(json, 'session_id', '缺少同步会话');
    final connectCode = _requiredString(json, 'connect_code', '缺少连接码');
    if (!_safeSessionId.hasMatch(sessionId) ||
        !_connectCode.hasMatch(connectCode)) {
      throw const AppError('invalid_connect_request', '连接信息格式无效');
    }
    return SyncConnectRequest(sessionId: sessionId, connectCode: connectCode);
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
    final ok = json['ok'];
    final message = json['message'];
    if (ok is! bool || message is! String) {
      throw const AppError('invalid_connect_response', '同步服务连接响应格式无效');
    }
    return SyncConnectResponse(ok: ok, message: message);
  }

  final bool ok;
  final String message;

  Map<String, Object?> toJson() {
    return {'ok': ok, 'message': message};
  }
}

final RegExp _safeSessionId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
final RegExp _connectCode = RegExp(r'^\d{6}$');

String _requiredString(Map<String, Object?> json, String key, String message) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw AppError('invalid_qr_payload', message);
  }
  return value;
}
