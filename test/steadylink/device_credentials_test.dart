import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/core/providers/bluetooth_platform_provider.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/src/device/core/bluetooth_platform.dart';
import 'package:oronbox/src/features/accounts/models/mi_account_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart'
    show ProtocolState;
import 'package:oronbox/steadylink/backend.dart';
import 'package:oronbox/steadylink/error_message.dart';
import 'package:oronbox/steadylink/operation_queue.dart';

const oldKey = '11111111111111111111111111111111';
const newKey = 'abcdefabcdefabcdefabcdefabcdefab';
const band = MiWearState(
  name: '小米手环 9 Pro',
  addr: 'AA:BB:CC:DD:EE:01',
  authkey: oldKey,
  connectType: 'spp',
);
const other = MiWearState(
  name: '小米手环 10',
  addr: 'AA:BB:CC:DD:EE:02',
  authkey: oldKey,
  connectType: 'spp',
);

class _Radio extends Fake implements BluetoothPlatform {
  @override
  Stream<BluetoothEndpoint> get scanStream => const Stream.empty();
  @override
  Future<List<BluetoothEndpoint>> stopScan() async => [];
}

class _Manager extends LocalDeviceManager {
  int disconnects = 0;
  @override
  DeviceManagerState build() {
    super.build();
    return const DeviceManagerState(
      currentDevice: band,
      pairedDevices: [band, other],
      protocolState: ProtocolState.ready,
      battery: BatteryStatus(capacity: 80),
      apps: [AppInfo(packageName: 'example.app', appName: 'Example')],
    );
  }

  @override
  Future<void> disconnect([String? address]) async {
    disconnects++;
    await super.disconnect(address);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Manager manager;
  late ProviderContainer container;
  late SteadyBackend backend;
  var failWrites = false;
  String? saved;
  setUp(() async {
    failWrites = false;
    saved = null;
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.instance.init();
    await SharedPrefsService.instance.reload();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('steadylink/credentials'),
          (call) async {
            if (call.method == 'read') return '{"paired_devices":[]}';
            if (failWrites) throw PlatformException(code: 'write_failed');
            saved = call.arguments as String;
            return null;
          },
        );
    await SharedPrefsService.instance.initializeSecureStorage();
    manager = _Manager();
    container = ProviderContainer(
      overrides: [
        bluetoothPlatformProvider.overrideWithValue(_Radio()),
        deviceManagerProvider.overrideWith(() => manager),
      ],
    );
    backend = container.read(steadyBackendProvider);
  });
  tearDown(() {
    container.dispose();
  });

  test('manual replacement retires ready session, clears stale data and persists new Key', () async {
    await backend.importDevice(
      band.copyWith(addr: 'aa-bb-cc-dd-ee-01', authkey: newKey.toUpperCase()),
    );
    final state = backend.state;
    expect(manager.disconnects, 1);
    expect(state.protocolState, ProtocolState.disconnected);
    expect(state.currentDevice!.authkey, newKey);
    expect(state.currentDevice!.disconnected, isTrue);
    expect(state.apps, isEmpty);
    expect(state.battery, isNull);
    expect(state.pairedDevices, hasLength(2));
    expect(state.pairedDevices.last, other);
    final stored = (jsonDecode(saved!)['paired_devices'] as List)
        .map((e) => jsonDecode(e as String))
        .toList();
    expect(stored.first['authkey'], newKey);
  });

  test('account sync updates Key without duplicate, unchanged Key retains ready session', () async {
    MiCloudDevice cloud(String key) => MiCloudDevice(
      name: band.name,
      model: 'xiaomi.watch.n67',
      mac: band.addr.toLowerCase(),
      authKey: key,
      firmwareVersion: '',
      serialNumber: '',
    );
    await backend.syncDevices([cloud(oldKey)]);
    expect(manager.disconnects, 0);
    expect(backend.state.protocolState, ProtocolState.ready);
    expect(await backend.syncDevices([cloud(newKey)]), 1);
    expect(manager.disconnects, 1);
    expect(backend.state.pairedDevices, hasLength(2));
    expect(backend.state.currentDevice!.authkey, newKey);
    expect(backend.state.protocolState, ProtocolState.disconnected);
  });

  test(
    'removal clears selected/current device and allows reimport with new Key',
    () async {
      backend.queue.select(band.addr);
      await backend.queue.settled;
      await backend.removeDevice(band.addr);
      expect(backend.state.currentDevice, isNull);
      expect(backend.state.pairedDevices, [other]);
      expect(backend.state.apps, isEmpty);
      await backend.importDevice(band.copyWith(authkey: newKey));
      expect(backend.state.currentDevice!.authkey, newKey);
      expect(backend.state.protocolState, ProtocolState.disconnected);
    },
  );

  test('invalid or unsaved Key does not replace working credentials', () async {
    await expectLater(backend.updateKey(band.addr, 'bad'), throwsStateError);
    expect(backend.state.currentDevice!.authkey, oldKey);
    expect(manager.disconnects, 0);
    failWrites = true;
    await expectLater(
      backend.updateKey(band.addr, newKey),
      throwsA(isA<PlatformException>()),
    );
    expect(backend.state.currentDevice!.authkey, oldKey);
    expect(backend.state.protocolState, ProtocolState.disconnected);
  });

  test('maintenance prevents mutation during install and forgetting never reconnects deleted device', () async {
    final gate = Completer<void>();
    final connects = <String>[];
    final queue = OperationQueue(
      connect: (id) async => connects.add(id),
      install: (_, _) async {},
    );
    addTearDown(queue.dispose);
    queue.select('old');
    await queue.settled;
    final mutation = queue.maintain(() => gate.future);
    await expectLater(queue.maintain(() async {}), throwsStateError);
    queue.forget('old');
    gate.complete();
    await mutation;
    await queue.exclusive('other', () async {});
    await queue.settled;
    expect(connects, ['old', 'other']);
  });

  test('Chinese errors distinguish authentication and uncertain installation outcome', () {
    expect(
      friendlyError(PlatformException(code: 'auth_failed', details: newKey)),
      contains('重新绑定'),
    );
    expect(
      friendlyError(TimeoutException('timeout'), installing: true),
      contains('确认是否已安装成功'),
    );
    expect(
      friendlyError(StateError('Key 保存失败 $newKey')),
      isNot(contains(newKey)),
    );
    expect(
      friendlyError(
        PlatformException(code: 'unknown', details: 'secret-password'),
      ),
      isNot(contains('secret-password')),
    );
    expect(friendlyError(StateError('permission denied')), contains('附近的设备'));
  });
}
