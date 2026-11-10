import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/src/core/providers/app_settings_providers.dart';
import 'package:oronbox/steadylink/bluetooth_connection_settings.dart';

void main() {
  test(
    'upgrade enables bond rebuilding once and preserves later opt-out',
    () async {
      SharedPreferences.setMockInitialValues({
        androidRebuildBondSettingKey: false,
        'auto_reconnect_on_disconnect': true,
      });
      await SharedPrefsService.instance.init();
      await SharedPrefsService.instance.reload();
      await initializeAndroidConnectionPreferences();
      expect(androidRebuildBondEnabled(), isTrue);
      expect(
        SharedPrefsService.instance.getBool('auto_reconnect_on_disconnect'),
        isTrue,
      );
      await SharedPrefsService.instance.setBool(
        androidRebuildBondSettingKey,
        false,
      );
      await initializeAndroidConnectionPreferences();
      await SharedPrefsService.instance.reload();
      expect(androidRebuildBondEnabled(), isFalse);
    },
  );
  testWidgets('automatic recovery defaults on and remembers the off choice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.instance.init();
    await SharedPrefsService.instance.reload();
    await tester.pumpWidget(
      const MaterialApp(home: BluetoothConnectionSettings()),
    );
    final toggle = find.widgetWithText(SwitchListTile, '断线自动恢复');
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      SharedPrefsService.instance.getBool('auto_reconnect_on_disconnect'),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      const MaterialApp(home: BluetoothConnectionSettings()),
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });
  testWidgets(
    'repair mode defaults on, user can disable it and confirm re-enabling',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SharedPrefsService.instance.init();
      await SharedPrefsService.instance.reload();
      await tester.pumpWidget(
        const MaterialApp(home: BluetoothConnectionSettings()),
      );
      expect(find.text('重建系统配对'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '连接前重建系统配对'),
            )
            .value,
        true,
      );
      await tester.tap(find.widgetWithText(SwitchListTile, '连接前重建系统配对'));
      await tester.pumpAndSettle();
      expect(
        SharedPrefsService.instance.getBool(androidRebuildBondSettingKey),
        isFalse,
      );
      await tester.tap(find.widgetWithText(SwitchListTile, '连接前重建系统配对'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        SharedPrefsService.instance.getBool(androidRebuildBondSettingKey),
        isNot(true),
      );
      await tester.tap(find.widgetWithText(SwitchListTile, '连接前重建系统配对'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('启用兼容方式'));
      await tester.pumpAndSettle();
      expect(
        SharedPrefsService.instance.getBool(androidRebuildBondSettingKey),
        true,
      );
      await tester.tap(find.widgetWithText(SwitchListTile, '连接前重建系统配对'));
      await tester.pumpAndSettle();
      expect(
        SharedPrefsService.instance.getBool(androidRebuildBondSettingKey),
        false,
      );
    },
  );
}
