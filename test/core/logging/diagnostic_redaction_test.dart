import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/core/logging/diagnostic_event.dart';
import 'package:oronbox/src/core/logging/diagnostic_redaction.dart';
import 'package:oronbox/src/core/logging/logging_service.dart';

void main() {
  test('redacts nested secrets, text credentials and exported diagnostics', () {
    final event = DiagnosticEvent(
      time: DateTime(2026),
      level: Level.WARNING,
      source: 'test',
      process: DiagnosticProcess.frontend,
      message: 'encryptKey=fixture-key-value password="two secret words"',
      error: 'Authorization: Bearer fixture-bearer\nCookie: fixture-cookie',
      fields: {
        'request': {
          'access_token': 'fixture-token',
          'deviceKey': 'fixture-device-key',
        },
        'status': 403,
      },
    );
    publishDiagnostic(event);
    for (final output in [
      event.format(),
      jsonEncode(event.toJson()),
      recentOronBoxDiagnostics.last.fields.toString(),
    ]) {
      expect(output, isNot(contains('fixture-')));
      expect(output, isNot(contains('two secret words')));
      expect(output, contains('403'));
    }
    expect(recentOronBoxDiagnostics.last.message, isNot(contains('fixture-')));
    expect(event.redacted().redacted().format(), event.redacted().format());
    expect(
      redactDiagnosticText('https://example.invalid/?token=fixture-query&ok=1'),
      isNot(contains('fixture-query')),
    );
    expect(
      redactDiagnosticText('Bearer fixture-standalone'),
      isNot(contains('fixture-standalone')),
    );
    for (final name in [
      'accessToken',
      'refresh_token',
      'apiKey',
      'clientSecret',
      'device_key',
    ]) {
      expect(
        redactDiagnosticText('$name=fixture-value'),
        isNot(contains('fixture-value')),
      );
      expect(
        jsonEncode(redactDiagnosticValue({name: 'fixture-value'})),
        isNot(contains('fixture-value')),
      );
    }
  });

  test(
    'keeps useful errors and bounds deep or oversized diagnostic fields',
    () {
      expect(redactDiagnosticText('连接超时：HTTP 403'), '连接超时：HTTP 403');
      expect(redactDiagnosticText('x' * 20000).length, lessThan(17000));
      Object nested = 'value';
      for (var i = 0; i < 20; i++) {
        nested = {'nested': nested};
      }
      expect(
        jsonEncode(redactDiagnosticValue(nested)),
        contains('[truncated]'),
      );
    },
  );
}
