import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:oronbox/src/core/providers/app_settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/core/providers/bluetooth_platform_provider.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/src/core/services/rfcomm_driver.dart';
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
    'Android pairing rejection is not retried and progress is device-scoped',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
      bluetooth.progress.add(
        const BluetoothConnectProgress(
          'AA:BB:CC:DD:EE:02',
          BluetoothConnectPhase.compatibility,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(deviceManagerProvider).connectionPhase,
        DeviceConnectionPhase.connectingTransport,
      );
      bluetooth.progress.add(
        const BluetoothConnectProgress(
          'aa:bb:cc:dd:ee:01',
          BluetoothConnectPhase.pairing,
        ),
      );
      await _waitFor(
        () =>
            container.read(deviceManagerProvider).connectionPhase ==
            DeviceConnectionPhase.pairing,
      );
      bluetooth._pendingConnections.single.completeError(
        const SppConnectFailure('PAIRING_REJECTED'),
      );
      await pending;
      expect(bluetooth.connectCalls, 1);
      expect(
        container.read(deviceManagerProvider).error,
        contains('PAIRING_REJECTED'),
      );
      expect(bluetooth.progress.hasListener, isFalse);
      await bluetooth.progress.close();
    },
  );

  test(
    'Android cancellation during transport backoff starts no second attempt',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
      bluetooth._pendingConnections.single.completeError(
        const SppConnectFailure('CONNECT_FAILED'),
      );
      await _waitFor(
        () =>
            container.read(deviceManagerProvider).connectionPhase ==
            DeviceConnectionPhase.waitingToRetry,
      );
      await manager.cancelConnect();
      await pending;
      expect(bluetooth.connectCalls, 1);
      expect(container.read(deviceManagerProvider).connecting, isFalse);
      await bluetooth.progress.close();
    },
  );

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

  test('switching devices during Android backoff preserves the new connection state', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final bluetooth = _BlockingBluetoothPlatform();
    final container = ProviderContainer(
      overrides: [bluetoothPlatformProvider.overrideWithValue(bluetooth)],
    );
    addTearDown(container.dispose);
    final manager = container.read(deviceManagerProvider.notifier);
    final first = manager.connect(
      'AA:BB:CC:DD:EE:01',
      '小米手环9 Pro',
      '1' * 32,
      connectType: 'spp',
    );
    await _waitFor(() => bluetooth.connectCalls == 1);
    bluetooth._pendingConnections.first.completeError(
      const SppConnectFailure('CONNECT_FAILED'),
    );
    await _waitFor(
      () =>
          container.read(deviceManagerProvider).connectionPhase ==
          DeviceConnectionPhase.waitingToRetry,
    );
    final second = manager.connect(
      'AA:BB:CC:DD:EE:02',
      '小米手环10',
      '2' * 32,
      connectType: 'spp',
    );
    await _waitFor(() => bluetooth.connectCalls == 2);
    await first;
    final state = container.read(deviceManagerProvider);
    expect(state.connecting, isTrue);
    expect(state.connectionTargetAddr, 'AA:BB:CC:DD:EE:02');
    await manager.cancelConnect();
    await second;
    expect(bluetooth.connectCalls, 2);
    await bluetooth.progress.close();
  });
  test('Android transient socket failure retries, but a later pairing rejection stops', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
    bluetooth._pendingConnections.first.completeError(
      const SppConnectFailure('CONNECT_FAILED'),
    );
    await _waitFor(() => bluetooth.connectCalls == 2, maxPolls: 400);
    bluetooth._pendingConnections.last.completeError(
      const SppConnectFailure('PAIRING_REJECTED'),
    );
    await pending;
    expect(bluetooth.connectCalls, 2);
    expect(
      container.read(deviceManagerProvider).error,
      contains('PAIRING_REJECTED'),
    );
    await bluetooth.progress.close();
  });
}

Future<void> _waitFor(bool Function() condition, {int maxPolls = 100}) async {
  for (var attempt = 0; attempt < maxPolls; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'condition did not become true');
}

class _BlockingBluetoothPlatform
    implements BluetoothPlatform, BluetoothConnectionProgressSource {
  final progress = StreamController<BluetoothConnectProgress>.broadcast();
  @override
  Stream<BluetoothConnectProgress> get connectionProgress => progress.stream;
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
