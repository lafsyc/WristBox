import 'dart:io';

import 'consent_fixture.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:oronbox/steadylink/mobile_dock.dart';
import 'package:oronbox/steadylink/cloud_store_page.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/mobile_app.dart';
import 'package:oronbox/steadylink/appearance.dart';
import 'package:oronbox/steadylink/mobile_motion.dart';
import 'package:oronbox/steadylink/band_illustration.dart';
import 'package:oronbox/steadylink/operation_queue.dart';
import 'package:oronbox/steadylink/backend.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart'
    show ProtocolState;

class MobilePreviewManager extends LocalDeviceManager {
  MobilePreviewManager(this.initial);
  final DeviceManagerState initial;
  @override
  DeviceManagerState build() => initial;
}

class CancelledFilePicker extends FilePickerPlatform {
  int calls = 0;
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    return [];
  }
}

void main() {
  setUpAll(acceptTestConsent);
  testWidgets(
    'mobile navigation, small screens and both themes retain device data',
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
      Future<void> show(DeviceManagerState state) async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              deviceManagerProvider.overrideWith(
                () => MobilePreviewManager(state),
              ),
            ],
            child: RepaintBoundary(
              key: ValueKey('mobile-preview'),
              child: SteadyMobileApp(initialize: noRuntime),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('mobile-preview')),
          );
          final picture = await boundary.toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('build/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      Future<void> toggleTheme() async {
        final scope = ProviderScope.containerOf(
          tester.element(find.byType(MobileHome)),
        );
        await tester.runAsync(
          () => scope.read(darkThemeProvider.notifier).toggle(),
        );
      }

      await show(const DeviceManagerState());
      expect(find.text('登录小米账号'), findsOneWidget);
      expect(find.text('应用工坊'), findsNothing);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('connection-guide-entry')), 200);
      await tester.tap(find.byKey(const ValueKey('connection-guide-entry')));
      await tester.pumpAndSettle();
      expect(find.text('先获取 Key，再连接手环'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      await capture('steadylink-android-welcome');
      const devices = [
        MiWearState(
          name: '小米手环 9 Pro',
          addr: 'AA:BB:CC:DD:EE:01',
          connectType: 'spp',
        ),
        MiWearState(
          name: '小米手环 10',
          addr: 'AA:BB:CC:DD:EE:02',
          connectType: 'spp',
        ),
      ];
      await show(
        DeviceManagerState(
          currentDevice: devices.first,
          pairedDevices: devices,
          protocolState: ProtocolState.ready,
          battery: const BatteryStatus(capacity: 86),
          apps: const [
            AppInfo(
              packageName: 'example.reader',
              appName: '腕上阅读',
              canRemove: true,
            ),
          ],
        ),
      );
      expect(find.text('86%'), findsOneWidget);
      expect(
        tester.widget<ConnectionOrbit>(find.byType(ConnectionOrbit)).battery,
        86,
      );
      await capture('steadylink-android-dark');
      expect(find.byTooltip('切换明暗主题'), findsNothing);
      await toggleTheme();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await capture('steadylink-android-light');
      expect(find.text('每次连接，都从容。'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileHome)),
      );
      final queue = container.read(steadyBackendProvider).queue;
      final previewJob =
          InstallJob(
              path: '口袋妖怪.rpk',
              deviceId: devices.first.addr,
              deviceName: devices.first.name,
            )
            ..phase = InstallPhase.installing
            ..progress = .42;
      queue.jobs.add(previewJob);
      queue.clearFinished();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getTopLeft(find.byType(MobileTransferCard)).dy,
        greaterThan(
          tester
              .getBottomLeft(find.byKey(const ValueKey('mobile-device-hero')))
              .dy,
        ),
      );
      expect(tester.takeException(), isNull);
      await capture('steadylink-android-install-light');
      await toggleTheme();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await capture('steadylink-android-install-dark');
      await toggleTheme();
      previewJob.phase = InstallPhase.succeeded;
      queue.clearFinished();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.byTooltip('设备操作').first);
      await tester.tap(find.byTooltip('设备操作').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('从列表删除'), findsOneWidget);
      await tester.tap(find.text('更新 Key'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('更新连接 Key'), findsOneWidget);
      await tester.tap(find.text('保存新 Key'));
      await tester.pump();
      expect(find.text('请输入完整的 32 位 Key'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      await tester.tap(find.text('应用').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('腕上阅读'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '应用'), findsOneWidget);
      expect(find.text('腕上应用'), findsNothing);
      expect(find.byTooltip('安装应用'), findsOneWidget);
      await capture('steadylink-android-apps');
      await tester.tap(find.byTooltip('卸载 腕上阅读'));
      await tester.pumpAndSettle();
      expect(find.text('卸载 腕上阅读？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      await capture('steadylink-android-settings');
      expect(find.widgetWithText(AppBar, '我的'), findsOneWidget);
      expect(find.text('WristBox'), findsNothing);
      final picker = CancelledFilePicker();
      final previousPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previousPicker);
      await tester.tap(find.byKey(const ValueKey('mobile-quick-install')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(picker.calls, 1);
      expect(
        tester.widget<MobileDock>(find.byType(MobileDock)).selectedIndex,
        3,
      );
      await tester.tap(find.text('商店').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CloudStorePage), findsOneWidget);
      expect(find.byTooltip('刷新商店'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '应用商店'), findsOneWidget);
      expect(find.text('应用商店'), findsOneWidget);
      final storeState = tester.state(find.byType(CloudStorePage));
      await tester.enterText(find.byType(TextField).first, '口袋');
      await tester.tap(find.text('应用').last);
      await tester.pump();
      await tester.tap(find.text('商店').last);
      await tester.pump();
      expect(tester.state(find.byType(CloudStorePage)), same(storeState));
      expect(find.text('口袋'), findsOneWidget);
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.text('已激活资源'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('动效预览'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('动效预览'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('正在传输'), findsOneWidget);
      await capture('steadylink-android-motion');
      await tester.tap(find.text('确认'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('等待手环确认'), findsOneWidget);
      expect(find.text('安装完成'), findsNothing);
      await tester.tap(find.text('完成'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('安装完成'), findsOneWidget);
      tester.view.physicalSize = const Size(320, 640);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await show(const DeviceManagerState());
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await show(
        DeviceManagerState(
          currentDevice: devices.first,
          pairedDevices: devices,
          protocolState: ProtocolState.ready,
          battery: const BatteryStatus(capacity: 86),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wave actually moves, reduced motion stops it, confirmation stays distinct',
    (tester) async {
      final job =
          InstallJob(path: 'demo.rpk', deviceId: 'preview', deviceName: '预览')
            ..phase = InstallPhase.installing
            ..progress = .65;
      Future<void> show(bool reduce) => tester.pumpWidget(
        MaterialApp(
          theme: mobileTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Scaffold(body: MobileTransferCard(job: job)),
          ),
        ),
      );
      await show(false);
      final finder = find.byKey(const ValueKey('transfer-wave'));
      await tester.pump(const Duration(milliseconds: 400));
      final before = tester.widget<CustomPaint>(finder).painter!;
      await tester.pump(const Duration(milliseconds: 400));
      final after = tester.widget<CustomPaint>(finder).painter!;
      expect(after.shouldRepaint(before), isTrue);
      await show(true);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      job.progress = 1;
      await show(true);
      await tester.pumpAndSettle();
      expect(find.text('等待手环确认'), findsOneWidget);
      expect(find.text('安装完成'), findsNothing);
    },
  );
  testWidgets(
    'band screen uses real status, handles unknown/zero battery and respects reduced motion',
    (tester) async {
      Future<void> show({
        bool ready = true,
        int? battery,
        InstallJob? job,
        bool reduce = false,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: mobileTheme(Brightness.dark),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduce),
              child: Scaffold(
                body: ConnectionOrbit(
                  ready: ready,
                  connecting: false,
                  battery: battery,
                  job: job,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      BandIllustration band() =>
          tester.widget<BandIllustration>(find.byType(BandIllustration));
      await show();
      expect(band().battery, isNull);
      expect(band().screen, BandScreen.battery);
      await show(battery: 0);
      expect(band().battery, 0);
      await show(ready: false, battery: 86);
      expect(band().battery, isNull);
      expect(band().screen, BandScreen.idle);
      final job =
          InstallJob(path: 'demo.rpk', deviceId: 'preview', deviceName: '预览')
            ..phase = InstallPhase.installing
            ..progress = .42;
      await show(battery: 86, job: job);
      expect(band().screen, BandScreen.transfer);
      expect(band().progress, .42);
      final before = band().phase;
      await tester.pump(const Duration(milliseconds: 500));
      expect(band().phase, isNot(before));
      job.progress = 1;
      await show(job: job);
      expect(band().screen, BandScreen.confirming);
      job.phase = InstallPhase.succeeded;
      await show(job: job);
      expect(band().screen, BandScreen.done);
      job.phase = InstallPhase.failed;
      await show(job: job);
      expect(band().screen, BandScreen.error);
      job.phase = InstallPhase.connecting;
      await show(job: job);
      expect(band().screen, BandScreen.connecting);
      await show(battery: 86, reduce: true);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      final paused = band().phase;
      await tester.pump(const Duration(seconds: 1));
      expect(band().phase, paused);
    },
  );

  testWidgets('render band states and motion at hero and list sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 350);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
    }
    const screens = [
      BandScreen.connecting,
      BandScreen.battery,
      BandScreen.transfer,
      BandScreen.confirming,
      BandScreen.done,
      BandScreen.error,
    ];
    for (var frame = 0; frame < 32; frame++) {
      await tester.pumpWidget(
        MaterialApp(
          theme: mobileTheme(Brightness.dark),
          home: RepaintBoundary(
            key: const ValueKey('band-states'),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'WristBox · 手环里的实时状态',
                      style: TextStyle(fontSize: 22),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var i = 0; i < screens.length; i++)
                          Column(
                            children: [
                              BandIllustration(
                                pro: true,
                                screen: screens[i],
                                battery: 68,
                                progress: .42,
                                phase: frame / 32,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                [
                                  '正在连接',
                                  '电量 68%',
                                  '传输 42%',
                                  '等待确认',
                                  '安装完成',
                                  '安装失败',
                                ][i],
                              ),
                              const SizedBox(height: 18),
                              BandIllustration(
                                screen: screens[i],
                                battery: 68,
                                progress: .42,
                                phase: frame / 32,
                                width: 36,
                                height: 48,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('band-states')),
        );
        final picture = await boundary.toImage();
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/band-motion-frames')
          ..createSync(recursive: true);
        await File(
          '${directory.path}/frame-${frame.toString().padLeft(2, '0')}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }
  });
}
