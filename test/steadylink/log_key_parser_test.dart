import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/log_key_parser.dart';

const keyA = '0123456789abcdef0123456789abcdef';
const keyB = 'abcdef0123456789abcdef0123456789';
List<LogKeyCandidate> parse(List<String> lines) => parseLogKeyRecords([
  for (var i = 0; i < lines.length; i++)
    {'text': lines[i], 'source': 'XiaomiFit.main.log', 'line': i + 1},
]);

void main() {
  test('multiple devices retain only metadata in their own JSON object', () {
    final items = parse([
      'prefix [INFO] ${jsonEncode({
        'devices': [
          {'encryptKey': keyA, 'productName': '手环甲', 'model': 'n67', 'mac': 'AA-BB-CC-DD-EE-01'},
          {'encryptKey': keyB, 'productName': '手环乙', 'model': 'o66', 'mac': 'AA:BB:CC:DD:EE:02'},
        ],
      })}',
    ]);
    expect(items.length, 2);
    expect(items[0].name, '手环甲');
    expect(items[0].address, 'AA:BB:CC:DD:EE:01');
    expect(items[1].name, '手环乙');
    expect(items[1].key, keyB);
    expect(items[1].model, 'o66');
  });
  test('nearby or parent metadata cannot label an unassigned key', () {
    final items = parse([
      '{"productName":"错误设备","mac":"AA:BB:CC:DD:EE:01"}',
      'encryptKey=$keyA',
      '{"productName":"另一个设备","payload":{"encryptKey":"$keyB"}}',
    ]);
    expect(items, hasLength(2));
    for (final item in items) {
      expect(item.name, isEmpty);
      expect(item.address, isEmpty);
    }
  });
  test('legacy, escaped and nested JSON formats remain supported', () {
    expect(parse(['deviceKey=prefix:$keyA']).single.key, keyA);
    expect(parse([r'\"encryptKey\":\"' + keyB + r'\"']).single.key, keyB);
    final nested = jsonEncode({
      'payload': jsonEncode({'encryptKey': keyA, 'productName': '日志设备'}),
    });
    expect(parse([nested]).single.name, '日志设备');
  });
  test('invalid, zero and overlong key tokens are rejected', () {
    expect(
      parse([
        'encryptKey=${'0' * 32}',
        'encryptKey=${'z' * 32}',
        'encryptKey=${keyA}0',
        'encryptKey=${keyA.substring(1)}',
      ]),
      isEmpty,
    );
  });
  test('deduplication preserves distinct addresses and historical keys', () {
    final line =
        '{"encryptKey":"$keyA","productName":"设备","mac":"AA:BB:CC:DD:EE:01"}';
    final items = parse([
      line,
      line,
      '{"encryptKey":"$keyB","mac":"AA:BB:CC:DD:EE:01"}',
      '{"encryptKey":"$keyA","mac":"AA:BB:CC:DD:EE:02"}',
    ]);
    expect(items, hasLength(3));
    expect(items.first.name, '设备');
    expect(items.first.hint, isNot(contains(keyA)));
    expect(items.first.toString(), isNot(contains(keyA)));
  });
  test('bounded input rejects excessive lines and oversized content', () {
    expect(
      () => parse(List.filled(513, 'encryptKey=$keyA')),
      throwsFormatException,
    );
    expect(() => parse(['x' * (128 * 1024 + 1)]), throwsFormatException);
    expect(() => parse(List.filled(20, 'x' * 120000)), throwsFormatException);
  });
  test('long-line windows recover keys without guessing device metadata', () {
    final items = parseLogKeyRecords([
      {
        'text':
            '{"encryptKey":"$keyA","productName":"Untrusted","mac":"AA:BB:CC:DD:EE:01"}',
        'truncatedEnd': true,
      },
      {'text': 'prefix encryptKey=$keyA ', 'truncatedStart': true},
      {'text': 'prefix deviceKey=legacy:$keyB', 'truncatedStart': true},
    ]);
    expect(items.map((item) => item.key), [keyA, keyB]);
    expect(
      items.every((item) => item.name.isEmpty && item.address.isEmpty),
      isTrue,
    );
  });
  test('cut tokens are ignored until an overlapping window completes them', () {
    expect(
      parseLogKeyRecords([
        {'text': 'prefix encryptKey=$keyA', 'truncatedEnd': true},
        {'text': 'prefix encryptKey=${keyA}0 ', 'truncatedStart': true},
        {'text': 'encryptKey=$keyB ', 'truncatedStart': true},
      ]),
      isEmpty,
    );
    expect(
      parseLogKeyRecords([
        {'text': 'encryptKey=$keyA ', 'truncatedEnd': true},
        {'text': 'prefix encryptKey=$keyA ', 'truncatedStart': true},
      ]).single.key,
      keyA,
    );
  });
  test(
    'separate records associate only through an unambiguous explicit ID',
    () {
      final items = parse([
        jsonEncode({'did': 'device-1', 'encryptKey': keyA}),
        jsonEncode({
          'did': 'device-1',
          'mac_address': 'aabbccddee01',
          'name': '我的手环',
          'model': 'n67',
        }),
        jsonEncode({
          'did': 'device-2',
          'mac': 'AA:BB:CC:DD:EE:02',
          'name': '不能错配',
        }),
      ]);
      expect(items.single.address, 'AA:BB:CC:DD:EE:01');
      expect(items.single.name, '我的手环');
      expect(items.single.model, 'n67');
    },
  );
  test('conflicting ID mappings remain unassigned, even across files', () {
    final items = parse([
      jsonEncode({'deviceId': 'same-id', 'encryptKey': keyA}),
      jsonEncode({'deviceId': 'same-id', 'mac': 'AA:BB:CC:DD:EE:01'}),
      jsonEncode({'device_id': 'same-id', 'mac': 'AA:BB:CC:DD:EE:02'}),
    ]);
    expect(items.single.address, isEmpty);
  });
  test(
    'known cloud device schema supports nested detail and product metadata',
    () {
      final items = parse([
        jsonEncode({
          'deviceInfo': {
            'device': {
              'name': '我的9Pro',
              'product': {'model': 'n67'},
              'detail': {'mac': 'AA:BB:CC:DD:EE:01', 'encrypt_key': keyA},
            },
          },
        }),
      ]);
      expect(items, hasLength(1));
      expect(items.single.name, '我的9Pro');
      expect(items.single.model, 'n67');
      expect(items.single.address, 'AA:BB:CC:DD:EE:01');
    },
  );
  test('complete native object supersedes long-line key-only windows', () {
    final object = jsonEncode({
      'mac': 'AA:BB:CC:DD:EE:01',
      'encryptKey': keyA,
      'model': 'n67',
    });
    final items = parseLogKeyRecords([
      {'text': object, 'truncatedStart': true},
      {'text': object, 'source': 'XiaomiFit.device.log', 'line': 10},
    ]);
    expect(items, hasLength(1));
    expect(items.single.address, 'AA:BB:CC:DD:EE:01');
  });
  test(
    'device grouping preserves multiple historical keys and separate devices',
    () {
      final groups = groupLogDevices(
        parse([
          jsonEncode({'mac': 'AA:BB:CC:DD:EE:01', 'encryptKey': keyA}),
          jsonEncode({'mac': 'AA:BB:CC:DD:EE:01', 'encryptKey': keyB}),
          jsonEncode({'mac': 'AA:BB:CC:DD:EE:02', 'encryptKey': keyA}),
        ]),
      );
      expect(groups, hasLength(2));
      expect(groups.first.candidates.map((c) => c.key), [keyA, keyB]);
      expect(groups.last.candidates.single.address, 'AA:BB:CC:DD:EE:02');
    },
  );
  test('a known Key does not hide an explicit conflicting ID record', () {
    final items = parse([
      jsonEncode({'did': 'conflict', 'encryptKey': keyA}),
      jsonEncode({
        'did': 'conflict',
        'mac': 'AA:BB:CC:DD:EE:01',
        'encryptKey': keyA,
      }),
      jsonEncode({'did': 'conflict', 'mac': 'AA:BB:CC:DD:EE:02'}),
    ]);
    expect(items, hasLength(2));
    expect(items.any((c) => c.address.isEmpty), isTrue);
  });
  test('native fallback recovers keys without treating rejected JSON as device metadata', () {
    final object = jsonEncode({
      'encryptKey': keyA,
      'mac': 'AA:BB:CC:DD:EE:01',
      'name': 'not trusted',
    });
    final unassigned = parseLogKeyRecords([
      {'text': object, 'metadataAllowed': false},
    ]);
    expect(unassigned.single.key, keyA);
    expect(unassigned.single.address, isEmpty);
    expect(unassigned.single.name, isEmpty);
    final recovered = parseLogKeyRecords([
      {'text': object, 'metadataAllowed': false},
      {'text': object, 'metadataAllowed': true},
    ]);
    expect(recovered, hasLength(1));
    expect(recovered.single.address, 'AA:BB:CC:DD:EE:01');
  });
  test('redacted address resolves from the local log address pool', () {
    final items = parseLogKeyRecords([
      {
        'text': jsonEncode({
          'mac': '**:**:**:DD:EE:01',
          'encrypt_key': keyA,
          'model': 'n67',
        }),
        'addressCandidates': ['AA:BB:CC:DD:EE:01'],
        'addressPoolComplete': true,
      },
    ]);
    expect(items.single.address, 'AA:BB:CC:DD:EE:01');
    expect(items.single.addressInferred, isTrue);
  });
  test('short suffix resolves against paired devices, while a collision remains selectable', () {
    final c = parse([
      jsonEncode({'mac': 'EE:01', 'encryptKey': keyA}),
    ]).single;
    expect(c.addressSuffix, 'EE01');
    final inferred = resolveLogAddress(c, ['AA:BB:CC:DD:EE:01']);
    expect(inferred.address, 'AA:BB:CC:DD:EE:01');
    final conflict = resolveLogAddress(inferred, ['11:22:33:44:EE:01']);
    expect(conflict.address, isEmpty);
    expect(logAddressMatches(conflict, 'AA:BB:CC:DD:EE:02'), isFalse);
  });
  test('incomplete address pool disables automatic suffix resolution', () {
    final items = parseLogKeyRecords([
      {
        'text': jsonEncode({'mac': 'DD:EE:01', 'encryptKey': keyA}),
        'addressCandidates': ['AA:BB:CC:DD:EE:01'],
        'addressPoolComplete': false,
      },
    ]);
    expect(
      resolveLogAddress(items.single, ['AA:BB:CC:DD:EE:01']).address,
      isEmpty,
    );
  });
}
