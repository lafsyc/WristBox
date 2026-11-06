import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'cloud_store.dart';

class AdminApi {
  AdminApi(this.dio);
  final Dio dio;
  late final CloudStore store = CloudStore(dio);
  static Future<AdminApi> connect() async {
    if (!Platform.isWindows) throw StateError('管理后台仅在电脑端开放');
    final store = await CloudStore.connect(requireAccount: true);
    if (!await store.isAdmin()) throw StateError('请使用管理员邮箱账号登录');
    return AdminApi(store.dio);
  }

  static Future<AdminApi> connectAnnouncements() async {
    final store = await CloudStore.connect(requireAccount: true);
    try {
      if (!await store.isAdmin()) throw StateError('请使用管理员邮箱账号登录');
      return AdminApi(store.dio);
    } catch (_) {
      store.dio.close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    final response = await dio.get<dynamic>(
      'v1/admin/$path',
      queryParameters: query,
    );
    return (response.data as Map).cast<String, dynamic>();
  }

  Future<void> change(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    await dio.request<dynamic>(
      'v1/admin/$path',
      data: body,
      options: Options(method: method),
    );
  }

  Future<Uint8List> export(String kind, Map<String, dynamic> query) async {
    final response = await dio.get<List<int>>(
      'v1/admin/export/$kind',
      queryParameters: query,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  Future<void> publish(String id, bool value) =>
      CloudStore(dio).publish(id, value);
  Future<Map<String, dynamic>> upload(
    String path,
    void Function(double) progress, {
    Map<String, dynamic>? binaryMetadata,
  }) => store.upload(path, progress, binaryMetadata: binaryMetadata);
}
