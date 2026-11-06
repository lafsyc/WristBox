import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/steadylink/log_import_page.dart';
import 'package:oronbox/steadylink/log_key_parser.dart';

const sampleKey = '0123456789abcdef0123456789abcdef';
const candidate = LogKeyCandidate(key: sampleKey, source: 'log', line: 1);

void main() {
  testWidgets(
    'unknown key requires explicit target; selected device metadata survives',
    (tester) async {
      MiWearState? saved;
      final first = MiWearState(
        name: '手环甲',
        addr: 'AA:BB:CC:DD:EE:01',
        connectType: 'spp',
        codename: 'n67',
        authkey: 'a' * 32,
      );
      final second = MiWearState(
        name: '手环乙',
        addr: 'AA:BB:CC:DD:EE:02',
        connectType: 'spp',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await showDialog<MiWearState>(
                    context: context,
                    builder: (_) => LogKeyTargetDialog(
                      candidate: candidate,
                      devices: [first, second],
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认保存'));
      await tester.pumpAndSettle();
      expect(find.text('请明确选择目标设备'), findsOneWidget);
      expect(saved, isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手环甲 · AA:BB:CC:DD:EE:01').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认保存'));
      await tester.pumpAndSettle();
      expect(saved!.authkey, sampleKey);
      expect(saved!.addr, first.addr);
      expect(saved!.name, first.name);
      expect(saved!.codename, first.codename);
      expect(first.authkey, 'a' * 32);
      expect(second.authkey, isNot(sampleKey));
    },
  );

  testWidgets('known log address rejects selecting a different device', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LogKeyTargetDialog(
            candidate: const LogKeyCandidate(
              key: sampleKey,
              source: 'log',
              line: 1,
              address: 'AA:BB:CC:DD:EE:01',
            ),
            devices: [
              MiWearState(
                name: '其他设备',
                addr: 'AA:BB:CC:DD:EE:02',
                connectType: 'spp',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('其他设备 · AA:BB:CC:DD:EE:02').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认保存'));
    await tester.pumpAndSettle();
    expect(find.text('日志地址与此设备不同，请选择正确的设备'), findsOneWidget);
  });

  testWidgets('local picker cancel preserves tutorial and has no error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var picks = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LogImportPage(
            pickLog: () async {
              picks++;
              return null;
            },
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('手动选择日志（备用）'), 200);
    await tester.tap(find.text('手动选择日志（备用）'));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(find.text('操作教程'), findsOneWidget);
    expect(find.textContaining('识别到'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
