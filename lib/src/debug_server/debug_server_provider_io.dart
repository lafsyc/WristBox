import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../host/application_host_provider.dart';
import 'debug_server_auth.dart';
import 'debug_server_runtime.dart';
import 'debug_server_state.dart';

class DebugServerController extends Notifier<DebugServerState> {
  DebugServerRuntime? _runtime;
  Future<void>? _lateStartCleanup;

  @override
  DebugServerState build() {
    _runtime = DebugServerRuntime(
      commandBus: ref.read(applicationHostProvider),
      displayName: 'OronBox',
      platform: _platformName,
      onChanged: () => unawaited(_refresh()),
    );
    ref.onDispose(() {
      final runtime = _runtime;
      if (runtime != null) unawaited(runtime.stop());
    });
    return const DebugServerState();
  }

  Future<void> start() async {
    if (state.isRunning || state.status == DebugServerStatus.starting) return;
    await _lateStartCleanup;
    state = state.copyWith(
      status: DebugServerStatus.starting,
      clearError: true,
    );
    try {
      final runtime = _runtime!;
      final starting = runtime.start();
      await starting.timeout(const Duration(seconds: 8));
      await _refresh();
    } on TimeoutException catch (error) {
      final runtime = _runtime!;
      final cleanup = runtime.stop().catchError((_) {
        // The controller is already reporting the startup failure. The
        // cleanup future is kept successful so a later retry is not blocked.
      });
      _lateStartCleanup = cleanup;
      unawaited(cleanup.whenComplete(() => _lateStartCleanup = null));
      state = state.copyWith(
        status: DebugServerStatus.error,
        error: error.toString(),
      );
    } catch (error) {
      state = state.copyWith(
        status: DebugServerStatus.error,
        error: error.toString(),
      );
    }
  }

  Future<void> stop() async {
    if (state.status == DebugServerStatus.stopping) return;
    state = state.copyWith(status: DebugServerStatus.stopping);
    try {
      await _runtime!.stop();
      state = const DebugServerState();
    } catch (error) {
      state = state.copyWith(
        status: DebugServerStatus.error,
        error: error.toString(),
      );
    }
  }

  Future<void> approve(String fingerprint) async {
    final client = _find(state.pendingClients, fingerprint);
    if (client == null) return;
    _runtime!.approveClient(client);
    await _refresh();
  }

  Future<void> revoke(String fingerprint) async {
    _runtime!.revokeClient(fingerprint);
    await _refresh();
  }

  Future<void> reject(String fingerprint) async {
    _runtime!.rejectClient(fingerprint);
    await _refresh();
  }

  Future<void> _refresh() async {
    final runtime = _runtime;
    final server = runtime?.server;
    if (server == null) {
      if (state.status != DebugServerStatus.starting) {
        state = const DebugServerState();
      }
      return;
    }
    final addresses = await _localAddresses(server.boundPort);
    state = DebugServerState(
      status: DebugServerStatus.running,
      info: server.info,
      addresses: addresses,
      pendingClients: server.pendingClients,
      authorizedClients: server.authorizedClients,
    );
  }

  DebugAuthorizedClient? _find(
    List<DebugAuthorizedClient> clients,
    String fingerprint,
  ) {
    for (final client in clients) {
      if (client.fingerprint == fingerprint) return client;
    }
    return null;
  }
}

final debugServerProvider =
    NotifierProvider<DebugServerController, DebugServerState>(
      DebugServerController.new,
    );

String get _platformName {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return Platform.operatingSystem;
}

Future<List<String>> _localAddresses(int port) async {
  final values = <String>[];
  try {
    // NetworkInterface.list performs a synchronous interface enumeration that
    // can stall the caller's isolate for seconds on Android. Run it on a
    // separate isolate and fall back to loopback when discovery is slow or
    // unavailable, so enabling the debug server never freezes the UI.
    final discovered = await Isolate.run(() async {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final result = <String>[];
      for (final networkInterface in interfaces) {
        for (final address in networkInterface.addresses) {
          if (address.isLoopback) continue;
          result.add('http://${address.address}:$port');
        }
      }
      return result;
    }).timeout(const Duration(milliseconds: 1500));
    values.addAll(discovered);
  } catch (_) {
    // The service remains usable through localhost when interface discovery
    // is unavailable or restricted by the platform.
  }
  if (values.isEmpty) {
    values.add('http://127.0.0.1:$port');
  }
  return values.toSet().toList()..sort();
}
