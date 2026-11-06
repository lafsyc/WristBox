import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/steadylink/log_key_parser.dart';
import 'package:oronbox/steadylink/log_device_selection.dart';

const firstKey = '0123456789abcdef0123456789abcdef';
const secondKey = 'abcdef0123456789abcdef0123456789';
const device = MiWearState(
  name: '我的手环',
  addr: 'AA:BB:CC:DD:EE:01',
  connectType: 'spp',
  codename: 'n67',
);
LogKeyCandidate key(String value, {String suffix = '', String address = ''}) =>
    LogKeyCandidate(
      key: value,
      source: 'test',
      line: 1,
      addressSuffix: suffix,
      address: address,
    );
void main() {
  test(
    'unknown address uses the selected bonded device without typing a MAC',
    () {
      final choices = logDeviceChoices([key(firstKey)], [device]);
      expect(choices.single.device.addr, device.addr);
      expect(choices.single.device.name, device.name);
      expect(choices.single.candidates.single.key, firstKey);
    },
  );
  test(
    'suffix does not offer a contradictory device and exact match is preferred',
    () {
      final choices = logDeviceChoices(
        [key(firstKey, suffix: 'EE01'), key(secondKey, address: device.addr)],
        [device, device.copyWith(addr: 'AA:BB:CC:DD:EE:02')],
      );
      expect(choices.length, 1);
      expect(choices.single.candidates.first.key, secondKey);
    },
  );
  test('one selection verifies historical keys and retains only the successful result', () async {
    final saved = <String>[];
    var connects = 0, restores = 0;
    await verifyLogDeviceChoice(
      choice: LogDeviceChoice(device, [key(firstKey), key(secondKey)]),
      save: (d) async {
        saved.add(d.authkey!);
        expect(d.name, device.name);
      },
      connect: (_) async {
        if (++connects == 1) throw StateError('auth failed');
      },
      rollback: () async {
        restores++;
      },
      cancelled: () => false,
    );
    expect(saved, [firstKey, secondKey]);
    expect(connects, 2);
    expect(restores, 0);
  });
  test('permission failure stops retries and restores previous data', () async {
    var saves = 0, restores = 0;
    await expectLater(
      verifyLogDeviceChoice(
        choice: LogDeviceChoice(device, [key(firstKey), key(secondKey)]),
        save: (_) async {
          saves++;
        },
        connect: (_) async => throw StateError('permission denied'),
        rollback: () async {
          restores++;
        },
        cancelled: () => false,
      ),
      throwsStateError,
    );
    expect(saves, 1);
    expect(restores, 1);
  });
  test('cancel after saving rolls back without trying to connect', () async {
    var cancel = false, restores = 0, connects = 0;
    await expectLater(
      verifyLogDeviceChoice(
        choice: LogDeviceChoice(device, [key(firstKey)]),
        save: (_) async {
          cancel = true;
        },
        connect: (_) async {
          connects++;
        },
        rollback: () async {
          restores++;
        },
        cancelled: () => cancel,
      ),
      throwsA(isA<LogImportCancelled>()),
    );
    expect(connects, 0);
    expect(restores, 1);
  });
  test(
    'trial count is bounded and restoration failure is reported separately',
    () async {
      var connects = 0;
      await expectLater(
        verifyLogDeviceChoice(
          choice: LogDeviceChoice(device, [
            for (var i = 1; i <= 5; i++)
              key(i.toRadixString(16).padLeft(32, '0')),
          ]),
          save: (_) async {},
          connect: (_) async {
            connects++;
            throw StateError('auth failed');
          },
          rollback: () async => throw StateError('storage failed'),
          cancelled: () => false,
        ),
        throwsA(isA<LogImportRestoreFailed>()),
      );
      expect(connects, 3);
    },
  );
}
