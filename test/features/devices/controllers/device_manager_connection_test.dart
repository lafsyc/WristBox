import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:oronbox/src/core/providers/app_settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/core/providers/bluetooth_platform_provider.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/src/device/core/bluetooth_platform.dart';
import 'package:oronbox/src/device/core/connect_type.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.instance.init();
    await SharedPrefsService.instance.reload();
  });

  for (final repair in [false, true]) {
    test(
      'Android preserves system bond unless repair is explicitly enabled ($repair)',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        // The inherited desktop/global default must not erase a phone's bond.
        await SharedPrefsService.instance.setBool(
          removeBondBeforeSppSettingKey,
          true,
        );
        if (repair) {
          await SharedPrefsService.instance.setBool(
            androidRebuildBondSettingKey,
            true,
          );
        }
        final bluetooth = _BlockingBluetoothPlatform();
        final container = ProviderContainer(
          overrides: [bluetoothPlatformProvider.overrideWithValue(bluetooth)],
        );
        addTearDown(container.dispose);
        final manager = container.read(deviceManagerProvider.notifier);
        final pending = manager.connect(
          'AA:BB:CC:DD:EE:01',
          '小米手环9 Pro',
          '1' * 32,
          connectType: 'spp',
        );
        await _waitFor(() => bluetooth.connectCalls == 1);
        expect(bluetooth.lastOptions!.sppRemoveBond, repair);
        await manager.cancelConnect();
        await pending;
      },
    );
  }

  test(
    'joins an in-flight connection to the same device and transport',
    () async {
      final bluetooth = _BlockingBluetoothPlatform();
      final container = ProviderContainer(
        overrides: [bluetoothPlatformProvider.overrideWithValue(bluetooth)],
      );
      addTearDown(container.dispose);
      final manager = container.read(deviceManagerProvider.notifier);
      addTearDown(() async {
        await manager.cancelConnect();
      });

      final first = manager.connect(
        'AA:BB:CC:DD:EE:FF',
        'Xiaomi Watch S5',
        'test-auth-key',
        connectType: ConnectType.spp.name,
      );
      await _waitFor(() => bluetooth.connectCalls == 1);

      final second = manager.connect(
        'AA:BB:CC:DD:EE:FF',
        'Xiaomi Watch S5',
        'test-auth-key',
        connectType: ConnectType.spp.name,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(second, same(first));
      expect(bluetooth.connectCalls, 1);

      await manager.cancelConnect();
      await Future.wait([first, second]);
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'condition did not become true');
}

class _BlockingBluetoothPlatform implements BluetoothPlatform {
  final _pendingConnections = <Completer<BluetoothConnection>>[];
  var connectCalls = 0;
  BluetoothConnectOptions? lastOptions;

  @override
  Stream<BluetoothEndpoint> get scanStream => const Stream.empty();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> startScan(BluetoothScanOptions options) async {}

  @override
  Future<List<BluetoothEndpoint>> stopScan() async => const [];

  @override
  Future<BluetoothConnection> connect(
    String address,
    String name,
    BluetoothConnectOptions options,
  ) {
    lastOptions = options;
    connectCalls++;
    final completer = Completer<BluetoothConnection>();
    _pendingConnections.add(completer);
    return completer.future;
  }

  @override
  Future<void> cancelPendingSppConnection() async {
    for (final pending in _pendingConnections) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('connection cancelled by test'));
      }
    }
  }

  @override
  Future<void> disconnect(String address) async {}

  @override
  Future<void> disconnectAll() async {}
}
