import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/backend.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/device/core/device_kind.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart'
    show ProtocolState;

const band = MiWearState(
  name: 'Test band',
  addr: 'AA:BB:CC:DD:EE:01',
  authkey: '00000000000000000000000000000000',
  connectType: 'spp',
);

class ConnectionManager extends LocalDeviceManager {
  int attempts = 0;
  @override
  DeviceManagerState build() => const DeviceManagerState(pairedDevices: [band]);
  @override
  Future<void> connect(
    String addr,
    String name,
    String authKey, {
    String connectType = 'ble',
    DeviceKind kind = DeviceKind.xiaomi,
  }) async {
    attempts++;
    state = state.copyWith(
      currentDevice: band,
      protocolState: ProtocolState.ready,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unavailable radio skips retries and recovers after enabling without restart', () async {
    var poweredOn = false;
    var probes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('oronbox/classic_spp'), (
          call,
        ) async {
          expect(call.method, 'checkAvailability');
          probes++;
          if (!poweredOn) {
            throw PlatformException(
              code: 'BLUETOOTH_SERVICE_STOPPED',
              message: '蓝牙支持服务未运行',
            );
          }
          return null;
        });
    final manager = ConnectionManager();
    final container = ProviderContainer(
      overrides: [deviceManagerProvider.overrideWith(() => manager)],
    );
    addTearDown(container.dispose);
    final backend = container.read(steadyBackendProvider);
    await expectLater(
      backend.ensureConnected(band.addr),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('蓝牙支持服务'),
        ),
      ),
    );
    expect(manager.attempts, 0);
    expect(probes, 1);
    poweredOn = true;
    await backend.ensureConnected(band.addr);
    expect(probes, 2);
    expect(manager.attempts, 1);
    await backend.ensureConnected(band.addr);
    expect(probes, 2); // Keep a healthy current connection intact.
    expect(manager.attempts, 1);
  }, skip: !Platform.isWindows);
}
