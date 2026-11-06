import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/cloud_store.dart';
import 'package:oronbox/steadylink/network_error.dart';

void main() {
  DioException failure(DioExceptionType type, {Object? cause, int? status}) {
    final request = RequestOptions(path: '/private');
    return DioException(
      requestOptions: request,
      type: type,
      error: cause,
      response: status == null
          ? null
          : Response(requestOptions: request, statusCode: status),
    );
  }

  test(
    'TLS failures and certificates are distinguished without exposing details',
    () {
      final error = failure(
        DioExceptionType.unknown,
        cause: const HandshakeException('secret-token'),
      );
      expect(networkErrorMessage(error), contains('安全连接建立失败'));
      expect(cloudError(error), isNot(contains('secret-token')));
      expect(
        cloudError(failure(DioExceptionType.badCertificate)),
        contains('证书校验失败'),
      );
    },
  );

  test('timeouts do not encourage blindly repeating a potentially completed mutation', () {
    expect(
      cloudError(failure(DioExceptionType.receiveTimeout)),
      contains('确认操作结果'),
    );
    expect(cloudError(failure(DioExceptionType.sendTimeout)), contains('操作记录'));
    expect(
      cloudError(failure(DioExceptionType.connectionTimeout)),
      contains('连接服务器超时'),
    );
    expect(cloudError(failure(DioExceptionType.cancel)), '操作已取消');
  });

  test('HTTP outages and permission failures are not reported as network interruptions', () {
    expect(
      cloudError(failure(DioExceptionType.badResponse, status: 502)),
      contains('服务器暂时不可用'),
    );
    expect(
      cloudError(failure(DioExceptionType.badResponse, status: 401)),
      contains('重新登录'),
    );
    expect(
      cloudError(failure(DioExceptionType.connectionError)),
      contains('代理设置'),
    );
  });
}
