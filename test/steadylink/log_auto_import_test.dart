import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/log_import_page.dart';

void main() {
  const channel = MethodChannel('wristbox/log_import');
  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LogImportPage())),
    );
  }

  testWidgets(
    'automatic scan asks for folder access without opening a file picker',
    (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'scanLatest') {
              throw PlatformException(
                code: 'LOG_FOLDER_REQUIRED',
                message: '首次自动读取需要授权日志文件夹',
              );
            }
            return false;
          });
      await show(tester);
      await tester.scrollUntilVisible(find.text('自动读取最新日志'), 200);
      await tester.tap(find.text('自动读取最新日志'));
      await tester.pumpAndSettle();
      expect(calls, ['scanLatest']);
      await tester.scrollUntilVisible(find.text('首次自动读取需要授权日志文件夹'), 200);
      expect(find.text('首次自动读取需要授权日志文件夹'), findsOneWidget);
      await tester.ensureVisible(find.text('授权日志文件夹'));
      await tester.tap(find.text('授权日志文件夹'));
      await tester.pumpAndSettle();
      expect(calls, ['scanLatest', 'grantFolder']);
    },
  );
  testWidgets(
    'return from health triggers one fresh-only scan; unrelated resume does not',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'scanLatest') {
              throw PlatformException(code: 'NO_LOG', message: '未发现本次新日志');
            }
            return null;
          });
      await show(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.scrollUntilVisible(find.text('打开运动健康，返回后自动读取'), 200);
      await tester.tap(find.text('打开运动健康，返回后自动读取'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['openHealth', 'scanLatest']);
      expect((calls.last.arguments as Map)['notBefore'], greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
    },
  );
}
