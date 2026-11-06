import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/store_models.dart';

void main() {
  Map<String, dynamic> variant(
    String id,
    int code,
    Map<String, dynamic> rule,
  ) => {
    'id': id,
    'versionCode': code,
    'supportedModels': ['n67'],
    'firmwareRules': [
      {'model': 'n67', ...rule},
    ],
  };
  test('numeric ranges, unknown firmware and latest compatible fallback', () {
    final old = variant('old', 1, {
      'mode': 'range',
      'minVersion': '1.9',
      'maxVersion': '1.10.2',
    });
    final next = variant('next', 2, {
      'mode': 'exact',
      'versions': ['2.0.1'],
    });
    final app = StoreApp('one', [old, next]);
    expect(app.forDevice('n67', '1.10')?['id'], 'old');
    expect(app.forDevice('n67', '1.9.0')?['id'], 'old');
    expect(app.forDevice('n67', '2.0.1')?['id'], 'next');
    for (final firmware in ['', 'unknown', '1.8.99', '1.10.3', '2.0.2']) {
      expect(app.forDevice('n67', firmware), isNull, reason: firmware);
    }
    expect(app.forDevice('o66', '2.0.1'), isNull);
    expect(firmwareSummary(next), contains('2.0.1'));
    expect(firmwareMismatch(next, 'n67', ''), contains('刷新设备信息'));
  });
  test('legacy and explicit unrestricted resources remain available', () {
    final legacy = {
      'id': 'legacy',
      'versionCode': 1,
      'supportedModels': ['n67'],
    };
    expect(StoreApp('legacy', [legacy]).forDevice('n67', '')?['id'], 'legacy');
    final unrestricted = variant('any', 2, {'mode': 'any'});
    expect(StoreApp('any', [unrestricted]).forDevice('n67', '')?['id'], 'any');
  });
}
