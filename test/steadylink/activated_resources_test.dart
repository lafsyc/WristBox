import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/activated_resources_page.dart';
import 'package:oronbox/steadylink/backend.dart';
import 'package:oronbox/steadylink/cloud_store.dart';
import 'package:oronbox/steadylink/mobile_app.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart';

const band = MiWearState(
  name: '我的手环 9 Pro',
  addr: 'AA:BB:CC:DD:EE:01',
  connectType: 'spp',
  codename: 'n67',
);

class LibraryManager extends LocalDeviceManager {
  @override
  DeviceManagerState build() => const DeviceManagerState(
    currentDevice: band,
    pairedDevices: [band],
    protocolState: ProtocolState.ready,
    systemInfo: SystemInfo(
      serialNumber: 'LIBSN000001',
      model: 'n67',
      firmwareVersion: '1',
      imei: '',
    ),
    apps: [
      AppInfo(
        packageName: 'com.wristbox.demo',
        appName: '激活测试',
        versionCode: 1,
      ),
    ],
  );
  @override
  Future<void> refreshDeviceData() async {}
  @override
  Future<void> fetchApps() async {}
  void changeBand() => state = state.copyWith(
    systemInfo: state.systemInfo!.copyWith(serialNumber: 'LIBSN000002'),
  );
}

class LibraryStore extends CloudStore {
  LibraryStore() : super(Dio());
  bool empty = false, offline = false;
  final serials = <String>[];
  @override
  Future<Map<String, dynamic>> activatedResources({
    String model = '',
    String serial = '',
    int offset = 0,
  }) async {
    serials.add(serial);
    if (offline) throw StateError('网络连接中断，请重试');
    return {
      'total': empty ? 0 : 2,
      'storeEnabled': true,
      'items': empty
          ? []
          : [
              {
                'id': 'a' * 32,
                'name': '激活测试',
                'packageName': 'com.wristbox.demo',
                'iconId': '',
                'model': 'n67',
                'serialHint': '••••0001',
                'status': 'active',
                'activatedAt': 1793800000,
                'matchesDevice': serial == 'LIBSN000001',
                'resource': {
                  'id': 'c' * 32,
                  'version': '1.1.0',
                  'versionCode': 2,
                },
              },
              {
                'id': 'b' * 32,
                'name': '已撤销的测试资源',
                'packageName': 'com.wristbox.other',
                'iconId': '',
                'model': 'o66',
                'serialHint': '••••0002',
                'status': 'revoked',
                'activatedAt': 1793700000,
                'matchesDevice': false,
                'resource': null,
              },
            ],
    };
  }
}

class RecordingBackend extends SteadyBackend {
  RecordingBackend(super.ref);
  String? selectedGrant, resource, address;
  @override
  Future<void> installCloud(
    CloudStore store,
    String resourceId,
    String deviceId,
    void Function(double) progress, {
    required String expectedModel,
    String? expectedGrantId,
    void Function(String)? onStage,
    Future<bool> Function(String model, String serial)? onActivationRequired,
  }) async {
    selectedGrant = expectedGrantId;
    resource = resourceId;
    address = deviceId;
    progress(1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('quick update targets the selected resource and bound grant', (
    tester,
  ) async {
    late RecordingBackend backend;
    final store = LibraryStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceManagerProvider.overrideWith(LibraryManager.new),
          steadyBackendProvider.overrideWith(
            (ref) => backend = RecordingBackend(ref),
          ),
        ],
        child: MaterialApp(home: ActivatedResourcesPage(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '更新'));
    await tester.pumpAndSettle();
    expect(backend.selectedGrant, 'a' * 32);
    expect(backend.resource, 'c' * 32);
    expect(backend.address, band.addr);
    expect(find.textContaining('已安装到绑定手环'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final chinese = File('C:/Windows/Fonts/msyh.ttc');
    if (chinese.existsSync()) {
      await (FontLoader(
        'LibraryChinese',
      )..addFont(chinese.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  test(
    'install action distinguishes unknown, installed, update and downgrade',
    () {
      String action(bool matched, bool known, int? version) =>
          activatedResourceAction(
            matchesDevice: matched,
            appsKnown: known,
            installedVersion: version,
            latestVersion: 2,
          );
      expect(action(false, true, 1), '连接并安装');
      expect(action(true, false, 1), '安装 / 更新');
      expect(action(true, true, 0), '安装 / 更新');
      expect(action(true, true, null), '安装');
      expect(action(true, true, 1), '更新');
      expect(action(true, true, 2), '重新安装');
      expect(action(true, true, 3), '已安装更新版本');
    },
  );
  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets(
      'library bindings, latest version and device changes ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final manager = LibraryManager(),
            store = LibraryStore(),
            key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [deviceManagerProvider.overrideWith(() => manager)],
            child: MaterialApp(
              theme: mobileTheme(brightness).copyWith(
                textTheme: mobileTheme(brightness).textTheme
                    .apply(fontFamily: 'LibraryChinese'),
              ),
              home: RepaintBoundary(
                key: key,
                child: ActivatedResourcesPage(store: store),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('已激活资源'), findsOneWidget);
        expect(find.textContaining('SN ••••0001'), findsOneWidget);
        expect(find.text('更新'), findsOneWidget);
        expect(find.text('当前已连接绑定设备'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '授权已撤销'))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File(
            'design/activated-resources-0.13.1/library-${brightness.name}.png',
          );
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        manager.changeBand();
        await tester.pumpAndSettle();
        expect(store.serials.last, 'LIBSN000002');
        expect(find.text('更新'), findsNothing);
        expect(find.text('连接并安装'), findsOneWidget);
        expect(find.text('当前已连接绑定设备'), findsNothing);
        tester.view.physicalSize = const Size(320, 820);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'empty library and a failed refresh do not retain install actions',
    (tester) async {
      final store = LibraryStore()..empty = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceManagerProvider.overrideWith(LibraryManager.new)],
          child: MaterialApp(home: ActivatedResourcesPage(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('这台手环还没有激活资源'), findsOneWidget);
      store.empty = false;
      await tester.tap(find.byTooltip('刷新资源与设备版本'));
      await tester.pumpAndSettle();
      expect(find.text('更新'), findsOneWidget);
      store.offline = true;
      await tester.tap(find.byTooltip('刷新资源与设备版本'));
      await tester.pumpAndSettle();
      expect(find.text('网络连接中断，请重试'), findsOneWidget);
      expect(find.text('更新'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
