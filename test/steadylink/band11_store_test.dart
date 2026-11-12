import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/cloud_store_page.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';

import 'store_ui_test.dart' show PreviewStore, StoreManager;

class _Band11NfcManager extends StoreManager {
  @override
  DeviceManagerState build() => super.build().copyWith(
    currentDevice: const MiWearState(
      name: 'Xiaomi Smart Band 11 3AE8',
      addr: 'CC',
      connectType: 'spp',
    ),
    systemInfo: const SystemInfo(
      serialNumber: 'SN-FIXTURE',
      firmwareVersion: '4.100.179',
      imei: '',
      model: 'q66nfc',
    ),
  );
}

class _UnknownManager extends StoreManager {
  @override
  DeviceManagerState build() => super.build().copyWith(
    currentDevice: const MiWearState(
      name: 'Unknown band',
      addr: 'CC',
      connectType: 'spp',
    ),
  );
}

class _Band11Store extends PreviewStore {
  @override
  Future<List<Map<String, dynamic>>> catalog({bool manage = false}) async => [
    for (final model in ['band11', 'band11nfc'])
      {
        'id': model,
        'name': '腕上棋局',
        'appId': 'chess',
        'packageName': 'com.fixture.$model',
        'version': '2.4.5-i1',
        'versionCode': 1,
        'published': true,
        'size': 400000,
        'installType': 'watchface',
        'iconId': '',
        'previewIds': <String>[],
        'description': '',
        'category': '游戏',
        'supportedModels': [model],
        'firmwareRules': [
          {
            'model': model,
            'mode': 'exact',
            'versions': ['4.100.179'],
          },
        ],
      },
  ];
}

void main() {
  testWidgets(
    'connected suffixed Band 11 NFC selects the NFC installation variant',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceManagerProvider.overrideWith(_Band11NfcManager.new),
          ],
          child: MaterialApp(home: CloudStorePage(store: _Band11Store())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('自动匹配 · 小米手环 11 NFC'), findsOneWidget);
      expect(find.text('自动匹配 · 等待连接'), findsNothing);
      await tester.tap(find.text('腕上棋局').first);
      await tester.pumpAndSettle();
      final install = find.widgetWithText(FilledButton, '安装到小米手环 11 NFC');
      expect(install, findsOneWidget);
      expect(tester.widget<FilledButton>(install).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'connected unknown device is not labelled as waiting for connection',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceManagerProvider.overrideWith(_UnknownManager.new)],
          child: MaterialApp(home: CloudStorePage(store: _Band11Store())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('自动匹配 · 型号未识别'), findsOneWidget);
      expect(find.text('自动匹配 · 等待连接'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
