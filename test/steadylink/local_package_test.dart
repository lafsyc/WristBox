import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/backend.dart';
import 'package:oronbox/steadylink/local_package.dart';
import 'package:oronbox/steadylink/operation_queue.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart'
    show ProtocolState;

class FileInstallManager extends LocalDeviceManager {
  int apps = 0, faces = 0, appQueries = 0, faceQueries = 0;
  bool paused = false;
  @override
  DeviceManagerState build() => const DeviceManagerState(
    currentDevice: MiWearState(addr: 'AA', name: '测试手环', connectType: 'spp'),
    pairedDevices: [MiWearState(addr: 'AA', name: '测试手环', connectType: 'spp')],
    protocolState: ProtocolState.ready,
  );
  @override
  Future<void> setBatteryRefreshPaused(bool value) async {
    paused = value;
  }

  @override
  Future<void> installApp(
    Uint8List bytes, {
    required String packageName,
    void Function(double)? onProgress,
    void Function()? onAppSideMissing,
  }) async {
    expect(packageName, 'test.local');
    apps++;
    onProgress?.call(1);
  }

  @override
  Future<void> installWatchface(
    Uint8List bytes, {
    required String watchfaceId,
    void Function(double)? onProgress,
  }) async {
    expect(watchfaceId, '999912345678');
    faces++;
    onProgress?.call(1);
  }

  @override
  Future<void> fetchApps() async {
    appQueries++;
  }

  @override
  Future<void> fetchWatchfaces() async {
    faceQueries++;
  }
}

void main() {
  final manifest = utf8.encode(
    jsonEncode({'package': 'test.local', 'name': '测试', 'versionName': '1.0.0'}),
  );
  final appBytes = ZipEncoder().encode(
    Archive()..addFile(ArchiveFile('manifest.json', manifest.length, manifest)),
  );
  final face = Uint8List(0x34)
    ..setRange(0, 4, [0x5a, 0xa5, 0x34, 0x12])
    ..setRange(0x28, 0x34, '999912345678'.codeUnits);
  for (final fixture in [
    ('app.RPK', appBytes, 1, 0),
    ('app.bin', appBytes, 1, 0),
    ('face.BIN', face, 0, 1),
    ('firmware.bin', Uint8List.fromList([0x60, 0x5a, 0x5a, 0x7e]), 0, 0),
    ('invalid.bin', Uint8List.fromList([1, 2, 3]), 0, 0),
  ]) {
    test('installation routes by content: ${fixture.$1}', () async {
      final dir = await Directory.systemTemp.createTemp('wristbox-local-test-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/${fixture.$1}');
      await file.writeAsBytes(fixture.$2);
      final manager = FileInstallManager();
      final container = ProviderContainer(
        overrides: [deviceManagerProvider.overrideWith(() => manager)],
      );
      addTearDown(container.dispose);
      final backend = container.read(steadyBackendProvider);
      final job = InstallJob(
        path: file.path,
        deviceId: 'AA',
        deviceName: '测试手环',
      );
      backend.queue.add([job]);
      await backend.queue.settled;
      expect(manager.apps, fixture.$3);
      expect(manager.faces, fixture.$4);
      expect(manager.paused, isFalse);
      expect(manager.appQueries, fixture.$3);
      expect(manager.faceQueries, fixture.$4);
      expect(
        job.phase,
        fixture.$3 + fixture.$4 > 0
            ? InstallPhase.succeeded
            : InstallPhase.failed,
      );
      if (fixture.$1 == 'firmware.bin') expect(job.error, contains('固件'));
    });
  }
  test('unsupported extensions and empty files are rejected', () {
    expect(isLocalInstallFile('A.BIN'), isTrue);
    expect(isLocalInstallFile('A.bin.apk'), isFalse);
    expect(
      () => analyzeLocalPackage('empty.bin', Uint8List(0)),
      throwsStateError,
    );
    expect(
      () => analyzeLocalPackage('app.apk', Uint8List.fromList(appBytes)),
      throwsStateError,
    );
  });
}
