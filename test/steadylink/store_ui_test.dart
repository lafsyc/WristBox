import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/cloud_store.dart';
import 'package:oronbox/steadylink/mobile_app.dart';
import 'package:oronbox/steadylink/mobile_dock.dart';
import 'package:oronbox/steadylink/cloud_store_page.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart'
    show ProtocolState;

class StoreManager extends LocalDeviceManager {
  @override
  DeviceManagerState build() => const DeviceManagerState(
    pairedDevices: [
      MiWearState(
        name: '小米手环 9 Pro',
        addr: 'AA',
        connectType: 'spp',
        codename: 'n67',
      ),
      MiWearState(
        name: '小米手环 10',
        addr: 'BB',
        connectType: 'spp',
        codename: 'o66',
      ),
    ],
    currentDevice: MiWearState(
      name: '小米手环 10',
      addr: 'BB',
      connectType: 'spp',
      codename: 'o66',
    ),
    protocolState: ProtocolState.ready,
  );
}

class PreviewStore extends CloudStore {
  PreviewStore() : super(Dio());
  @override
  Future<Map<String, dynamic>> info() async => {
    'storeEnabled': true,
    'notice': '',
  };
  @override
  Future<List<Map<String, dynamic>>> catalog({bool manage = false}) async => [
    {
      'id': 'pokemon-336',
      'name': '口袋妖怪',
      'appId': 'pokemon',
      'packageName': 'com.ycc.koudaiyaoguai1',
      'version': '1.10.1',
      'versionCode': 43,
      'published': true,
      'category': '测试游戏',
      'size': 9941788,
      'iconId': 'e' * 64,
      'previewIds': <String>[],
      'supportedModels': ['n67', 'p67'],
      'description': '探索地图、收集精灵，体验回合制战斗。当前为测试版本。',
    },
    for (final pair in {
      '336': ['n67', 'p67'],
      '212': ['o66', 'band11'],
      '192': ['n66'],
      '432': ['o65', 'p65'],
    }.entries)
      {
        'id': pair.key,
        'name': '冒险猫',
        'appId': 'cats',
        'packageName': 'com.ycc.lafs.mxm.cat',
        'version': '1.0.0',
        'versionCode': 1,
        'published': true,
        'category': '休闲游戏',
        'size': 914716,
        'iconId': 'a' * 64,
        'previewIds': ['b' * 64, 'c' * 64, 'd' * 64],
        'supportedModels': pair.value,
        'description': '陪小猫穿过森林，跳过荆棘，收集罐头。轻点短跳，长按蓄力，松手起跳。',
      },
  ];
  @override
  Future<Uint8List> media(String id) async {
    const icon = String.fromEnvironment('WRISTBOX_PREVIEW_ICON');
    const preview = String.fromEnvironment('WRISTBOX_PREVIEW_SCREENSHOT');
    const pokemon = String.fromEnvironment('WRISTBOX_PREVIEW_POKEMON');
    final path = id.startsWith('e')
        ? pokemon
        : id.startsWith('a')
        ? icon
        : preview;
    if (path.isNotEmpty && File(path).existsSync()) {
      return File(path).readAsBytesSync();
    }
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAN0lEQVR4nO3QQREAMAgDQYpWRCC1bspUBZ+Ngcvs6bovFpebcQcIECBAgAABAgQIECBAgACBLzCVXwLzQoKdzgAAAABJRU5ErkJggg==',
    );
  }
}

class CountingStore extends PreviewStore {
  int reads = 0;
  @override
  Future<List<Map<String, dynamic>>> catalog({bool manage = false}) {
    reads++;
    return super.catalog(manage: manage);
  }
}

