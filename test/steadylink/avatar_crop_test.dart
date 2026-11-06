import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/avatar_crop.dart';
import 'package:oronbox/steadylink/mobile_app.dart';
import 'package:oronbox/steadylink/profile_dashboard.dart';
import 'package:oronbox/steadylink/wristbox_account.dart';

Future<ui.Image> sample() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 200),
    Paint()..color = Colors.red,
  );
  canvas.drawRect(
    const Rect.fromLTWH(200, 0, 200, 200),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(400, 200);
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('large original becomes bounded pixel-only upload and crop selects requested region', () async {
    final image = await sample();
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final large = Uint8List(png.lengthInBytes + 3 * 1024 * 1024)
      ..setRange(0, png.lengthInBytes, png.buffer.asUint8List());
    final decoded = await decodeAvatarPreview(large);
    final data = await encodeAvatarCrop(
      decoded,
      avatarCropRect(400, 200, 1, const Offset(300, 100)),
    );
    expect(data.length, lessThan(2 * 1024 * 1024));
    final codec = await ui.instantiateImageCodec(data);
    final output = (await codec.getNextFrame()).image;
    expect(output.width, 512);
    expect(output.height, 512);
    final pixels = (await output.toByteData())!;
    final pixel = (256 * 512 + 256) * 4;
    expect(pixels.getUint8(pixel + 2), greaterThan(200));
    expect(pixels.getUint8(pixel), lessThan(100));
    expect(avatarCropRect(400, 200, 5, const Offset(-999, 999)).left, 0);
    await expectLater(
      decodeAvatarPreview(Uint8List(20 * 1024 * 1024 + 1)),
      throwsStateError,
    );
    await expectLater(
      decodeAvatarPreview(Uint8List.fromList([1, 2, 3])),
      throwsStateError,
    );
    output.dispose();
    codec.dispose();
    decoded.dispose();
    image.dispose();
  });

  testWidgets('crop supports drag zoom and reset', (tester) async {
    final image = (await tester.runAsync(sample))!;
    addTearDown(image.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AvatarCropDialog(image: image)),
      ),
    );
    await tester.pumpAndSettle();
    final slider = find.byType(Slider);
    tester.widget<Slider>(slider).onChanged!(2);
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, 2);
    await tester.drag(
      find.byKey(const ValueKey('avatar-crop-canvas')),
      const Offset(40, 0),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('重置裁切'));
    await tester.tap(find.text('重置裁切'));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'identity and membership placeholder fit both themes and enlarged text',
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
          MaterialApp(
            theme: mobileTheme(brightness),
            home: RepaintBoundary(
              key: const ValueKey('identity-preview'),
              child: Scaffold(
                appBar: AppBar(title: const Text('我的')),
                body: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    AccountIdentityCard(
                      session: const WristBoxSession(
                        'sample',
                        'test@example.com',
                        'admin',
                        id: 100,
                        nickname: 'WristBox',
                      ),
                      onOpen: () {},
                    ),
                    const SizedBox(height: 14),
                    const MembershipPlaceholder(),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      for (final brightness in Brightness.values) {
        await show(brightness);
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('identity-preview')),
          );
          final picture = await boundary.toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('build/identity-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      await tester.tap(find.text('会员中心'));
      await tester.pumpAndSettle();
      expect(find.text('会员功能筹备中'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await show(Brightness.dark);
      expect(tester.takeException(), isNull);
      expect(find.text('ID 100'), findsOneWidget);
    },
  );
}
