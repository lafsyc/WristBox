import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/commands/command_protocol.dart';
import 'package:oronbox/src/debug_server/debug_server_auth.dart';
import 'package:oronbox/src/debug_server/debug_server_runtime.dart';

void main() {
  test('identity store preserves the server id and RSA key', () async {
    final root = await Directory.systemTemp.createTemp('oronbox-debug-');
    addTearDown(() => root.delete(recursive: true));
    final store = DebugServerIdentityStore(directoryProvider: () async => root);

    final first = await store.loadOrCreate();
    final second = await store.loadOrCreate();

    expect(first.serverId, startsWith('ob-'));
    expect(second.serverId, first.serverId);
    expect(second.keyPair.publicKey, first.keyPair.publicKey);
    expect(second.keyPair.sign([1, 2, 3]), isNotEmpty);
  });

  test('identity store preserves approved debug clients', () async {
    final root = await Directory.systemTemp.createTemp('oronbox-debug-');
    addTearDown(() => root.delete(recursive: true));
    final store = DebugServerIdentityStore(directoryProvider: () async => root);
    final keyPair = DebugRsaKeyPair.generate(bitStrength: 2048);
    final client = DebugAuthorizedClient(
      fingerprint: keyPair.publicKey.fingerprint,
      publicKey: keyPair.publicKey,
      displayName: 'Test tool',
      scopes: {'device.list', 'task.status'},
    );

    await store.saveAuthorizedClients([client]);
    final restored = await store.loadAuthorizedClients();

    expect(restored, hasLength(1));
    expect(restored.single.toJson(), client.toJson());
  });

  test('runtime starts and stops the explicit server', () async {
    final root = await Directory.systemTemp.createTemp('oronbox-debug-');
    addTearDown(() => root.delete(recursive: true));
    final bus = _EmptyBus();
    final runtime = DebugServerRuntime(
      commandBus: bus,
      port: 0,
      identityStore: DebugServerIdentityStore(
        directoryProvider: () async => root,
      ),
      temporaryDirectoryProvider: () async => root,
    );

    final server = await runtime.start();
    expect(server.isRunning, isTrue);
    expect(server.boundPort, greaterThan(0));
    await runtime.stop();
    expect(server.isRunning, isFalse);
    await bus.close();
  });

  test('authorization saves recover after an earlier write failure', () async {
    final root = await Directory.systemTemp.createTemp('oronbox-debug-');
    addTearDown(() => root.delete(recursive: true));
    final bus = _EmptyBus();
    final store = _FailOnceIdentityStore(root);
    final runtime = DebugServerRuntime(
      commandBus: bus,
      port: 0,
      identityStore: store,
      temporaryDirectoryProvider: () async => root,
    );
    final firstKey = DebugRsaKeyPair.generate(bitStrength: 2048);
    final secondKey = DebugRsaKeyPair.generate(bitStrength: 2048);

    final server = await runtime.start();
    server.approveClient(
      DebugAuthorizedClient(
        fingerprint: firstKey.publicKey.fingerprint,
        publicKey: firstKey.publicKey,
        displayName: 'First',
        scopes: const {'device.list'},
      ),
    );
    server.approveClient(
      DebugAuthorizedClient(
        fingerprint: secondKey.publicKey.fingerprint,
        publicKey: secondKey.publicKey,
        displayName: 'Second',
        scopes: const {'device.list'},
      ),
    );
    await runtime.stop();

    final restored = await store.loadAuthorizedClients();
    expect(restored, hasLength(2));
    await bus.close();
  });
}

class _FailOnceIdentityStore extends DebugServerIdentityStore {
  _FailOnceIdentityStore(Directory root)
    : super(directoryProvider: () async => root);

  bool _shouldFail = true;

  @override
  Future<void> saveAuthorizedClients(
    Iterable<DebugAuthorizedClient> clients,
  ) async {
    if (_shouldFail) {
      _shouldFail = false;
      throw const FileSystemException('simulated write failure');
    }
    await super.saveAuthorizedClients(clients);
  }
}

class _EmptyBus implements OronBoxCommandBus {
  @override
  Stream<CommandEvent> get events => const Stream.empty();

  @override
  Future<CommandResult> execute(OronBoxCommand command) async =>
      const CommandResult.success();

  @override
  Future<void> close() async {}
}
