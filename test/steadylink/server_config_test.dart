import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/server_config.dart';
import 'package:oronbox/steadylink/wristbox_account.dart';

void main() {
  test(
    'no deployment config rejects cloud use before opening a connection',
    () async {
      if (wristBoxAuthUrl.isNotEmpty) return;
      final dio = Dio();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );
      await expectLater(
        WristBoxAccountService(dio: dio).publicClient(),
        throwsA(isA<StateError>()),
      );
      expect(requests, 0);
      dio.close();
    },
  );

  test(
    'bundled CA is opt-in and restricted to the configured HTTPS origin',
    () {
      const configured = 'https://store.example.test:9443/wristbox-accounts';
      bool trusts(String url, {bool enabled = true}) =>
          shouldUseBundledCa(url, configuredBase: configured, enabled: enabled);
      expect(trusts(configured), isTrue);
      expect(trusts('https://store.example.test:9443/another-path'), isTrue);
      expect(trusts(configured, enabled: false), isFalse);
      for (final url in [
        'http://store.example.test:9443/wristbox-accounts',
        'https://store.example.test/wristbox-accounts',
        'https://another.example.test:9443/wristbox-accounts',
        'https://user:pass@store.example.test:9443/wristbox-accounts',
        '$configured?token=example',
        '$configured#fragment',
        '',
      ]) {
        expect(trusts(url), isFalse, reason: url);
      }
      expect(
        shouldUseBundledCa(configured, configuredBase: '', enabled: true),
        isFalse,
      );
    },
  );
}
