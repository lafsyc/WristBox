import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../commands/command_protocol.dart';
import '../core/logging/logging_service.dart';
import 'debug_server.dart';
import 'debug_server_auth.dart';
import 'debug_server_protocol.dart';

class DebugServerIdentity {
  const DebugServerIdentity({required this.serverId, required this.keyPair});

  final String serverId;
  final DebugRsaKeyPair keyPair;

  Map<String, Object?> toJson() => {
    'serverId': serverId,
    'keyPair': keyPair.toJson(),
  };

  factory DebugServerIdentity.fromJson(Map<String, Object?> json) {
    return DebugServerIdentity(
      serverId: json['serverId']?.toString() ?? '',
      keyPair: DebugRsaKeyPair.fromJson(
        (json['keyPair'] as Map).cast<String, Object?>(),
      ),
    );
  }
}

class DebugServerIdentityStore {
  DebugServerIdentityStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<DebugServerIdentity> loadOrCreate() async {
    final root = await _directoryProvider();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}debug-server',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}identity.json',
    );
    if (await file.exists()) {
      final value = jsonDecode(await file.readAsString());
      if (value is Map) {
        final identity = DebugServerIdentity.fromJson(
          value.cast<String, Object?>(),
        );
        if (identity.serverId.isNotEmpty) return identity;
      }
    }
    final identity = await _generateIdentity();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(identity.toJson()), flush: true);
    await temporary.rename(file.path);
    return identity;
  }

  Future<DebugServerIdentity> _generateIdentity() async {
    // RSA key generation is CPU-bound and can take seconds on mobile. Run it
    // on a separate isolate so the first start never blocks the UI isolate.
    final keyPair = await Isolate.run<Map<String, Object?>>(
      () => DebugRsaKeyPair.generate().toJson(),
    );
    return DebugServerIdentity(
      serverId: _newServerId(),
      keyPair: DebugRsaKeyPair.fromJson(keyPair),
    );
  }

  Future<List<DebugAuthorizedClient>> loadAuthorizedClients() async {
    final root = await _directoryProvider();
    final file = File(
      '${root.path}${Platform.pathSeparator}debug-server${Platform.pathSeparator}authorized-clients.json',
    );
    if (!await file.exists()) return const [];
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! List) return const [];
      return [
        for (final item in value)
          if (item is Map)
            DebugAuthorizedClient.fromJson(item.cast<String, Object?>()),
      ];
    } catch (_) {
      // A corrupt approval file must not prevent OronBox from starting.
      return const [];
    }
  }

  Future<void> saveAuthorizedClients(
    Iterable<DebugAuthorizedClient> clients,
  ) async {
    final root = await _directoryProvider();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}debug-server',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}authorized-clients.json',
    );
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(clients.map((client) => client.toJson()).toList()),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}

class DebugServerRuntime {
  static final _log = getLogger('DebugServerRuntime');
  DebugServerRuntime({
    required this.commandBus,
    this.displayName = 'OronBox',
    this.platform = 'unknown',
    this.port = defaultDebugServerPort,
    DebugServerIdentityStore? identityStore,
    this.temporaryDirectoryProvider,
    this.onChanged,
  }) : _identityStore = identityStore ?? DebugServerIdentityStore();

  final OronBoxCommandBus commandBus;
  final String displayName;
  final String platform;
  final int port;
  final DebugServerIdentityStore _identityStore;
  final Future<Directory> Function()? temporaryDirectoryProvider;
  final void Function()? onChanged;

  DebugServer? _server;
  Future<DebugServer>? _starting;
  Future<void> _authorizationSaveTail = Future<void>.value();

  DebugServer? get server => _server;

  List<DebugAuthorizedClient> get pendingClients =>
      _server?.pendingClients ?? const [];

  List<DebugAuthorizedClient> get authorizedClients =>
      _server?.authorizedClients ?? const [];

  void approveClient(DebugAuthorizedClient client) =>
      _server?.approveClient(client);

  void revokeClient(String fingerprint) => _server?.revokeClient(fingerprint);

  void rejectClient(String fingerprint) => _server?.rejectClient(fingerprint);

  Future<DebugServer> start() async {
    final current = _server;
    if (current != null) return Future.value(current);
    final starting = _starting;
    if (starting != null) return starting;
    final future = _start();
    _starting = future;
    return future;
  }

  Future<void> stop() async {
    final starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        // The server may have failed to bind; there is nothing to stop.
      }
    }
    final server = _server;
    _server = null;
    await server?.stop();
    await _authorizationSaveTail;
    _starting = null;
  }

  Future<DebugServer> _start() async {
    final identity = await _identityStore.loadOrCreate();
    final authorizedClients = await _identityStore.loadAuthorizedClients();
    late final DebugServer server;
    server = DebugServer(
      serverId: identity.serverId,
      displayName: displayName,
      platform: platform,
      identity: identity.keyPair,
      host: InternetAddress.anyIPv4,
      port: port,
      commandBus: commandBus,
      temporaryDirectoryProvider: temporaryDirectoryProvider,
      onChanged: onChanged,
      authorizedClients: authorizedClients,
      onAuthorizationChanged: _queueAuthorizationSave,
    );
    await server.start();
    _server = server;
    return server;
  }

  void _queueAuthorizationSave() {
    final server = _server;
    if (server == null) return;
    final snapshot = List<DebugAuthorizedClient>.of(server.authorizedClients);
    _authorizationSaveTail = _authorizationSaveTail
        .then((_) => _identityStore.saveAuthorizedClients(snapshot))
        .catchError((Object error, StackTrace stackTrace) {
          _log.warning(
            'Failed to persist authorized debug clients',
            error,
            stackTrace,
          );
        });
    unawaited(_authorizationSaveTail);
  }
}

String _newServerId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return 'ob-${base64Url.encode(bytes).replaceAll('=', '')}';
}
