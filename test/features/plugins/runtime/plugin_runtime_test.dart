import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/features/plugins/runtime/plugin_runtime.dart';
import 'package:oronbox/src/features/plugins/runtime/plugin_runtime_quickjs.dart';

void main() {
  test('interconnect send forwards the optional device id', () {
    expect(
      oronBoxPluginBootstrap,
      contains("host('interconnect.send', [packageName, data, deviceId])"),
    );
  });

  test('host calls use request IDs instead of returning Dart futures', () {
    expect(oronBoxPluginBootstrap, contains('nextHostRequest'));
    expect(oronBoxPluginBootstrap, contains('__zbSettleHostRequest'));
    expect(oronBoxPluginBootstrap, contains('__zbBeginOperation'));
    expect(oronBoxPluginBootstrap, contains('__zbPollOperation'));
  });

  test('unencodable host results reject the pending JavaScript request', () {
    final settlement = encodeQuickJsHostSettlement(true, Object());

    expect(settlement.succeeded, isFalse);
    expect(settlement.encodedPayload, contains('serialization failed'));
  });
}
