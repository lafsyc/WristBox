import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/features/plugins/runtime/plugin_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles ZML and exposes the plugin attach contract', () async {
    final source = await rootBundle.loadString('assets/scripts/zeppos/zml.js');

    expect(source, contains('AppSideService('));
    expect(source, contains('request('));
    expect(source, contains('onRequest'));
    expect(oronBoxPluginBootstrap, contains('appside.zml.attach'));
    expect(oronBoxPluginBootstrap, contains('appside.zml.request'));
    expect(oronBoxPluginBootstrap, contains('appside.zml.call'));
    expect(oronBoxPluginBootstrap, contains('appside.zml.detach'));
  });
}
