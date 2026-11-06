import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/commands/command_protocol.dart';
import 'package:oronbox/src/debug_server/debug_server.dart';
import 'package:oronbox/src/debug_server/debug_server_auth.dart';
import 'package:oronbox/src/debug_server/debug_server_protocol.dart';
import 'package:oronbox/src/features/devices/services/device_log_archive.dart';

void main() {
  test('extracts the current offline log from a compressed device archive', () {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('log/offlinelog/tmp.log', utf8.encode('run')))
      ..addFile(ArchiveFile.bytes('log/offlinelog/log1.gz', [1, 2, 3]));
    final tar = TarEncoder().encodeBytes(archive);
    final bytes = GZipEncoder().encodeBytes(tar);
    expect(utf8.decode(extractCurrentDeviceLog(bytes)!), 'run');
  });

  test('authenticates and streams an install into the host queue', () async {
    final serverIdentity = DebugRsaKeyPair.generate();
    final clientIdentity = DebugRsaKeyPair.generate();
    final host = _RecordingHost();
    final server = DebugServer(
      serverId: 'server-1',
      displayName: 'Test OronBox',
      platform: 'test',
      identity: serverIdentity,
      host: InternetAddress.loopbackIPv4,
      commandBus: host,
      temporaryDirectoryProvider: () async => Directory.systemTemp,
    );
    server.approveClient(
      DebugAuthorizedClient(
        fingerprint: clientIdentity.publicKey.fingerprint,
        publicKey: clientIdentity.publicKey,
        displayName: 'VS Code',
        scopes: {'app.list', 'install.upload'},
      ),
    );
    await server.start();
    final http = HttpClient();
    addTearDown(() async {
      http.close(force: true);
      await server.stop();
      await host.close();
    });

    final info = await _jsonRequest(
      http,
      server.boundPort,
      'GET',
      '/debug/v1/info',
    );
    expect(info.statusCode, 200);
    expect(info.body['serverId'], 'server-1');
    expect(info.body['secure'], isFalse);
    expect(info.body['transport'], 'http');
    expect(info.body['auth'], 'challenge-rsa');
    final advertisedCapabilities = (info.body['capabilities'] as List)
        .map((value) => value.toString())
        .toSet();
    expect(
      advertisedCapabilities,
      containsAll(odsCapabilities.difference(const {'discovery.mdns'})),
    );
    expect(advertisedCapabilities.difference(odsCapabilities), isEmpty);

    final unsupportedScope = await _jsonRequest(
      http,
      server.boundPort,
      'POST',
      '/debug/v1/auth/challenge',
      body: {
        'clientId': 'invalid-client',
        'displayName': 'Invalid client',
        'publicKey': clientIdentity.publicKey.toJson(),
        'scopes': ['root'],
      },
    );
    expect(unsupportedScope.statusCode, 400);

    final challengeResponse = await _jsonRequest(
      http,
      server.boundPort,
      'POST',
      '/debug/v1/auth/challenge',
      body: {
        'clientId': 'vscode-1',
        'displayName': 'Test IDE',
        'publicKey': clientIdentity.publicKey.toJson(),
        'scopes': ['app.list', 'install.upload'],
      },
    );
    final challenge = (challengeResponse.body['challenge'] as Map)
        .cast<String, Object?>();
    final signature = clientIdentity.sign(
      DebugAuthTranscript.encode(
        challengeId: challenge['challengeId']!.toString(),
        serverId: challenge['serverId']!.toString(),
        clientId: 'vscode-1',
        serverNonce: challenge['serverNonce']!.toString(),
        clientNonce: challenge['clientNonce']!.toString(),
        clientFingerprint: clientIdentity.publicKey.fingerprint,
        scopes: {'app.list', 'install.upload'},
      ),
    );
    final verified = await _jsonRequest(
      http,
      server.boundPort,
      'POST',
      '/debug/v1/auth/verify',
      body: {
        'challengeId': challenge['challengeId'],
        'clientId': 'vscode-1',
        'publicKey': clientIdentity.publicKey.toJson(),
        'scopes': ['app.list', 'install.upload'],
        'signature': base64Url.encode(signature).replaceAll('=', ''),
      },
    );
    expect(verified.statusCode, 200);
    expect(verified.body['sessionId'], isNotEmpty);
    expect(verified.body['scopes'], ['app.list', 'install.upload']);
    final token = verified.body['token']!.toString();

    final deniedDeviceList = await _jsonRequest(
      http,
      server.boundPort,
      'GET',
      '/debug/v1/device/list',
      token: token,
    );
    expect(deniedDeviceList.statusCode, 403);
    expect(host.commands, isEmpty);

    final deniedImplicitConnect = await _jsonRequest(
      http,
      server.boundPort,
      'GET',
      '/debug/v1/app?deviceId=device-a',
      token: token,
    );
    expect(deniedImplicitConnect.statusCode, 403);
    expect(host.commands, isEmpty);

    final bytes = utf8.encode('fake-rpk');
    final installed = await _jsonRequest(
      http,
      server.boundPort,
      'POST',
      '/debug/v1/install',
      token: token,
      rawBody: bytes,
      headers: {
        'x-oronbox-file-name': 'demo.rpk',
        'x-oronbox-type': 'quickapp',
        'x-oronbox-size': '${bytes.length}',
        'x-oronbox-sha256': sha256.convert(bytes).toString(),
      },
    );
    expect(installed.statusCode, 202);
    expect(installed.body['taskId'], 'task-1');
    expect(host.commands.single.method, 'task.enqueue');
    final params =
        ((host.commands.single.params['command'] as Map)['params'] as Map)
            .cast<String, Object?>();
    expect(params['fileName'], 'demo.rpk');
    expect(params['type'], 'quickapp');
    expect(await File(params['path']!.toString()).exists(), isTrue);
  });
}

Future<_JsonResponse> _jsonRequest(
  HttpClient client,
  int port,
  String method,
  String path, {
  Map<String, Object?>? body,
  List<int>? rawBody,
  String? token,
  Map<String, String>? headers,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  request.headers.contentType = body == null
      ? ContentType('application', 'octet-stream')
      : ContentType.json;
  if (token != null) request.headers.set('authorization', 'Bearer $token');
  headers?.forEach(request.headers.set);
  if (body != null) {
    request.write(jsonEncode(body));
  } else if (rawBody != null) {
    request.add(rawBody);
  }
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  return _JsonResponse(response.statusCode, jsonDecode(text) as Map);
}

class _JsonResponse {
  const _JsonResponse(this.statusCode, this.body);

  final int statusCode;
  final Map body;
}

class _RecordingHost implements OronBoxCommandBus {
  final commands = <OronBoxCommand>[];
  final _events = StreamController<CommandEvent>.broadcast();

  @override
  Stream<CommandEvent> get events => _events.stream;

  @override
  Future<CommandResult> execute(OronBoxCommand command) async {
    commands.add(command);
    return const CommandResult.success({'taskId': 'task-1'});
  }

  @override
  Future<void> close() => _events.close();
}
