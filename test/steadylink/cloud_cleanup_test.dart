import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/backend.dart';
import 'package:oronbox/steadylink/cloud_store.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart';
import 'package:oronbox/src/protocols/xiaomi/transport/mass_payload_source.dart';
import 'package:oronbox/src/device/xiaomi/components/install_errors.dart';

const target = MiWearState(
  name: '小米手环 9 Pro',
  addr: 'AA:BB:CC:DD:EE:01',
  connectType: 'spp',
  codename: 'n67',
);
const original = ProtocolException('手环未通过安装包校验');

class FailingCleanupSource extends CloudPackageSource {
  FailingCleanupSource() : super(Dio()) {
    manifest = {'packageName': 'test.app', 'versionCode': 1};
  }
  final reports = <bool>[];
  @override
  Future<void> close() async {
    throw StateError('cleanup failed');
  }

  @override
  Future<void> finish(bool success) async {
    reports.add(success);
  }
}

class InstallStore extends CloudStore {
  InstallStore(this.source) : super(Dio());
  final FailingCleanupSource source;
  @override
  Future<CloudPackageSource> open(
    String id,
    String device,
    String model, {
    String serial = '',
    String firmware = '',
    bool activationRequired = false,
    String? grantId,
  }) async => source;
  @override
  Future<Map<String, dynamic>> activationStatus(
    String resource,
    String model,
    String serial, {
    String firmware = '',
    String? grantId,
  }) async => {'required': false, 'activated': true};
}

class InstallManager extends LocalDeviceManager {
  InstallManager(this.success);
  final bool success;
  int disconnects = 0;
  final pauses = <bool>[];
  @override
  DeviceManagerState build() => const DeviceManagerState(
    currentDevice: target,
    pairedDevices: [target],
    protocolState: ProtocolState.ready,
  );
  @override
  Future<void> setBatteryRefreshPaused(bool paused) async {
    pauses.add(paused);
  }

  @override
  Future<void> disconnect([String? address]) async {
    disconnects++;
    throw StateError('disconnect cleanup failed');
  }

  @override
  Future<void> installCloudApp(
    MassPayloadSource source, {
    required String deviceId,
    required String packageName,
    required int versionCode,
    void Function(double)? onProgress,
  }) async {
    if (!success) throw original;
  }

  @override
  Future<void> fetchApps() async {}
  @override
  Future<void> fetchSystemInfo() async {}
}

void main() {
  for (final success in [false, true]) {
    test('cleanup errors cannot mask install outcome: $success', () async {
      final manager = InstallManager(success), source = FailingCleanupSource();
      final container = ProviderContainer(
        overrides: [deviceManagerProvider.overrideWith(() => manager)],
      );
      addTearDown(container.dispose);
      final backend = container.read(steadyBackendProvider);
      final future = backend.installCloud(
        InstallStore(source),
        'fixture',
        target.addr,
        (_) {},
        expectedModel: 'n67',
      );
      if (success) {
        await future;
      } else {
        await expectLater(future, throwsA(same(original)));
      }
      expect(manager.disconnects, success ? 0 : 1);
      expect(manager.pauses, [true, false]);
      expect(source.reports, [success]);
      expect(backend.queue.busy, false);
    });
  }
  test('protocol failures show actionable Chinese messages', () {
    expect(
      cloudError(ProtocolException(xiaomiInstallPrepareError(1))),
      contains('上一项任务'),
    );
    expect(
      cloudError(ProtocolException(xiaomiInstallPrepareError(3))),
      contains('存储空间不足'),
    );
    expect(
      cloudError(ProtocolException(xiaomiInstallPrepareError(5))),
      contains('更低的版本'),
    );
    expect(
      cloudError(ProtocolException(xiaomiInstallResultError(2))),
      contains('校验'),
    );
    expect(cloudError(UnsupportedError('read only')), contains('安装数据处理异常'));
  });
}
