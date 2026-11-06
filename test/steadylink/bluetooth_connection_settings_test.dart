import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/src/core/providers/app_settings_providers.dart';
import 'package:oronbox/steadylink/bluetooth_connection_settings.dart';

void main() {
  testWidgets(
    'repair mode defaults off, cancellation does not persist, confirmation does',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SharedPrefsService.instance.init();
      await SharedPrefsService.instance.reload();
      await tester.pumpWidget(
        const MaterialApp(home: BluetoothConnectionSettings()),
      );
      expect(find.text('优先直接连接'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        SharedPrefsService.instance.getBool(androidRebuildBondSettingKey),
        isNot(true),
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('启用兼容方式'));
      await tester.pumpAndSettle();
      expect(
        SharedPrefsService.instance.getBool(androidRebuildBondSettingKey),
        true,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        SharedPrefsService.instance.getBool(androidRebuildBondSettingKey),
        false,
      );
    },
  );
}
