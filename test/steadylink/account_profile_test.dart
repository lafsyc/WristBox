import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/account_profile_dialog.dart';
import 'package:oronbox/steadylink/mobile_app.dart';
import 'package:oronbox/steadylink/wristbox_account.dart';

class ProfilePreviewService extends WristBoxAccountService {
  bool fail = false;
  @override
  Future<WristBoxSession> refresh(WristBoxSession session) async => session;
  @override
  Future<WristBoxSession> updateProfile(
    WristBoxSession session,
    String name,
  ) async {
    if (fail) throw StateError('网络暂时不可用，请重试');
    return WristBoxSession(
      session.token,
      session.email,
      session.role,
      id: session.id,
      nickname: name,
    );
  }
}

void main() {
  testWidgets(
    'profile saves nickname, preserves edits on failure and fits small screens',
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
      final service = ProfilePreviewService();
      const session = WristBoxSession(
        'test-token',
        '3615541950@qq.com',
        'admin',
        id: 100,
        nickname: 'WristBox',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: mobileTheme(Brightness.dark),
          home: RepaintBoundary(
            key: const ValueKey('profile-preview'),
            child: Scaffold(
              body: AccountProfileDialog(service: service, session: session),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ID  100'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '新的昵称');
      await tester.tap(find.text('保存昵称'));
      await tester.pumpAndSettle();
      expect(find.text('昵称已保存'), findsOneWidget);
      service.fail = true;
      await tester.enterText(find.byType(TextField), '保留草稿');
      await tester.tap(find.text('保存昵称'));
      await tester.pumpAndSettle();
      expect(find.text('保留草稿'), findsOneWidget);
      expect(find.text('网络暂时不可用，请重试'), findsOneWidget);
      service.fail = false;
      await tester.enterText(find.byType(TextField), 'WristBox');
      await tester.tap(find.text('保存昵称'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('profile-preview')),
        );
        final picture = await boundary.toImage();
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File('build/account-profile-dark.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('保存昵称'), findsOneWidget);
    },
  );
}
