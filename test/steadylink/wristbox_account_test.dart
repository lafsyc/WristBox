import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/wristbox_account.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  String nickname = '小腕';
  String? avatar;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.endsWith('/profile')) {
      nickname = (options.data as Map)['nickname'] as String;
    }
    if (options.path.endsWith('/avatar')) {
      if (options.method == 'DELETE') {
        avatar = null;
      } else {
        final bytes = await requestStream!.expand((chunk) => chunk).toList();
        expect(bytes, [1, 2, 3]);
        avatar = base64Encode(bytes);
      }
    }
    final response =
        options.path.endsWith('/logout') || options.path.endsWith('/code')
        ? {'ok': true}
        : {
            'token': 'test-session-token',
            'user': {
              'email': 'test@example.com',
              'role': 'user',
              'id': 10000,
              'nickname': nickname,
              'avatar': avatar,
            },
          };
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('requires HTTPS, sends correct account requests and stores token only in secure storage', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPrefsService.instance;
    await prefs.init();
    var vault = <String, dynamic>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('steadylink/credentials'),
          (call) async {
            if (call.method == 'read') return jsonEncode(vault);
            vault = (jsonDecode(call.arguments as String) as Map)
                .cast<String, dynamic>();
            return null;
          },
        );
    await prefs.initializeSecureStorage();
    final adapter = FakeAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final bad = WristBoxAccountService(dio: dio, baseUrl: 'http://example.com');
    await expectLater(
      bad.sendCode('test@example.com', false),
      throwsA(isA<StateError>()),
    );
    expect(adapter.requests, isEmpty);
    final defaultApi = WristBoxAccountService(dio: dio);
    await defaultApi.sendCode('test@example.com', false);
    expect(adapter.requests.last.uri.host, 'api.example.invalid');
    expect(adapter.requests.last.uri.path, '/wristbox-accounts/v1/auth/code');
    final api = WristBoxAccountService(
      dio: dio,
      baseUrl: 'https://example.com/auth',
    );
    await api.sendCode('test@example.com', true);
    expect(adapter.requests.last.uri.path, '/auth/v1/auth/code');
    expect(adapter.requests.last.data, {
      'email': 'test@example.com',
      'purpose': 'register',
    });
    final session = await api.authenticate(
      'test@example.com',
      '123456',
      register: true,
      useCode: true,
      password: 'test-password-123',
    );
    expect(session.email, 'test@example.com');
    expect(vault['wristbox.account.session'], isNotNull);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'wristbox.account.session',
      ),
      isFalse,
    );
    expect(api.stored()?.token, session.token);
    expect(adapter.requests.last.data, {
      'email': 'test@example.com',
      'code': '123456',
      'password': 'test-password-123',
    });
    expect(session.id, 10000);
    final renamed = await api.updateProfile(session, '新昵称');
    expect(renamed.nickname, '新昵称');
    expect(api.stored()?.nickname, '新昵称');
    expect(adapter.requests.last.method, 'PATCH');
    expect(
      adapter.requests.last.headers['Authorization'],
      'Bearer test-session-token',
    );
    final withAvatar = await api.updateAvatar(
      renamed,
      Uint8List.fromList([1, 2, 3]),
    );
    expect(withAvatar.avatar, base64Encode([1, 2, 3]));
    expect((await api.refresh(withAvatar)).id, 10000);
    expect((await api.updateAvatar(withAvatar, null)).avatar, isNull);
    await api.logout(session);
    expect(
      adapter.requests.last.headers['Authorization'],
      'Bearer test-session-token',
    );
    expect(api.stored(), isNull);
    expect(vault.containsKey('wristbox.account.session'), isFalse);
    await api.refresh(session);
    expect(
      api.stored(),
      isNull,
      reason: 'late refresh cannot restore a logged-out session',
    );
  });
}
