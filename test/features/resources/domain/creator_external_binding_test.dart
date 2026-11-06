import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/features/resources/domain/creator_external_binding.dart';

void main() {
  test('reads canonical and historical BandBBS bindings', () {
    final canonical = parseCreatorBandBbsBinding('{"12":"345"}');
    expect(canonical.single.categoryId, '12');
    expect(canonical.single.resourceId, '345');

    final historical = parseCreatorBandBbsBinding(
      '{"13":{"resource_id":"678","url":"https://example.com/678"}}',
    );
    expect(historical.single.categoryId, '13');
    expect(historical.single.resourceId, '678');
    expect(historical.single.url, 'https://example.com/678');
  });
}
