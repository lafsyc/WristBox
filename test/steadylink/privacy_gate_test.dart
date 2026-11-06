import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/steadylink/privacy_gate.dart';
import 'package:oronbox/steadylink/legal_documents.dart';
import 'package:oronbox/steadylink/mobile_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.instance.init();
    await SharedPrefsService.instance.remove(consentPreference);
  });

  testWidgets(
    'no runtime before explicit consent; every document must be read',
    (tester) async {
      tester.view.physicalSize = const Size(390, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var starts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyGate(
            initialize: () async {
              starts++;
            },
            child: const Text('home'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(starts, 0);
      expect(find.text('home'), findsNothing);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      for (final doc in legalDocuments) {
        await tester.ensureVisible(find.text(doc.title));
        await tester.tap(find.text(doc.title));
        await tester.pumpAndSettle();
        expect(find.text('请阅读至文末'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('— 全文结束 —'),
          600,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('已阅读，返回'));
        await tester.pumpAndSettle();
      }
      expect(starts, 0);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('同意并进入 WristBox'));
      await tester.tap(find.text('同意并进入 WristBox'));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(find.text('home'), findsOneWidget);
      expect(
        SharedPrefsService.instance.getString(consentPreference),
        legalVersion,
      );
    },
  );

  testWidgets('current consent enters; changed version asks again', (
    tester,
  ) async {
    final prefs = SharedPrefsService.instance;
    await prefs.setString(consentPreference, legalVersion);
    var starts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyGate(
          initialize: () async {
            starts++;
          },
          child: const Text('home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(find.text('home'), findsOneWidget);
    await prefs.setString(consentPreference, 'old-version');
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyGate(
          key: UniqueKey(),
          initialize: () async {
            starts++;
          },
          child: const Text('home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(find.text('开始之前'), findsOneWidget);
  });

  testWidgets('privacy welcome renders light dark and small viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 960);
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
    for (final brightness in [Brightness.dark, Brightness.light]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: mobileTheme(brightness),
          home: RepaintBoundary(
            key: const ValueKey('privacy'),
            child: PrivacyGate(
              initialize: () async {},
              child: const Text('home'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('privacy')),
        );
        final picture = await boundary.toImage();
        final data = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'design/privacy-0.14.0/welcome-${brightness.name}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        picture.dispose();
      });
    }
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
