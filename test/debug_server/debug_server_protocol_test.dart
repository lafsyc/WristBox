import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/debug_server/debug_server_protocol.dart';

void main() {
  test('server info survives JSON transport', () {
    const info = DebugServerInfo(
      serverId: 'ob-server-1',
      displayName: 'Android phone',
      platform: 'android',
      port: 43821,
      protocolVersion: 1,
      capabilities: {'device.list', 'install.upload'},
      fingerprint: 'SHA256:abc',
    );

    final restored = DebugServerInfo.fromJson(
      (jsonDecode(jsonEncode(info.toJson())) as Map).cast<String, Object?>(),
    );

    expect(restored, info);
  });

  test('auth transcript is deterministic and scope-order independent', () {
    final first = DebugAuthTranscript.encode(
      challengeId: 'challenge-1',
      serverId: 'server-1',
      clientId: 'client-1',
      serverNonce: 'server-nonce',
      clientNonce: 'client-nonce',
      clientFingerprint: 'fingerprint',
      scopes: {'install.upload', 'device.list'},
    );
    final second = DebugAuthTranscript.encode(
      challengeId: 'challenge-1',
      serverId: 'server-1',
      clientId: 'client-1',
      serverNonce: 'server-nonce',
      clientNonce: 'client-nonce',
      clientFingerprint: 'fingerprint',
      scopes: {'device.list', 'install.upload'},
    );

    expect(first, second);
    expect(utf8.decode(first), contains('challenge-1'));
  });

  test('install request rejects a path-only payload', () {
    expect(
      () => DebugInstallRequest.fromJson({'type': 'quickapp'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('ODS request and response envelopes round-trip', () {
    final request = OdsMessage.request(
      id: '7',
      method: 'device.list',
      params: {'includeDisconnected': true},
    );
    final restored = OdsMessage.fromJson(
      (jsonDecode(jsonEncode(request.toJson())) as Map).cast<String, Object?>(),
    );
    expect(restored.type, OdsMessageType.request);
    expect(restored.id, '7');
    expect(restored.method, 'device.list');
    expect(restored.toCommand().params['_odsRequestId'], '7');

    final event = OdsMessage.event(
      event: 'operation.progress',
      sequence: 12,
      data: {'progress': 0.5},
    );
    final eventRestored = OdsMessage.fromJson(
      (jsonDecode(jsonEncode(event.toJson())) as Map).cast<String, Object?>(),
    );
    expect(eventRestored.type, OdsMessageType.event);
    expect(eventRestored.sequence, 12);
    expect(eventRestored.params['progress'], 0.5);
  });

  test('ODS operation preserves optional transfer fields', () {
    const operation = OdsOperation(
      id: 'op-1',
      kind: 'device.pull',
      state: OdsOperationState.running,
      deviceId: 'device-1',
      progress: 0.25,
      bytesDone: 25,
      bytesTotal: 100,
      bytesPerSecond: 50,
      fileName: 'recording.wav',
    );
    final restored = OdsOperation.fromJson(
      (jsonDecode(jsonEncode(operation.toJson())) as Map)
          .cast<String, Object?>(),
    );
    expect(restored.id, operation.id);
    expect(restored.state, OdsOperationState.running);
    expect(restored.bytesPerSecond, 50);
    expect(restored.fileName, 'recording.wav');
  });
}
