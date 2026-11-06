import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('credentials use native storage, serialize writes, and survive a failed write', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPrefsService.instance;
    await prefs.init();
    var stored = <String, dynamic>{};
    var failWrite = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('steadylink/credentials'),
          (call) async {
            if (call.method == 'read') return jsonEncode(stored);
            if (failWrite) throw PlatformException(code: 'storage');
            await Future<void>.delayed(const Duration(milliseconds: 2));
            stored =
                jsonDecode(call.arguments as String) as Map<String, dynamic>;
            return null;
          },
        );
    await prefs.initializeSecureStorage();
    await Future.wait([
      prefs.setStringList('paired_devices', ['test-device']),
      prefs.setString('mi.account.token', 'test-token'),
    ]);
    expect(stored['paired_devices'], ['test-device']);
    expect(stored['mi.account.token'], 'test-token');
    final plain = await SharedPreferences.getInstance();
    expect(plain.containsKey('paired_devices'), isFalse);
    expect(plain.containsKey('mi.account.token'), isFalse);
    failWrite = true;
    await expectLater(
      prefs.setString('mi.account.token', 'lost'),
      throwsA(isA<PlatformException>()),
    );
    expect(prefs.getString('mi.account.token'), 'test-token');
    failWrite = false;
    await prefs.remove('mi.account.token');
    expect(stored.containsKey('mi.account.token'), isFalse);
    expect(prefs.getStringList('paired_devices'), ['test-device']);
  });
}
