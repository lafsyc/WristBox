import 'dart:convert';
import 'dart:typed_data';
import '../commands/command_protocol.dart';

const defaultDebugServerPort = 10517;

/// Wire version for the OronBox Debug Service (ODS).
///
/// ODS uses the existing authenticated HTTP listener. JSON requests and
/// responses use HTTP/1.1, uploads use multipart/form-data, and long-running
/// operation events use a Server-Sent Events stream. There is no second raw
/// TCP framing protocol.
const odsProtocolVersion = 1;

/// Stable ODS command capabilities.  Keep these names at the protocol edge;
/// implementation details such as Xiaomi MASS or SPP must never leak into a
/// client capability check.
const odsCapabilities = <String>{
  'auth.challenge',
  'auth.approve',
  'discovery.mdns',
  'device.list',
  'device.current',
  'device.status',
  'device.connect',
  'device.disconnect',
  'app.list',
  'app.launch',
  'app.uninstall',
  'watchface.list',
  'watchface.remove',
  'watchface.set',
  'device.logs.export',
  'device.logs.download',
  'install.upload',
  'task.status',
  'task.cancel',
};

/// Permission names are intentionally separate from capabilities.  A client
/// can discover that a command exists without being granted permission to
/// execute it.
const odsScopes = <String>{
  'device.list',
  'device.read',
  'device.control',
  'app.list',
  'app.launch',
  'app.uninstall',
  'watchface.list',
  'watchface.set',
  'watchface.remove',
  'diagnostics.read',
  'install.upload',
  'task.status',
  'task.cancel',
};

const odsJsonContentType = 'application/json; charset=utf-8';
const odsEventContentType = 'text/event-stream; charset=utf-8';
const odsUploadContentType = 'application/octet-stream';
const odsEventsPath = '/debug/v1/events';

enum OdsMessageType { request, response, event }

/// The ODS envelope is the only protocol object a transport needs to know.
/// Requests and responses share an id; events are unsolicited and carry a
/// monotonically increasing sequence number for reconnect/resume.
class OdsMessage {
  const OdsMessage({
    required this.type,
    this.id,
    this.streamId,
    this.method,
    this.event,
    this.params = const {},
    this.result,
    this.error,
    this.sequence,
  });

  final OdsMessageType type;
  final String? id;
  final String? streamId;
  final String? method;
  final String? event;
  final Map<String, Object?> params;
  final Object? result;
  final OdsError? error;
  final int? sequence;

  factory OdsMessage.request({
    required String id,
    required String method,
    String? streamId,
    Map<String, Object?> params = const {},
  }) => OdsMessage(
    type: OdsMessageType.request,
    id: id,
    streamId: streamId,
    method: method,
    params: params,
  );

  factory OdsMessage.response({
    required String id,
    String? streamId,
    Object? result,
    OdsError? error,
  }) => OdsMessage(
    type: OdsMessageType.response,
    id: id,
    streamId: streamId,
    result: result,
    error: error,
  );

  factory OdsMessage.event({
    required String event,
    required int sequence,
    String? streamId,
    Map<String, Object?> data = const {},
  }) => OdsMessage(
    type: OdsMessageType.event,
    event: event,
    streamId: streamId,
    sequence: sequence,
    params: data,
  );

  Map<String, Object?> toJson() => {
    'type': type.name,
    if (id != null) 'id': id,
    if (streamId != null) 'streamId': streamId,
    if (method != null) 'method': method,
    if (event != null) 'event': event,
    if (type == OdsMessageType.request) 'params': params,
    if (type == OdsMessageType.event) 'data': params,
    if (type == OdsMessageType.response) 'ok': error == null,
    if (type == OdsMessageType.response && error == null) 'result': result,
    if (error != null) 'error': error!.toJson(),
    if (sequence != null) 'seq': sequence,
  };

  factory OdsMessage.fromJson(Map<String, Object?> json) {
    final type = OdsMessageType.values.firstWhere(
      (value) => value.name == json['type']?.toString(),
      orElse: () => throw const FormatException('Unknown ODS message type'),
    );
    final error = json['error'];
    final rawData = type == OdsMessageType.event
        ? json['data']
        : json['params'];
    return OdsMessage(
      type: type,
      id: json['id']?.toString(),
      streamId: json['streamId']?.toString(),
      method: json['method']?.toString(),
      event: json['event']?.toString(),
      params: rawData is Map ? rawData.cast<String, Object?>() : const {},
      result: json['result'],
      error: error is Map
          ? OdsError.fromJson(error.cast<String, Object?>())
          : null,
      sequence: (json['seq'] as num?)?.toInt(),
    );
  }

