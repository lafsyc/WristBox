import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/device/core/device_kind.dart';
import 'package:oronbox/steadylink/backend.dart';

class CancelManager extends LocalDeviceManager {
  final started = Completer<void>(), pending = Completer<void>();
  int attempts = 0;
  @override
  DeviceManagerState build() => DeviceManagerState(
    pairedDevices: [
      MiWearState(
        name: 'Test',
        addr: 'AA:BB:CC:DD:EE:01',
        authkey: '1' * 32,
        connectType: 'spp',
      ),
    ],
  );
  @override
  Future<void> connect(
    String addr,
    String name,
    String authKey, {
    String connectType = 'ble',
    DeviceKind kind = DeviceKind.xiaomi,
  }) async {
    attempts++;
    state = state.copyWith(connecting: true);
    started.complete();
    await pending.future;
  }

  @override
  Future<void> cancelConnect() async {
    state = state.copyWith(connecting: false);
    if (!pending.isCompleted) pending.complete();
  }

  @override
  Future<void> disconnect([String? address]) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'explicit cancellation cannot start another connection attempt',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('oronbox/classic_spp'),
            (_) async => null,
          );
      final manager = CancelManager();
      final container = ProviderContainer(
        overrides: [deviceManagerProvider.overrideWith(() => manager)],
      );
      addTearDown(container.dispose);
      final backend = container.read(steadyBackendProvider);
      final result = backend.ensureConnected('AA:BB:CC:DD:EE:01');
      final expected = expectLater(
        result,
        throwsA(isA<StateError>().having((e) => e.message, 'message', '已取消连接')),
      );
      await manager.started.future;
      await backend.cancelConnection();
      await expected;
      expect(manager.attempts, 1);
    },
  );
}
