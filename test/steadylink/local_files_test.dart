import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/local_files.dart';
import 'package:oronbox/steadylink/mobile_app.dart';

void main() {
  test(
    'local filters combine name, folder, extension, age and stable sorting',
    () {
      final now = DateTime(2026, 11, 4);
      final files = [
        LocalPackageFile(
          id: '1',
          name: '口袋妖怪.RPK',
          directory: 'Download',
          size: 100,
          modified: now.millisecondsSinceEpoch,
        ),
        LocalPackageFile(
          id: '2',
          name: '表盘.BIN',
          directory: 'Download',
          size: 300,
          modified: now
              .subtract(const Duration(days: 2))
              .millisecondsSinceEpoch,
        ),
        const LocalPackageFile(
          id: '3',
          name: '旧应用.rpk',
          directory: 'Documents',
          size: 200,
          modified: 0,
        ),
      ];
      expect(filterLocalFiles(files, extension: 'bin').single.id, '2');
      expect(
        filterLocalFiles(files, query: 'download', days: 7, now: now).length,
        2,
      );
      expect(filterLocalFiles(files, query: '口袋').single.id, '1');
      expect(
        filterLocalFiles(files, days: 7, extension: 'rpk', now: now).single.id,
        '1',
      );
      expect(
        filterLocalFiles(files, sort: LocalFileSort.size).map((f) => f.id),
        ['2', '3', '1'],
      );
      expect(filterLocalFiles(files).map((f) => f.id), ['1', '2', '3']);
    },
  );
  testWidgets('local files browse, filter, select and handle denied access', (
    tester,
  ) async {
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
    var allowed = true;
    var settings = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalFileService.channel, (call) async {
          if (call.method == 'grantAllFiles') {
            settings++;
            return null;
          }
          if (call.method == 'scan') {
            return {
              'allFiles': allowed,
              'canAllFiles': true,
              'folders': 0,
              'files': allowed
                  ? [
                      {
                        'id': 'one',
                        'name': '口袋妖怪_1.10.1.rpk',
                        'directory': 'Download',
                        'size': 9941788,
                        'modified': now,
                      },
                      {
                        'id': 'two',
                        'name': '简约表盘.bin',
                        'directory': 'Download',
                        'size': 412345,
                        'modified': now - 86400000,
                      },
                      {
                        'id': 'three',
                        'name': '冒险猫.rpk',
                        'directory': 'Documents',
                        'size': 914716,
                        'modified': now - 86400000 * 10,
                      },
                    ]
                  : [],
            };
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalFileService.channel, null),
    );
    String? picked;
    Future<void> show() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: mobileTheme(Brightness.dark),
          home: RepaintBoundary(
            key: const ValueKey('local-preview'),
            child: Scaffold(
              appBar: AppBar(title: const Text('WristBox')),
              body: LocalFilesPane(
                key: UniqueKey(),
                bottomInset: 0,
                onPick: () {},
                onInstall: (f) async {
                  picked = f.id;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show();
    expect(find.text('找到 3 个文件'), findsOneWidget);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('local-preview')),
      );
      final picture = await boundary.toImage();
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File('build/local-files-dark.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
    await tester.tap(find.text('BIN'));
    await tester.pumpAndSettle();
    expect(find.text('找到 1 个文件'), findsOneWidget);
    await tester.tap(find.text('简约表盘.bin'));
    await tester.pumpAndSettle();
    expect(picked, 'two');
    await tester.tap(find.text('全部格式'));
    await tester.enterText(find.byType(TextField), 'Documents');
    await tester.pumpAndSettle();
    expect(find.text('找到 1 个文件'), findsOneWidget);
    await tester.tap(find.text('最近 7 天'));
    await tester.pumpAndSettle();
    expect(find.text('找到 0 个文件'), findsOneWidget);
    allowed = false;
    await show();
    expect(find.text('开启手机文件访问'), findsOneWidget);
    await tester.tap(find.text('开启手机文件访问'));
    await tester.pumpAndSettle();
    expect(settings, 1);
    expect(find.text('找到 0 个文件'), findsOneWidget);
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
