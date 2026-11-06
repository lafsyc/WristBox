import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/backend.dart';
import 'package:oronbox/steadylink/bin_upload_dialog.dart';
import 'package:oronbox/steadylink/store_models.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/device/core/cloud_watchface_policy.dart';
import 'package:oronbox/src/device/core/xiaomi_wearable_catalog.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/xiaomi/transport/mass_payload_source.dart';

import 'cloud_cleanup_test.dart'
    show InstallManager, InstallStore, FailingCleanupSource, target, original;

class BinManager extends InstallManager {
  BinManager(super.success);
  var binCalls = 0, appCalls = 0, refreshes = 0;
  @override
  Future<void> installCloudWatchface(
    MassPayloadSource source, {
    required String deviceId,
    required String watchfaceId,
    void Function(double)? onProgress,
  }) async {
    expect(watchfaceId, '367190065');
    expect(deviceId, target.addr);
    binCalls++;
    onProgress?.call(.5);
    if (!success) throw original;
  }

  @override
  Future<void> installCloudApp(
    MassPayloadSource source, {
    required String deviceId,
    required String packageName,
    required int versionCode,
    void Function(double)? onProgress,
  }) async {
    appCalls++;
  }

  @override
  Future<void> fetchWatchfaces() async {
    refreshes++;
  }
}

void main() {
  test('cloud BIN header cannot be relabeled, patched or routed as OTA', () {
    final header = Uint8List(52)
      ..setAll(0, [0x5a, 0xa5, 0x34, 0x12])
      ..setAll(40, '367190065'.codeUnits);
    final original = Uint8List.fromList(header);
    validateCloudWatchfaceHeader(header, '367190065', 70000);
    expect(header, original);
    for (final id in ['1234', '000000000', '120912345']) {
      expect(
        () => validateCloudWatchfaceHeader(header, id, 70000),
        throwsStateError,
      );
    }
    header[0] = 0x60;
    expect(
      () => validateCloudWatchfaceHeader(header, '367190065', 70000),
      throwsStateError,
    );
  });
  for (final success in [true, false]) {
    test(
      'BIN routes to watchface stream and retains cleanup semantics: $success',
      () async {
        final manager = BinManager(success), source = FailingCleanupSource();
        source.manifest = {
          'packageName': 'com.wristbox.watchface.id367190065',
          'versionCode': 20402,
          'installType': 'watchface',
          'packageFormat': 'bin',
          'watchfaceId': '367190065',
        };
        final container = ProviderContainer(
          overrides: [deviceManagerProvider.overrideWith(() => manager)],
        );
        addTearDown(container.dispose);
        final backend = container.read(steadyBackendProvider);
        final op = backend.installCloud(
          InstallStore(source),
          'fixture',
          target.addr,
          (_) {},
          expectedModel: 'n67',
        );
        if (success) {
          await op;
        } else {
          await expectLater(op, throwsA(same(original)));
        }
        expect(manager.binCalls, 1);
        expect(manager.appCalls, 0);
        expect(manager.refreshes, success ? 1 : 0);
        expect(source.reports, [success]);
        expect(backend.queue.busy, false);
      },
    );
  }
  test('NFC variants select distinct BIN resources', () {
    expect(
      normalizeXiaomiWearableIdentity('miwear.watch.n66nfc')?.codename,
      'n66nfc',
    );
    expect(
      normalizeXiaomiWearableIdentity('miwear.watch.n66')?.codename,
      'n66',
    );
    expect(
      xiaomiDisplayNameForIdentity(name: '小米手环9 NFC', codename: 'n66'),
      contains('NFC'),
    );
    for (final entry in [
      ('小米手环9 NFC', 'n66', 'n66nfc'),
      ('小米手环11 NFC', 'band11', 'band11nfc'),
    ]) {
      final d = MiWearState(
        name: entry.$1,
        addr: 'AA:BB:CC:DD:EE:FF',
        codename: entry.$2,
        connectType: 'spp',
      );
      expect(storeModelForDevice(d), entry.$3);
      final app = StoreApp('one', [
        {
          'id': 'plain',
          'versionCode': 1,
          'installType': 'watchface',
          'supportedModels': [entry.$2],
        },
        {
          'id': 'nfc',
          'versionCode': 1,
          'installType': 'watchface',
          'supportedModels': [entry.$3],
        },
      ]);
      expect(app.forDevice(storeModelForDevice(d), '1.0')?['id'], 'nfc');
    }
  });
  testWidgets(
    'BIN upload collects a validated display version and numeric order',
    (tester) async {
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) =>
                      const BinUploadDialog(fileName: 'game.FACE.BIN'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('game'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(2), '0');
      await tester.tap(find.text('上传为草稿'));
      await tester.pumpAndSettle();
      expect(find.text('请输入有效的正整数版本号'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(2), '20402');
      await tester.tap(find.text('上传为草稿'));
      await tester.pumpAndSettle();
      expect(result, {
        'name': 'game',
        'version': '1.0.0',
        'versionCode': 20402,
      });
    },
  );
}