void main() {
  testWidgets(
    'embedded store refreshes after account changes and retains search',
    (tester) async {
      final store = CountingStore();
      Future<void> show(int revision) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [deviceManagerProvider.overrideWith(StoreManager.new)],
            child: MaterialApp(
              home: Scaffold(
                body: CloudStorePage(
                  store: store,
                  embedded: true,
                  accountRevision: revision,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(0);
      await tester.enterText(find.byType(TextField).first, '冒险猫');
      await tester.pumpAndSettle();
      expect(store.reads, 1);
      await show(1);
      expect(store.reads, 2);
      expect(find.text('1 款'), findsOneWidget);
      expect(find.byType(StoreAppCard), findsOneWidget);
      await tester.tap(find.text('创意工坊').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('creative-workshop-preview')),
        findsOneWidget,
      );
      expect(find.byType(StoreAppCard), findsNothing);
      await tester.tap(find.text('精选应用'));
      await tester.pumpAndSettle();
      expect(find.text('冒险猫'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '冒险猫',
      );
      expect(store.reads, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'embedded store keeps two columns at narrow widths and large text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (font.existsSync()) {
        await (FontLoader('Roboto')..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            ))
            .load();
      }
      Future<void> show(Brightness brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [deviceManagerProvider.overrideWith(StoreManager.new)],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: mobileTheme(brightness),
              home: RepaintBoundary(
                key: const ValueKey('store-grid-preview'),
                child: Scaffold(
                  extendBody: true,
                  body: CloudStorePage(
                    store: PreviewStore(),
                    embedded: true,
                    headerInAppBar: true,
                    deviceId: 'AA',
                    bottomInset: 90,
                  ),
                  bottomNavigationBar: MobileDock(
                    selectedIndex: 1,
                    onSelected: (_) {},
                    connected: true,
                    connecting: false,
                    onInstallPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      for (final brightness in Brightness.values) {
        await show(brightness);
        final cards = find.byType(StoreAppCard);
        expect(cards, findsNWidgets(2));
        expect(
          tester.getTopLeft(cards.at(0)).dy,
          tester.getTopLeft(cards.at(1)).dy,
        );
        await tester.runAsync(() async {
          for (final id in ['a' * 64, 'e' * 64]) {
            await precacheImage(
              MemoryImage(await PreviewStore().media(id)),
              tester.element(cards.first),
            );
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('store-grid-preview')),
          );
          final picture = await boundary.toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('build/store-grid-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
        await tester.tap(find.text('创意工坊').first);
        await tester.pumpAndSettle();
        expect(find.byType(StoreAppCard), findsNothing);
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('store-grid-preview')),
          );
          final picture = await boundary.toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('build/workshop-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
        await tester.tap(find.text('精选应用'));
        await tester.pumpAndSettle();
      }
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await show(Brightness.dark);
      await tester.tap(find.text('创意工坊').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('精选应用'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey('store-catalog')),
        const Offset(0, -520),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(StoreAppCard), findsNWidgets(2));
      await tester.tap(find.byType(StoreAppCard).last);
      await tester.pumpAndSettle();
      expect(find.byType(StoreAppPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'store groups variants, prioritizes connected band, previews and blocks mismatched models',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (font.existsSync()) {
        await (FontLoader('Microsoft YaHei UI')..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            ))
            .load();
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceManagerProvider.overrideWith(StoreManager.new)],
          child: RepaintBoundary(
            key: const ValueKey('store-preview'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'Microsoft YaHei UI',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff7160df),
                ),
              ),
              home: CloudStorePage(deviceId: 'AA', store: PreviewStore()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2 款'), findsOneWidget);
      expect(find.text('安装目标 · 小米手环 10'), findsOneWidget);
      await tester.ensureVisible(find.byType(StoreAppCard).first);
      await tester.pumpAndSettle();
      final cards = find.byType(StoreAppCard);
      expect(cards, findsNWidgets(2));
      expect(
        tester.getTopLeft(cards.at(0)).dy,
        tester.getTopLeft(cards.at(1)).dy,
      );
      expect(
        tester.getTopLeft(cards.at(1)).dx,
        greaterThan(tester.getTopRight(cards.at(0)).dx),
      );
      await tester.tap(find.text('冒险猫').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final install = find.widgetWithText(FilledButton, '安装到小米手环 10');
      expect(tester.widget<FilledButton>(install).onPressed, isNotNull);
      await tester.runAsync(() async {
        final context = tester.element(find.byType(StoreAppPage));
        for (final id in ['a' * 64, 'b' * 64]) {
          await precacheImage(
            MemoryImage(await PreviewStore().media(id)),
            context,
          );
        }
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('store-preview')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('dist').create(recursive: true);
        await File('dist/store-detail-preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      // Preview another supported model: installed target must not silently change.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('小米手环 9 Pro').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('当前连接的是小米手环 10'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '连接对应型号后安装'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('自动匹配当前手环'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(install).onPressed, isNotNull);
      // A missing model must be explicit, not a fallback to any existing package.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('小米手环 8 Pro').last);
      await tester.pumpAndSettle();
      expect(find.text('以下为其他型号的预览，仅供参考。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '连接对应型号后安装'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
