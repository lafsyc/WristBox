import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../commands/command_protocol.dart';
import '../features/devices/services/device_log_archive.dart';
import 'debug_server_auth.dart';
import 'debug_server_mdns.dart';
import 'debug_server_protocol.dart';

/// Network-facing debug server for OronBox clients.
///
/// The server deliberately exposes a small, typed HTTP surface instead of the
/// internal command bus. Uploaded resources are staged locally and then handed
/// to the existing daemon queue, so a client never sends a filesystem path to
/// another machine.
class DebugServer {
  DebugServer({
    required this.serverId,
    required this.displayName,
    required this.platform,
    required this.identity,
    required this.host,
    required this.commandBus,
    this.port = defaultDebugServerPort,
    this.maxUploadBytes = 256 * 1024 * 1024,
    Future<Directory> Function()? temporaryDirectoryProvider,
    DateTime Function()? now,
    this.onChanged,
    Iterable<DebugAuthorizedClient> authorizedClients = const [],
    this.onAuthorizationChanged,
  }) : _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _now = now ?? DateTime.now,
       authenticator = DebugServerAuthenticator(
         serverId: serverId,
         serverIdentity: identity,
         now: now,
         authorizedClients: authorizedClients,
       );

  final String serverId;
  final String displayName;
  final String platform;
  final DebugRsaKeyPair identity;
  final InternetAddress host;
  final int port;
  final int maxUploadBytes;
  final OronBoxCommandBus commandBus;
  final void Function()? onChanged;
  final void Function()? onAuthorizationChanged;
  final DebugServerAuthenticator authenticator;
  final Future<Directory> Function() _temporaryDirectoryProvider;
  final DateTime Function() _now;
  final _sessions = <String, _DebugSession>{};
  final _logOperations = <String, _DebugLogOperation>{};
  DebugMdnsAdvertiser? _mdns;

  HttpServer? _httpServer;
  Directory? _stagingDirectory;
  Timer? _maintenanceTimer;
  bool _mdnsAvailable = false;

  bool get isRunning => _httpServer != null;
  int get boundPort => _httpServer?.port ?? port;
  List<DebugAuthorizedClient> get pendingClients =>
      authenticator.pendingClients;
  List<DebugAuthorizedClient> get authorizedClients =>
      authenticator.authorizedClients;

  DebugServerInfo get info => DebugServerInfo(
    serverId: serverId,
    displayName: displayName,
    platform: platform,
    port: boundPort,
    protocolVersion: odsProtocolVersion,
    secure: false,
    capabilities: _mdnsAvailable
        ? odsCapabilities
        : odsCapabilities.difference(const {'discovery.mdns'}),
    fingerprint: identity.publicKey.fingerprint,
  );