  OronBoxCommand toCommand() {
    if (type != OdsMessageType.request || method == null || id == null) {
      throw const FormatException('ODS message is not a request');
    }
    return OronBoxCommand(
      method: method!,
      params: {...params, '_odsRequestId': id},
    );
  }
}

class OdsError {
  const OdsError(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    if (details != null) 'details': details,
  };

  factory OdsError.fromJson(Map<String, Object?> json) => OdsError(
    json['code']?.toString() ?? 'unknown',
    json['message']?.toString() ?? 'Unknown error',
    details: json['details'],
  );
}

enum OdsOperationState { queued, running, completed, failed, cancelled }

/// Common state for install, transfer, recording and diagnostic operations.
/// The operation endpoint is intentionally generic, like adb's shell/pull
/// commands, so clients do not need one bespoke polling protocol per feature.
class OdsOperation {
  const OdsOperation({
    required this.id,
    required this.kind,
    required this.state,
    this.deviceId,
    this.stage,
    this.message,
    this.progress,
    this.bytesDone,
    this.bytesTotal,
    this.bytesPerSecond,
    this.fileName,
    this.error,
  });

  final String id;
  final String kind;
  final OdsOperationState state;
  final String? deviceId;
  final String? stage;
  final String? message;
  final double? progress;
  final int? bytesDone;
  final int? bytesTotal;
  final int? bytesPerSecond;
  final String? fileName;
  final OdsError? error;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'state': state.name,
    if (deviceId != null) 'deviceId': deviceId,
    if (stage != null) 'stage': stage,
    if (message != null) 'message': message,
    if (progress != null) 'progress': progress,
    if (bytesDone != null) 'bytesDone': bytesDone,
    if (bytesTotal != null) 'bytesTotal': bytesTotal,
    if (bytesPerSecond != null) 'bytesPerSecond': bytesPerSecond,
    if (fileName != null) 'fileName': fileName,
    if (error != null) 'error': error!.toJson(),
  };

  factory OdsOperation.fromJson(Map<String, Object?> json) => OdsOperation(
    id: _requiredString(json, 'id'),
    kind: _requiredString(json, 'kind'),
    state: OdsOperationState.values.firstWhere(
      (value) => value.name == json['state']?.toString(),
      orElse: () => throw const FormatException('Unknown ODS operation state'),
    ),
    deviceId: json['deviceId']?.toString(),
    stage: json['stage']?.toString(),
    message: json['message']?.toString(),
    progress: (json['progress'] as num?)?.toDouble(),
    bytesDone: (json['bytesDone'] as num?)?.toInt(),
    bytesTotal: (json['bytesTotal'] as num?)?.toInt(),
    bytesPerSecond: (json['bytesPerSecond'] as num?)?.toInt(),
    fileName: json['fileName']?.toString(),
    error: json['error'] is Map
        ? OdsError.fromJson((json['error'] as Map).cast<String, Object?>())
        : null,
  );
}

class DebugServerInfo {
  const DebugServerInfo({
    required this.serverId,
    required this.displayName,
    required this.platform,
    required this.port,
    required this.protocolVersion,
    required this.capabilities,
    required this.fingerprint,
    this.secure = false,
    this.discoveryService = '_oronbox-debug._tcp.local',
    this.certificateFingerprint,
  });

  final String serverId;
  final String displayName;
  final String platform;
  final int port;
  final int protocolVersion;
  final Set<String> capabilities;
  final String fingerprint;
  final bool secure;
  final String discoveryService;
  final String? certificateFingerprint;

  Map<String, Object?> toJson() => {
    'serverId': serverId,
    'displayName': displayName,
    'platform': platform,
    'port': port,
    'protocolVersion': protocolVersion,
    'capabilities': capabilities.toList()..sort(),
    'fingerprint': fingerprint,
    'secure': secure,
    'transport': 'http',
    'auth': 'challenge-rsa',
    'discoveryService': discoveryService,
    if (certificateFingerprint != null)
      'certificateFingerprint': certificateFingerprint,
  };

