import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/admin_activation_page.dart';
import 'package:oronbox/steadylink/admin_api.dart';
import 'package:oronbox/steadylink/backend.dart';
import 'package:oronbox/steadylink/cloud_store.dart';
import 'package:oronbox/steadylink/resource_activation_dialog.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';

import 'cloud_cleanup_test.dart'
    show InstallManager, FailingCleanupSource, target;

class IdentityManager extends InstallManager {
  IdentityManager() : super(true);
  int reads = 0;
  @override
  Future<void> fetchSystemInfo() async {
    reads++;
    state = state.copyWith(
      systemInfo: const SystemInfo(
        serialNumber: 'TESTSN000001',
        firmwareVersion: '1',
        imei: '',
        model: 'n67',
      ),
    );
  }

  void changeIdentity() => state = state.copyWith(
    systemInfo: state.systemInfo!.copyWith(serialNumber: 'OTHERDEVICE2'),
  );
  void installNewerVersion() => state = state.copyWith(
    apps: const [
      AppInfo(packageName: 'test.app', appName: 'Test', versionCode: 2),
    ],
  );
}

class ActivationStore extends CloudStore {
  ActivationStore() : super(Dio());
  bool activated = false;
  int opens = 0;
  String? selectedGrant;
  VoidCallback? onCheck;
  @override
  Future<Map<String, dynamic>> activationStatus(
    String resource,
    String model,
    String serial, {
    String? grantId,
  }) async {
    expect(serial, 'TESTSN000001');
    selectedGrant = grantId;
    onCheck?.call();
    return {'required': true, 'activated': activated};
  }

  @override
  Future<CloudPackageSource> open(
    String id,
    String device,
    String model, {
    String serial = '',
    bool activationRequired = false,
    String? grantId,
  }) async {
    expect(serial, 'TESTSN000001');
    expect(activationRequired, isTrue);
    expect(grantId, selectedGrant);
    opens++;
    return FailingCleanupSource();
  }
}

class AdminAdapter implements HttpClientAdapter {
  int generated = 0;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    dynamic value;
    if (o.path.endsWith('resources')) {
      value = {
        'resources': [
          {
            'id': 'a' * 32,
            'packageName': 'com.wristbox.activationdemo',
            'name': '激活测试',
            'activationRequired': true,
          },
        ],
      };
    } else if (o.method == 'POST') {
      generated++;
      expect(o.data['count'], 5);
      value = {
        'cards': [
          {'id': 'b' * 32, 'code': 'TEST-ONLY-NOT-A-REAL-CARD'},
        ],
      };
    } else {
      value = {
        'total': 1,
        'items': [
          {
            'id': 'b' * 32,
            'suffix': 'ABC123',
            'created': 1793800000,
            'expires': 1893800000,
            'redeemed': 1793800001,
            'revoked': 0,
            'userId': 10001,
            'email': 'demo@example.com',
            'model': 'n67',
            'serialHint': '••••0001',
          },
        ],
      };
    }
    return ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('library installation pins the grant and blocks a downgrade', () async {
    final manager = IdentityManager(),
        store = ActivationStore()..activated = true;
    final container = ProviderContainer(
      overrides: [deviceManagerProvider.overrideWith(() => manager)],
    );
    addTearDown(container.dispose);
    final backend = container.read(steadyBackendProvider);
    container.read(deviceManagerProvider);
    manager.installNewerVersion();
    await expectLater(
      backend.installCloud(
        store,
        'a' * 32,
        target.addr,
        (_) {},
        expectedModel: 'n67',
        expectedGrantId: 'b' * 32,
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'reason', contains('更高版本')),
      ),
    );
    expect(store.selectedGrant, 'b' * 32);
  });
  setUpAll(() async {
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
    final chinese = File('C:/Windows/Fonts/msyh.ttc');
    if (chinese.existsSync()) {
      await (FontLoader(
        'TestChinese',
      )..addFont(chinese.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  test(
    'cancel activation opens no download and leaves connection intact',
    () async {
      final manager = IdentityManager(), store = ActivationStore();
      final container = ProviderContainer(
        overrides: [deviceManagerProvider.overrideWith(() => manager)],
      );
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(steadyBackendProvider)
            .installCloud(
              store,
              'a' * 32,
              target.addr,
              (_) {},
              expectedModel: 'n67',
              onActivationRequired: (_, serial) async => false,
            ),
        throwsA(isA<ActivationCancelled>()),
      );
      expect(manager.reads, 1);
      expect(store.opens, 0);
      expect(manager.disconnects, 0);
    },
  );
  test('identity change after server status stops download', () async {
    final manager = IdentityManager(),
        store = ActivationStore()..activated = true;
    final container = ProviderContainer(
      overrides: [deviceManagerProvider.overrideWith(() => manager)],
    );
    addTearDown(container.dispose);
    store.onCheck = manager.changeIdentity;
    await expectLater(
      container
          .read(steadyBackendProvider)
          .installCloud(
            store,
            'a' * 32,
            target.addr,
            (_) {},
            expectedModel: 'n67',
          ),
      throwsStateError,
    );
    expect(store.opens, 0);
  });
  test(
    'activated device passes serial and required binding into native source',
    () async {
      final manager = IdentityManager(),
          store = ActivationStore()..activated = true;
      final container = ProviderContainer(
        overrides: [deviceManagerProvider.overrideWith(() => manager)],
      );
      addTearDown(container.dispose);
      await container
          .read(steadyBackendProvider)
          .installCloud(
            store,
            'a' * 32,
            target.addr,
            (_) {},
            expectedModel: 'n67',
          );
      expect(store.opens, 1);
    },
  );
  testWidgets(
    'activation dialog retains card after failure, retry and cancel',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'TestChinese'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => ResourceActivationDialog(
                    appName: '激活测试',
                    model: 'n67',
                    serial: 'TESTSN000001',
                    activate: (code) async {
                      expect(code, 'sample-card');
                      attempts++;
                      throw StateError('卡密无效，请核对');
                    },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sample-card');
      await tester.tap(find.text('激活并继续安装'));
      await tester.pumpAndSettle();
      expect(find.text('卡密无效，请核对'), findsOneWidget);
      expect(find.text('sample-card'), findsOneWidget);
      expect(attempts, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceActivationDialog), findsNothing);
    },
  );
  testWidgets('admin lists masked bindings and generates cards once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = AdminAdapter(), key = GlobalKey();
    final dio = Dio()..httpClientAdapter = adapter;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'TestChinese',
          colorSchemeSeed: const Color(0xff8970db),
        ),
        home: RepaintBoundary(
          key: key,
          child: AdminActivationPage(api: AdminApi(dio)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ID 10001'), findsOneWidget);
    expect(find.textContaining('SN ••••0001'), findsOneWidget);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('design/activation-0.13.0/admin-activation.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('生成卡密'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(adapter.generated, 1);
    expect(find.textContaining('TEST-ONLY-NOT-A-REAL-CARD'), findsOneWidget);
    expect(find.text('导出 TXT'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('已保存，关闭'));
    await tester.pumpAndSettle();
  });
}