  Future<DebugServerInfo> start() async {
    if (_httpServer != null) return info;
    final staging = await _temporaryDirectoryProvider();
    _stagingDirectory = Directory(
      '${staging.path}${Platform.pathSeparator}oronbox-debug-server',
    );
    await _stagingDirectory!.create(recursive: true);
    _httpServer = await HttpServer.bind(host, port, shared: true);
    _httpServer!.listen(_handleRequest, onError: (_) {});
    _mdns = DebugMdnsAdvertiser(
      serverId: serverId,
      displayName: displayName,
      platform: platform,
      port: boundPort,
      fingerprint: identity.publicKey.fingerprint,
    );
    _mdnsAvailable = await _mdns!.start();
    _maintenanceTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _purgeExpiredAuthState(),
    );
    onChanged?.call();
    return info;
  }

  Future<void> stop() async {
    final server = _httpServer;
    _httpServer = null;
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    _sessions.clear();
    _logOperations.clear();
    await _mdns?.stop();
    _mdns = null;
    _mdnsAvailable = false;
    await server?.close(force: true);
    onChanged?.call();
  }

  void approveClient(DebugAuthorizedClient client) {
    authenticator.approveClient(client);
    onAuthorizationChanged?.call();
    onChanged?.call();
  }

  void rejectClient(String fingerprint) {
    authenticator.rejectClient(fingerprint);
    onChanged?.call();
  }

  void revokeClient(String fingerprint) {
    authenticator.revokeClient(fingerprint);
    _sessions.removeWhere((_, session) => session.fingerprint == fingerprint);
    onAuthorizationChanged?.call();
    onChanged?.call();
  }

  void _purgeExpiredAuthState() {
    authenticator.clearExpiredChallenges();
    final current = _now().toUtc();
    _sessions.removeWhere((_, session) => current.isAfter(session.expiresAt));
    _logOperations.removeWhere(
      (_, operation) =>
          operation.finishedAt != null &&
          current.difference(operation.finishedAt!) > const Duration(hours: 1),
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/debug/v1/info') {
        return await _sendJson(request, 200, {
          ...info.toJson(),
          'publicKey': identity.publicKey.toJson(),
        });
      }
      if (request.method == 'POST' &&
          request.uri.path == '/debug/v1/auth/challenge') {
        return await _issueChallenge(request);
      }
      if (request.method == 'POST' &&
          request.uri.path == '/debug/v1/auth/verify') {
        return await _verifyChallenge(request);
      }

      final session = _sessionFor(request);
      if (session == null) return _sendError(request, 401, 'unauthorized');
      if (request.method == 'GET' && request.uri.path == '/debug/v1/devices') {
        if (!_hasScope(session, 'device.list')) {
          return _sendError(request, 403, 'scope_required');
        }
        return await _executeJson(
          request,
          const OronBoxCommand(method: 'device.paired'),
        );
      }
      if (request.method == 'GET' &&
          request.uri.path == '/debug/v1/device/list') {
        if (!_hasScope(session, 'device.list')) {
          return _sendError(request, 403, 'scope_required');
        }
        return await _executeJson(
          request,
          const OronBoxCommand(method: 'device.paired'),
        );
      }
      if (request.method == 'GET' &&
          request.uri.path == '/debug/v1/device/current') {
        if (!_hasScope(session, 'device.read')) {
          return _sendError(request, 403, 'scope_required');
        }
        return await _executeJson(
          request,
          const OronBoxCommand(method: 'device.status'),
        );
      }
      if (request.method == 'GET' &&
          request.uri.path == '/debug/v1/device/status') {
        if (!_hasScope(session, 'device.read')) {
          return _sendError(request, 403, 'scope_required');
        }
        return await _executeJson(
          request,
          const OronBoxCommand(method: 'device.status'),
        );
      }
      if (request.method == 'POST' &&
          request.uri.path == '/debug/v1/device/connect') {
        if (!_hasScope(session, 'device.control')) {
          return _sendError(request, 403, 'scope_required');
        }
        final body = await _readJson(request, maxBytes: 64 * 1024);
        final deviceId = body['deviceId']?.toString().trim() ?? '';
        if (deviceId.isEmpty) {
          return _sendError(request, 400, 'device_id_required');
        }
        return await _executeJson(
          request,
          OronBoxCommand(
            method: 'device.connect',
            params: {'device': deviceId},
          ),
        );
      }
      if (request.method == 'POST' &&
          request.uri.path == '/debug/v1/device/disconnect') {
        if (!_hasScope(session, 'device.control')) {
          return _sendError(request, 403, 'scope_required');
        }
        final body = await _readJson(request, maxBytes: 64 * 1024);
        final deviceId = body['deviceId']?.toString().trim();
        return await _executeJson(
          request,
          OronBoxCommand(
            method: 'device.disconnect',
            params: {
              if (deviceId != null && deviceId.isNotEmpty) 'device': deviceId,
            },
          ),
        );
      }
      final appMatch = RegExp(r'^/debug/v1/app(?:/([^/]+))?$')
          .firstMatch(request.uri.path);
      if (request.method == 'POST' &&
          request.uri.path == '/debug/v1/app/launch') {
        if (!_hasScope(session, 'app.launch')) {
          return _sendError(request, 403, 'scope_required');
        }
        final body = await _readJson(request, maxBytes: 64 * 1024);
        final packageName =
            body['packageName']?.toString().trim() ??
            body['package']?.toString().trim() ??
            '';
        if (packageName.isEmpty) {
          return _sendError(request, 400, 'package_required');
        }
        return await _executeDeviceCommand(
          request,
          'app.launch',
          params: {'package': packageName},
        );
      }
      if (appMatch != null) {
        if (request.method == 'GET' && !_hasScope(session, 'app.list')) {
          return _sendError(request, 403, 'scope_required');
        }
        if (request.method == 'DELETE' &&
            !_hasScope(session, 'app.uninstall')) {
          return _sendError(request, 403, 'scope_required');
        }
        if (request.method == 'POST' && !_hasScope(session, 'app.launch')) {
          return _sendError(request, 403, 'scope_required');
        }
        final packageName = appMatch.group(1);
        if (request.method == 'GET' && packageName == null) {
          return await _executeDeviceCommand(request, 'app.list');
        }
        if (request.method == 'POST' &&
            packageName != null &&
            request.uri.path.endsWith('/launch')) {
          return await _executeDeviceCommand(
            request,
            'app.launch',
            params: {'package': Uri.decodeComponent(packageName)},
          );
        }
        if (request.method == 'DELETE' && packageName != null) {
          return await _executeDeviceCommand(
            request,
            'app.uninstall',
            params: {'package': Uri.decodeComponent(packageName)},
          );
        }
      }
      if (request.method == 'POST' &&
          RegExp(r'^/debug/v1/app/[^/]+/launch$').hasMatch(request.uri.path)) {
        if (!_hasScope(session, 'app.launch')) {
          return _sendError(request, 403, 'scope_required');
        }
        final packageName = Uri.decodeComponent(request.uri.path.split('/')[4]);
        return await _executeDeviceCommand(
          request,
          'app.launch',
          params: {'package': packageName},
        );
      }
      final watchfaceMatch = RegExp(r'^/debug/v1/watchface(?:/([^/]+))?$')
          .firstMatch(request.uri.path);
      if (request.method == 'POST' &&
          request.uri.path == '/debug/v1/watchface/set') {
        if (!_hasScope(session, 'watchface.set')) {
          return _sendError(request, 403, 'scope_required');
        }
        final body = await _readJson(request, maxBytes: 64 * 1024);
        final watchfaceId = body['id']?.toString().trim() ?? '';
        if (watchfaceId.isEmpty) {
          return _sendError(request, 400, 'watchface_id_required');
        }
        return await _executeDeviceCommand(
          request,
          'watchface.set',
          params: {'id': watchfaceId},
        );
      }
      if (watchfaceMatch != null) {
        if (request.method == 'GET' && !_hasScope(session, 'watchface.list')) {
          return _sendError(request, 403, 'scope_required');
        }
        if (request.method == 'DELETE' &&
            !_hasScope(session, 'watchface.remove')) {
          return _sendError(request, 403, 'scope_required');
        }
        if (request.method == 'POST' && !_hasScope(session, 'watchface.set')) {
          return _sendError(request, 403, 'scope_required');
        }
        final watchfaceId = watchfaceMatch.group(1);
        if (request.method == 'GET' && watchfaceId == null) {
          return await _executeDeviceCommand(request, 'watchface.list');
        }
        if (request.method == 'POST' &&
            watchfaceId != null &&
            request.uri.path.endsWith('/set')) {
          return await _executeDeviceCommand(
            request,
            'watchface.set',
            params: {'id': Uri.decodeComponent(watchfaceId)},
          );
        }
        if (request.method == 'DELETE' && watchfaceId != null) {
          return await _executeDeviceCommand(
            request,
            'watchface.remove',
            params: {'id': Uri.decodeComponent(watchfaceId)},
          );
        }
      }
      if (request.method == 'POST' &&
          RegExp(r'^/debug/v1/watchface/[^/]+/set$')
              .hasMatch(request.uri.path)) {
        if (!_hasScope(session, 'watchface.set')) {
          return _sendError(request, 403, 'scope_required');
        }
        final watchfaceId = Uri.decodeComponent(request.uri.path.split('/')[4]);
        return await _executeDeviceCommand(
          request,
          'watchface.set',
          params: {'id': watchfaceId},
        );
      }
      if (request.method == 'POST' &&
          request.uri.path == '/debug/v1/device-logs') {
        if (!_hasScope(session, 'diagnostics.read')) {
          return _sendError(request, 403, 'scope_required');
        }
        return await _startDeviceLogExport(request);
      }
      final logMatch = RegExp(
        r'^/debug/v1/device-logs/([^/]+)(?:/(archive|current-log|cancel))?$',
      ).firstMatch(request.uri.path);
      if (logMatch != null) {
        if (!_hasScope(session, 'diagnostics.read')) {
          return _sendError(request, 403, 'scope_required');
        }
        final operation = _logOperations[logMatch.group(1)!];
        if (operation == null) return _sendError(request, 404, 'not_found');
        final suffix = logMatch.group(2);
        if (suffix == 'cancel') {
          if (request.method != 'POST') {
            return _sendError(request, 405, 'method_not_allowed');
          }
          await commandBus.execute(
            const OronBoxCommand(method: 'device.logs.cancel'),
          );
          operation.state = OdsOperationState.cancelled;
          operation.finishedAt = _now().toUtc();
          operation.message = 'cancelled';
          return await _sendJson(request, 200, operation.toJson());
        }
        if (suffix == null) {
          if (request.method != 'GET') {
            return _sendError(request, 405, 'method_not_allowed');
          }
          return await _sendJson(request, 200, operation.toJson());
        }
        if (request.method != 'GET' ||
            operation.state != OdsOperationState.completed) {
          return _sendError(request, 409, 'operation_not_completed');
        }
        final file = suffix == 'archive'
            ? operation.archiveFile
            : operation.currentLogFile;
        if (file == null || !await file.exists()) {
          return _sendError(request, 404, 'file_not_available');
        }
        return await _sendFile(
          request,
          file,
          currentLog: suffix == 'current-log',
        );
      }
      if (request.method == 'POST' && request.uri.path == '/debug/v1/install') {
        if (!_hasScope(session, 'install.upload')) {
          return _sendError(request, 403, 'scope_required');
        }
        return await _install(request);
      }
      final queueMatch = RegExp(r'^/debug/v1/tasks/([^/]+)(?:/(cancel))?$')
          .firstMatch(request.uri.path);
      if (queueMatch != null) {
        if (!_hasScope(session, 'task.status')) {
          return _sendError(request, 403, 'scope_required');
        }
        final taskId = queueMatch.group(1)!;
        if (queueMatch.group(2) == 'cancel') {
          if (request.method != 'POST' || !_hasScope(session, 'task.cancel')) {
            return _sendError(request, 403, 'scope_required');
          }
          return await _executeJson(
            request,
            OronBoxCommand(method: 'queue.cancel', params: {'id': taskId}),
          );
        }
        if (request.method != 'GET') {
          return _sendError(request, 405, 'method_not_allowed');
        }
        return await _executeJson(
          request,
          OronBoxCommand(method: 'queue.get', params: {'id': taskId}),
        );
      }
      return _sendError(request, 404, 'not_found');
    } on FormatException catch (error) {
      return _sendError(
        request,
        400,
        'invalid_request',
        message: error.message,
      );
    } catch (_) {
      return _sendError(request, 500, 'internal_error');
    }
  }

  Future<void> _issueChallenge(HttpRequest request) async {
    final body = await _readJson(request, maxBytes: 64 * 1024);
    final key = DebugRsaPublicKey.fromJson(
      (body['publicKey'] as Map).cast<String, Object?>(),
    );
    final scopes = _readScopes(body['scopes']);
    final clientId = body['clientId']?.toString().trim() ?? '';
    if (clientId.isEmpty || scopes.isEmpty) {
      return _sendError(request, 400, 'invalid_challenge_request');
    }
    final challenge = authenticator.issueChallenge(
      clientId: clientId,
      clientKey: key,
      scopes: scopes,
      displayName: body['displayName']?.toString(),
    );
    return _sendJson(request, 200, {
      'challenge': challenge.toJson(),
      'server': {...info.toJson(), 'publicKey': identity.publicKey.toJson()},
    });
  }

  Future<void> _verifyChallenge(HttpRequest request) async {
    final body = await _readJson(request, maxBytes: 128 * 1024);
    final key = DebugRsaPublicKey.fromJson(
      (body['publicKey'] as Map).cast<String, Object?>(),
    );
    final signatureText = body['signature']?.toString() ?? '';
    final signature = base64Url.decode(
      '$signatureText${'=' * ((4 - signatureText.length % 4) % 4)}',
    );
    final result = authenticator.verify(
      challengeId: body['challengeId']?.toString() ?? '',
      clientId: body['clientId']?.toString() ?? '',
      clientKey: key,
      scopes: _readScopes(body['scopes']),
      signature: signature,
    );
    if (result.status == DebugAuthStatus.authorized) {
      final token = _newToken();
      _sessions[token] = _DebugSession(
        token: token,
        fingerprint: result.fingerprint!,
        scopes: _readScopes(body['scopes']),
        expiresAt: _now().toUtc().add(const Duration(minutes: 30)),
      );
      return _sendJson(request, 200, {
        'status': 'authorized',
        'sessionId': token,
        'token': token,
        'scopes': _readScopes(body['scopes']).toList()..sort(),
        'expiresAt': _sessions[token]!.expiresAt.toIso8601String(),
      });
    }
    if (result.status == DebugAuthStatus.pendingApproval) {
      onChanged?.call();
      return await _sendJson(request, 202, {
        'status': 'pending_approval',
        'fingerprint': result.fingerprint,
      });
    }
    return _sendError(request, 401, 'authentication_rejected');
  }

  Future<void> _startDeviceLogExport(HttpRequest request) async {
    final body = await _readJson(request, maxBytes: 64 * 1024);
    final operation = _DebugLogOperation(
      id: _newToken(),
      deviceId: body['deviceId']?.toString(),
    );
    _logOperations[operation.id] = operation;
    unawaited(_runDeviceLogExport(operation));
    return _sendJson(request, 202, operation.toJson());
  }

  Future<void> _runDeviceLogExport(_DebugLogOperation operation) async {
    operation.state = OdsOperationState.running;
    operation.stage = 'preparing';
    final subscription = commandBus.events.listen((event) {
      if (event.event != 'device.log.progress' ||
          event.data['operationId']?.toString() != operation.id) {
        return;
      }
      operation.stage = event.data['stage']?.toString();
      operation.message = event.data['message']?.toString();
      operation.progress = (event.data['progress'] as num?)?.toDouble();
      operation.fileName = event.data['fileName']?.toString();
      operation.bytesDone = (event.data['bytesDone'] as num?)?.toInt();
      operation.bytesTotal = (event.data['bytesTotal'] as num?)?.toInt();
    });
    try {
      final result = await commandBus.execute(
        OronBoxCommand(
          method: 'device.logs.pull',
          params: {
            'operationId': operation.id,
            if (operation.deviceId != null) 'deviceId': operation.deviceId,
          },
        ),
      );
      if (!result.ok) {
        operation.state = OdsOperationState.failed;
        operation.finishedAt = _now().toUtc();
        operation.message = result.error?.message ?? 'device log export failed';
        operation.error = result.error?.toJson();
        return;
      }
      final value = (result.value as Map).cast<String, Object?>();
      final bytes = Uint8List.fromList(
        (value['bytes'] as List? ?? const [])
            .whereType<num>()
            .map((item) => item.toInt() & 0xff)
            .toList(growable: false),
      );
      if (bytes.isEmpty) {
        throw StateError('device returned an empty log archive');
      }
      final extension = _archiveExtension(value['name']?.toString() ?? '');
      final archive = File(
        '${_stagingDirectory!.path}${Platform.pathSeparator}device-log-${operation.id}$extension',
      );
      await _writeAtomic(archive, bytes);
      operation.archiveFile = archive;
      final currentBytes = Uint8List.fromList(
        (value['currentLogBytes'] as List? ?? const [])
            .whereType<num>()
            .map((item) => item.toInt() & 0xff)
            .toList(growable: false),
      );
      final extracted = currentBytes.isNotEmpty
          ? currentBytes
          : extractCurrentDeviceLog(bytes);
      if (extracted != null && extracted.isNotEmpty) {
        final current = File(
          '${_stagingDirectory!.path}${Platform.pathSeparator}device-log-${operation.id}-tmp.log',
        );
        await _writeAtomic(current, extracted);
        operation.currentLogFile = current;
      }
      operation.state = OdsOperationState.completed;
      operation.finishedAt = _now().toUtc();
      operation.stage = 'completed';
      operation.progress = 1;
      operation.fileName = value['name']?.toString();
      operation.bytesDone = bytes.length;
      operation.bytesTotal = bytes.length;
    } catch (error) {
      operation.state = OdsOperationState.failed;
      operation.finishedAt = _now().toUtc();
      operation.stage = 'failed';
      operation.message = error.toString();
      operation.error = {'code': 'internal', 'message': error.toString()};
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _install(HttpRequest request) async {
    final metadata = DebugInstallRequest.fromJson({
      'fileName': request.headers.value('x-oronbox-file-name'),
      'type': request.headers.value('x-oronbox-type'),
      'sha256': request.headers.value('x-oronbox-sha256'),
      'size': int.tryParse(request.headers.value('x-oronbox-size') ?? ''),
      if (request.headers.value('x-oronbox-device-id') != null)
        'deviceId': request.headers.value('x-oronbox-device-id'),
    });
    if (metadata.size > maxUploadBytes) {
      return _sendError(request, 413, 'upload_too_large');
    }
    final contentLength = request.headers.contentLength;
    if (contentLength >= 0 && contentLength != metadata.size) {
      return _sendError(request, 400, 'size_mismatch');
    }
    final safeName = _safeFileName(metadata.fileName);
    final file = File(
      '${_stagingDirectory!.path}${Platform.pathSeparator}${_newToken()}-$safeName',
    );
    final digestSink = _DigestSink();
    final digestInput = sha256.startChunkedConversion(digestSink);
    final output = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in request) {
        received += chunk.length;
        if (received > maxUploadBytes || received > metadata.size) {
          throw const _UploadFailure(413, 'upload_size_exceeded');
        }
        digestInput.add(chunk);
        output.add(chunk);
      }
      digestInput.close();
      await output.close();
      if (received != metadata.size ||
          digestSink.value.toString() != metadata.sha256) {
        throw const _UploadFailure(400, 'sha256_or_size_mismatch');
      }
      final queued = await commandBus.execute(
        OronBoxCommand(
          method: 'task.enqueue',
          params: {
            'command': {
              'method': 'install.local',
              'params': {
                'path': file.path,
                'fileName': safeName,
                'type': metadata.type,
                'deleteAfter': true,
                if (metadata.deviceId != null) 'device': metadata.deviceId,
                'title': 'Debug install $safeName',
              },
            },
          },
        ),
      );
      if (!queued.ok) {
        await file.delete();
        return _sendCommandFailure(request, queued);
      }
      return await _sendJson(request, 202, {
        'taskId': (queued.value as Map)['taskId'],
        'fileName': safeName,
        'sha256': metadata.sha256,
      });
    } on _UploadFailure catch (error) {
      await output.close();
      await _deleteIfExists(file);
      return _sendError(request, error.status, error.code);
    } catch (_) {
      await output.close();
      await _deleteIfExists(file);
      rethrow;
    }
  }

  Future<void> _executeDeviceCommand(
    HttpRequest request,
    String method, {
    Map<String, Object?> params = const {},
  }) async {
    final deviceId = request.uri.queryParameters['deviceId'];
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      final session = _sessionFor(request);
      if (session == null || !_hasScope(session, 'device.control')) {
        return _sendError(request, 403, 'scope_required');
      }
      final connected = await commandBus.execute(
        OronBoxCommand(method: 'device.connect', params: {'device': deviceId}),
      );
      if (!connected.ok) return _sendCommandFailure(request, connected);
    }
    return _executeJson(
      request,
      OronBoxCommand(method: method, params: params),
    );
  }

  _DebugSession? _sessionFor(HttpRequest request) {
    final value = request.headers.value('authorization');
    if (value == null || !value.startsWith('Bearer ')) return null;
    final token = value.substring('Bearer '.length).trim();
    final session = _sessions[token];
    if (session == null || _now().toUtc().isAfter(session.expiresAt)) {
      _sessions.remove(token);
      return null;
    }
    return session;
  }

  bool _hasScope(_DebugSession session, String scope) =>
      session.scopes.contains(scope);

  Future<void> _executeJson(HttpRequest request, OronBoxCommand command) async {
    final result = await commandBus.execute(command);
    if (!result.ok) return _sendCommandFailure(request, result);
    return _sendJson(request, 200, {'result': result.value});
  }

  Future<Map<String, Object?>> _readJson(
    HttpRequest request, {
    required int maxBytes,
  }) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw const FormatException('Request too large');
      }
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map) throw const FormatException('JSON object required');
    return value.cast<String, Object?>();
  }

  void _sendCommandFailure(HttpRequest request, CommandResult result) {
    _sendJson(request, 502, {'error': result.error?.toJson()});
  }

  void _sendError(
    HttpRequest request,
    int status,
    String code, {
    String? message,
  }) {
    _sendJson(request, status, {
      'error': {'code': code, 'message': message ?? code},
    });
  }

  Future<void> _sendJson(HttpRequest request, int status, Object value) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set('cache-control', 'no-store');
    response.write(jsonEncode(value));
    await response.close();
  }

  Future<void> _sendFile(
    HttpRequest request,
    File file, {
    required bool currentLog,
  }) async {
    final response = request.response;
    response.statusCode = 200;
    final lower = file.path.toLowerCase();
    response.headers.contentType = currentLog
        ? ContentType('text', 'plain', charset: 'utf-8')
        : lower.endsWith('.zip')
        ? ContentType('application', 'zip')
        : lower.endsWith('.tar.gz') || lower.endsWith('.tgz')
        ? ContentType('application', 'gzip')
        : ContentType('application', 'octet-stream');
    response.headers.set('cache-control', 'no-store');
    await response.addStream(file.openRead());
    await response.close();
  }

  Future<void> _writeAtomic(File target, List<int> bytes) async {
    final temporary = File('${target.path}.part');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  }
}

