import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/steadylink/client_updates.dart';
import 'package:oronbox/steadylink/operation_queue.dart';

Map<String, dynamic> state({bool force = false, bool release = true}) => {
  'mandatory': force,
  'minimumBuild': force ? clientBuild + 1 : 0,
  'release': release
      ? {
          'build': clientBuild + 1,
          'version': '0.9.1',
          'title': '新版本测试',
          'notes': '改进连接稳定性',
          'packageId': 'a' * 32,
          'size': 12,
          'sha256': 'a' * 64,
        }
      : null,
  'announcements': [
    {'id': 'notice', 'revision': 1, 'title': '公告测试', 'body': '欢迎使用'},
  ],
};

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.instance.init();
  });
  setUp(() async {
    for (final key in [
      'client.update.cache',
      'client.update.dismissed',
      'client.notice.notice:1',
    ]) {
      await SharedPrefsService.instance.remove(key);
    }
  });
  test('release version matches both platform build inputs', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: $clientVersion+$clientBuild'),
    );
  });
  test('hash and length reject corrupt downloads', () async {
    final dir = await Directory.systemTemp.createTemp('wristbox-update-test');
    try {
      final file = File('${dir.path}/package');
      await file.writeAsBytes([1, 2, 3]);
      final hash = sha256.convert([1, 2, 3]).toString();
      expect(await verifyUpdate(file, 3, hash), true);
      expect(await verifyUpdate(file, 4, hash), false);
      await file.writeAsBytes([1, 2, 4]);
      expect(await verifyUpdate(file, 3, hash), false);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  testWidgets('optional can be postponed and notice is read once', (
    tester,
  ) async {
    final queue = OperationQueue(
      connect: (_) async {},
      install: (_, _) async {},
    );
    final host = GlobalKey<ClientReleaseHostState>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (_, child) => ClientReleaseHost(
            key: host,
            queue: queue,
            fetchStatus: () async => state(),
            child: child!,
          ),
          home: const Scaffold(body: Text('工具主页')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新版本测试'), findsOneWidget);
    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();
    expect(find.text('公告测试'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await host.currentState!.check();
    await tester.pumpAndSettle();
    expect(find.text('公告测试'), findsNothing);
    expect(find.text('新版本测试'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    queue.dispose();
  });
  testWidgets(
    'forced cached update survives network failure and withdrawal unlocks',
    (tester) async {
      await SharedPrefsService.instance.setString(
        'client.update.cache',
        jsonEncode(state(force: true)),
      );
      await SharedPrefsService.instance.setInt(
        'client.update.dismissed',
        clientBuild + 1,
      );
      var offline = true;
      final queue = OperationQueue(
        connect: (_) async {},
        install: (_, _) async {},
      );
      final host = GlobalKey<ClientReleaseHostState>();
      var taps = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (_, child) => ClientReleaseHost(
              key: host,
              queue: queue,
              fetchStatus: () async {
                if (offline) throw StateError('离线');
                return {
                  'release': null,
                  'mandatory': false,
                  'announcements': [],
                };
              },
              child: child!,
            ),
            home: Scaffold(
              body: TextButton(
                onPressed: () => taps++,
                child: const Text('工具操作'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('稍后再说'), findsNothing);
      expect(find.text('新版本测试'), findsOneWidget);
      await tester.tap(find.text('工具操作'), warnIfMissed: false);
      expect(taps, 0);
      offline = false;
      await host.currentState!.check();
      await tester.pumpAndSettle();
      expect(find.text('新版本测试'), findsNothing);
      await tester.tap(find.text('工具操作'));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
      queue.dispose();
    },
  );
  testWidgets('waits for wearable transfer before showing update', (
    tester,
  ) async {
    final pending = Completer<void>();
    final queue = OperationQueue(
      connect: (_) async {},
      install: (_, _) async {},
    );
    final operation = queue.maintain(() => pending.future);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (_, child) => ClientReleaseHost(
            queue: queue,
            fetchStatus: () async => state(force: true),
            child: child!,
          ),
          home: const Scaffold(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新版本测试'), findsNothing);
    pending.complete();
    await operation;
    await tester.pumpAndSettle();
    expect(find.text('新版本测试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    queue.dispose();
  });
}
