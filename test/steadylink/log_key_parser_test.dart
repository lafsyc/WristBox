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
}
