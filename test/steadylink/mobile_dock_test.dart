import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/mobile_dock.dart';

void main() {
  testWidgets(
    'dock fits small screens, respects safe area and exposes navigation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      var deviceTaps = 0;
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                padding: EdgeInsets.only(bottom: 34),
                viewPadding: EdgeInsets.only(bottom: 34),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  extendBody: true,
                  body: const SizedBox.expand(),
                  bottomNavigationBar: MobileDock(
                    selectedIndex: selected,
                    onSelected: (value) => setState(() => selected = value),
                    connected: false,
                    connecting: true,
                    onInstallPressed: () => deviceTaps++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final device = find.byKey(const ValueKey('mobile-quick-install'));
        expect(tester.getBottomRight(device).dy, lessThanOrEqualTo(606));
        await tester.tap(find.byKey(const ValueKey('mobile-tab-3')));
        await tester.pumpAndSettle();
        expect(selected, 3);
        await tester.tap(device);
        await tester.pumpAndSettle();
        expect(find.text('连接中'), findsOneWidget);
        expect(find.text('已连接'), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      }
      expect(deviceTaps, 2);
    },
  );
}