class _DebugSession {
  const _DebugSession({
    required this.token,
    required this.fingerprint,
    required this.scopes,
    required this.expiresAt,
  });

  final String token;
  final String fingerprint;
  final Set<String> scopes;
  final DateTime expiresAt;
}

class _DebugLogOperation {
  _DebugLogOperation({required this.id, this.deviceId});

  final String id;
  final String? deviceId;
  OdsOperationState state = OdsOperationState.queued;
  String? stage;
  String? message;
  double? progress;
  int? bytesDone;
  int? bytesTotal;
  String? fileName;
  Map<String, Object?>? error;
  File? archiveFile;
  File? currentLogFile;
  DateTime? finishedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': 'device_logs',
    'state': state.name,
    if (deviceId != null) 'deviceId': deviceId,
    if (stage != null) 'stage': stage,
    if (message != null) 'message': message,
    if (progress != null) 'progress': progress,
    if (bytesDone != null) 'bytesDone': bytesDone,
    if (bytesTotal != null) 'bytesTotal': bytesTotal,
    if (fileName != null) 'fileName': fileName,
    if (error != null) 'error': error,
    if (archiveFile != null) 'archiveUrl': '/debug/v1/device-logs/$id/archive',
    if (currentLogFile != null)
      'currentLogUrl': '/debug/v1/device-logs/$id/current-log',
  };
}

class _UploadFailure implements Exception {
  const _UploadFailure(this.status, this.code);

  final int status;
  final String code;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest digest) {
    if (value != null) throw StateError('Digest already set');
    value = digest;
  }

  @override
  void close() {
    if (value == null) throw StateError('Digest was not set');
  }
}

Set<String> _readScopes(Object? value) {
  if (value is! List) return const {};
  final scopes = value
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toSet();
  if (!odsScopes.containsAll(scopes)) {
    throw const FormatException('Unsupported debug scope');
  }
  return scopes;
}

String _safeFileName(String value) {
  final normalized = value.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  if (name.isEmpty || name == '.' || name == '..') return 'resource.rpk';
  return name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

String _newToken() {
  final random = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  return base64Url.encode(random).replaceAll('=', '');
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) await file.delete();
}

String _archiveExtension(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.tar.gz')) return '.tar.gz';
  if (lower.endsWith('.tgz')) return '.tgz';
  if (lower.endsWith('.zip')) return '.zip';
  return '.bin';
}
