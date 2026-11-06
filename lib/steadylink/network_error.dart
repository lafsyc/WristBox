import 'dart:io';

import 'package:dio/dio.dart';

/// User-facing diagnostics without exposing URLs, request bodies or credentials.
String networkErrorMessage(DioException error) {
  if (error.type == DioExceptionType.badCertificate) {
    return '服务器证书校验失败，已停止连接，请联系管理员';
  }
  if (error.error is HandshakeException || error.error is TlsException) {
    return '安全连接建立失败，可能是网络拦截或服务证书异常，请稍后重试或联系管理员';
  }
  return switch (error.type) {
    DioExceptionType.connectionTimeout => '连接服务器超时，请检查网络后重试',
    DioExceptionType.sendTimeout => '上传超时，请检查网络和操作记录后再试',
    DioExceptionType.receiveTimeout => '等待服务器响应超时，请刷新确认操作结果后再试',
    DioExceptionType.cancel => '操作已取消',
    DioExceptionType.connectionError => '无法连接服务器，请检查网络或代理设置后重试',
    _ => '请求未完成，请刷新确认操作结果后再试',
  };
}