  factory DebugServerInfo.fromJson(Map<String, Object?> json) {
    final capabilities = json['capabilities'];
    return DebugServerInfo(
      serverId: _requiredString(json, 'serverId'),
      displayName: _requiredString(json, 'displayName'),
      platform: _requiredString(json, 'platform'),
      port: _requiredInt(json, 'port'),
      protocolVersion: _requiredInt(json, 'protocolVersion'),
      capabilities: capabilities is List
          ? capabilities.map((value) => value.toString()).toSet()
          : const {},
      fingerprint: _requiredString(json, 'fingerprint'),
      secure: json['secure'] == true,
      discoveryService:
          json['discoveryService']?.toString() ?? '_oronbox-debug._tcp.local',
      certificateFingerprint: json['certificateFingerprint']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DebugServerInfo &&
      other.serverId == serverId &&
      other.displayName == displayName &&
      other.platform == platform &&
      other.port == port &&
      other.protocolVersion == protocolVersion &&
      other.capabilities.length == capabilities.length &&
      other.capabilities.containsAll(capabilities) &&
      other.fingerprint == fingerprint &&
      other.secure == secure &&
      other.discoveryService == discoveryService &&
      other.certificateFingerprint == certificateFingerprint;

  @override
  int get hashCode => Object.hash(
    serverId,
    displayName,
    platform,
    port,
    protocolVersion,
    Object.hashAll(capabilities),
    fingerprint,
    secure,
    discoveryService,
    certificateFingerprint,
  );
}

class DebugAuthChallenge {
  const DebugAuthChallenge({
    required this.challengeId,
    required this.serverId,
    required this.serverNonce,
    required this.clientNonce,
    required this.clientFingerprint,
    required this.scopes,
    required this.expiresAt,
  });

  final String challengeId;
  final String serverId;
  final String serverNonce;
  final String clientNonce;
  final String clientFingerprint;
  final Set<String> scopes;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
    'challengeId': challengeId,
    'serverId': serverId,
    'serverNonce': serverNonce,
    'clientNonce': clientNonce,
    'clientFingerprint': clientFingerprint,
    'scopes': scopes.toList()..sort(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

class DebugInstallRequest {
  const DebugInstallRequest({
    required this.fileName,
    required this.type,
    required this.sha256,
    required this.size,
    this.deviceId,
  });

  final String fileName;
  final String type;
  final String sha256;
  final int size;
  final String? deviceId;

  factory DebugInstallRequest.fromJson(Map<String, Object?> json) {
    final fileName = json['fileName']?.toString().trim() ?? '';
    final type = json['type']?.toString().trim() ?? '';
    final sha256 = json['sha256']?.toString().trim() ?? '';
    final size = json['size'];
    if (fileName.isEmpty || type.isEmpty || sha256.isEmpty || size is! num) {
      throw const FormatException(
        'fileName, type, sha256, and numeric size are required',
      );
    }
    if (size < 0 || size > 256 * 1024 * 1024) {
      throw const FormatException('Resource size is outside the allowed range');
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
      throw const FormatException('sha256 must be a 64-character hex string');
    }
    return DebugInstallRequest(
      fileName: fileName,
      type: type,
      sha256: sha256.toLowerCase(),
      size: size.toInt(),
      deviceId: json['deviceId']?.toString(),
    );
  }

  Map<String, Object?> toJson() => {
    'fileName': fileName,
    'type': type,
    'sha256': sha256,
    'size': size,
    if (deviceId != null) 'deviceId': deviceId,
  };
}

class DebugAuthTranscript {
  const DebugAuthTranscript._();

  static Uint8List encode({
    required String challengeId,
    required String serverId,
    required String clientId,
    required String serverNonce,
    required String clientNonce,
    required String clientFingerprint,
    required Set<String> scopes,
  }) {
    final value = [
      'oronbox-debug-auth-v1',
      challengeId,
      serverId,
      clientId,
      serverNonce,
      clientNonce,
      clientFingerprint,
      [...scopes]..sort(),
    ];
    return Uint8List.fromList(utf8.encode(jsonEncode(value)));
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('Missing $key');
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) throw FormatException('Missing $key');
  return value.toInt();
}
