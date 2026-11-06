import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:oronbox/src/protocols/xiaomi/transport/mass_payload_source.dart';

import 'wristbox_account.dart';
import 'network_error.dart';
import 'error_message.dart';

class CloudStore {
  CloudStore(this.dio);
  final Dio dio;
  final _images = <String, Future<Uint8List>>{};

  Future<Uint8List> media(String id) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
      return Future.error(StateError('图片标识无效'));
    }
    if (_images.containsKey(id)) return _images[id]!;
    if (_images.length >= 32) _images.remove(_images.keys.first);
    final future = dio
        .get<List<int>>(
          'v1/store/media/$id',
          options: Options(responseType: ResponseType.bytes),
        )
        .then((r) => Uint8List.fromList(r.data!));
    _images[id] = future;
    // Failed requests may be retried on the next page refresh.
    future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _images.remove(id);
      },
    );
    return future;
  }

  Future<String> uploadMedia(String path, String kind) async {
    final file = File(path);
    final length = await file.length();
    if (length < 1 || length > 4 * 1024 * 1024) {
      throw StateError('请选择不超过 4 MB 的图片');
    }
    final response = await dio.post<dynamic>(
      'v1/store/media',
      queryParameters: {'kind': kind},
      data: file.openRead(),
      options: Options(
        contentType: 'application/octet-stream',
        headers: {Headers.contentLengthHeader: length},
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    return response.data['id'] as String;
  }

  static Future<CloudStore> connect({bool requireAccount = false}) async {
    final service = WristBoxAccountService();
    if (requireAccount) {
      final session = service.stored();
      if (session == null) throw StateError('请先登录管理员邮箱账号');
      return CloudStore(await service.authenticatedClient(session));
    }
    final client = await service.publicClient();
    var expires = 0;
    Future<void> renew() async {
      final response = await client.post<dynamic>('v1/store/guest-session');
      client.options.headers['Authorization'] =
          'Bearer ${response.data['token']}';
      expires = (response.data['expires'] as num).toInt();
    }

    await renew();
    // A 401 is rejected before the operation runs. Refresh once; never replay a
    // download chunk under a different owner or replay ambiguous network errors.
    Future<void>? refreshing;
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          if (!request.path.endsWith('guest-session') &&
              !request.path.contains('/sessions/') &&
              expires - DateTime.now().millisecondsSinceEpoch ~/ 1000 < 1500) {
            try {
              await (refreshing ??= renew().whenComplete(
                () => refreshing = null,
              ));
              request.headers['Authorization'] =
                  client.options.headers['Authorization'];
            } catch (e) {
              handler.reject(DioException(requestOptions: request, error: e));
              return;
            }
          }
          handler.next(request);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          if (error.response?.statusCode != 401 ||
              request.extra['guestRetried'] == true ||
              request.path.endsWith('guest-session') ||
              request.path.contains('/sessions/')) {
            handler.next(error);
            return;
          }
          try {
            await (refreshing ??= renew().whenComplete(
              () => refreshing = null,
            ));
            request.headers['Authorization'] =
                client.options.headers['Authorization'];
            request.extra['guestRetried'] = true;
            handler.resolve(await client.fetch<dynamic>(request));
          } catch (_) {
            handler.next(error);
          }
        },
      ),
    );
    return CloudStore(client);
  }

  Future<Map<String, dynamic>> info() async {
    final response = await dio.get<dynamic>('v1/store/info');
    return (response.data as Map).cast<String, dynamic>();
  }

  Future<bool> isAdmin() async {
    final r = await dio.get<dynamic>('v1/auth/me');
    return r.data['user']['role'] == 'admin';
  }

  Future<List<Map<String, dynamic>>> catalog({bool manage = false}) async {
    final r = await dio.get<dynamic>(
      'v1/store/resources',
      queryParameters: {'manage': manage},
    );
    return (r.data['resources'] as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> upload(
    String path,
    void Function(double) progress,
  ) async {
    final file = File(path);
    final length = await file.length();
    if (!path.toLowerCase().endsWith('.rpk') ||
        length < 1 ||
        length > 32 * 1024 * 1024) {
      throw StateError('请选择不超过 32 MB 的 RPK 安装包');
    }
    final response = await dio.post<dynamic>(
      'v1/store/resources',
      data: file.openRead(),
      options: Options(
        contentType: 'application/octet-stream',
        headers: {Headers.contentLengthHeader: length},
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(seconds: 60),
      ),
      onSendProgress: (sent, total) => progress((sent / length).clamp(0, 1)),
    );
    return (response.data as Map).cast<String, dynamic>();
  }

  Future<void> publish(String id, bool value) async {
    await dio.patch<dynamic>(
      'v1/store/resources/$id',
      data: {'published': value},
    );
  }

  Future<Map<String, dynamic>> activationStatus(
    String resource,
    String model,
    String serial, {
    String firmware = '',
    String? grantId,
  }) async {
    final response = await dio.post<dynamic>(
      'v1/store/activation/status',
      data: {
        'resourceId': resource,
        'model': model,
        'serial': serial,
        'firmware': firmware,
        if (grantId != null) 'grantId': grantId,
      },
    );
    return (response.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> activatedResources({
    String model = '',
    String serial = '',
    String firmware = '',
    int offset = 0,
  }) async {
    final response = await dio.post<dynamic>(
      'v1/store/activation/library',
      data: {
        'model': model,
        'serial': serial,
        'firmware': firmware,
        'offset': offset,
      },
    );
    return (response.data as Map).cast<String, dynamic>();
  }

  Future<void> activate(
    String resource,
    String model,
    String serial,
    String code, {
    String firmware = '',
  }) async {
    await dio.post<dynamic>(
      'v1/store/activation/redeem',
      data: {
        'resourceId': resource,
        'model': model,
        'serial': serial,
        'firmware': firmware,
        'code': code,
      },
    );
  }

  Future<CloudPackageSource> open(
    String id,
    String device,
    String model, {
    String serial = '',
    String firmware = '',
    bool activationRequired = false,
    String? grantId,
  }) async {
    if (!Platform.isAndroid) throw StateError('云端安装目前仅支持安卓端');
    final source = CloudPackageSource(dio);
    try {
      await source.initialize(
        id,
        device.toUpperCase(),
        model,
        serial: serial,
        firmware: firmware,
        activationRequired: activationRequired,
        grantId: grantId,
      );
      return source;
    } catch (_) {
      try {
        await source.close();
      } catch (_) {}
      rethrow;
    }
  }
}

class CloudPackageSource extends MassPayloadSource {
  CloudPackageSource(this.dio);
  static const _crypto = MethodChannel('wristbox/store_crypto');
  final Dio dio;
  final CancelToken _cancel = CancelToken();
  Map<String, dynamic> manifest = {};
  String? _sid;
  bool _closed = false;
  int _cachedIndex = -1;
  Uint8List _cached = Uint8List(0);
  @override
  int get length => manifest['size'] as int;
  @override
  Uint8List get md5 => Uint8List.fromList(
    List.generate(
      16,
      (i) => int.parse(
        (manifest['md5'] as String).substring(i * 2, i * 2 + 2),
        radix: 16,
      ),
    ),
  );

  Future<void> initialize(
    String resource,
    String device,
    String model, {
    String serial = '',
    String firmware = '',
    bool activationRequired = false,
    String? grantId,
  }) async {
    final trusted = await rootBundle.load(
      'assets/certificates/wristbox-store-signing.der',
    );
    final public = await _crypto.invokeMethod<String>('prepare');
    final begin = <String, dynamic>{
      'resourceId': resource,
      'device': device,
      'model': model,
      'serial': serial,
      'firmware': firmware,
      'publicKey': public,
      if (grantId != null) 'grantId': grantId,
    };
    final challenge = await dio.post<dynamic>(
      'v1/store/challenges',
      data: begin,
    );
    final proof = await _crypto.invokeMethod<String>('prove', {
      'message': challenge.data['message'],
    });
    final response = await dio.post<dynamic>(
      'v1/store/sessions',
      data: {...begin, 'challengeId': challenge.data['id'], 'proof': proof},
    );
    final data = (response.data as Map).cast<String, dynamic>();
    // The native verifier checks the signature and request binding before unwrap.
    await _crypto.invokeMethod<bool>('accept', {
      ...data,
      'trustedKey': trusted.buffer.asUint8List(
        trusted.offsetInBytes,
        trusted.lengthInBytes,
      ),
      'device': device,
      'resourceId': resource,
      'model': model,
      'firmware': firmware,
      'activationRequired': activationRequired,
      'deviceIdentity': sha256
          .convert(utf8.encode('$model\u0000${serial.trim().toUpperCase()}'))
          .toString(),
    });
    final envelope = jsonDecode(
      utf8.decode(base64Decode(data['envelope'] as String)),
    ) as Map;
    if (grantId != null && envelope['activationId'] != grantId) {
      throw StateError('安装会话与所选资源授权不一致，已停止下载');
    }
    _sid = envelope['sessionId'] as String;
    manifest = (envelope['manifest'] as Map).cast<String, dynamic>();
  }

  Future<Uint8List> _chunk(int seq) async {
    if (_closed) throw StateError('安装已结束');
    final expected = (length - seq * 65536).clamp(0, 65536) + 16;
    final result = await dio.get<ResponseBody>(
      'v1/store/sessions/$_sid/chunks/$seq',
      cancelToken: _cancel,
      options: Options(responseType: ResponseType.stream),
    );
    final body = result.data!;
    final buffer = BytesBuilder(copy: false);
    await for (final part in body.stream) {
      if (_closed || buffer.length + part.length > expected) {
        throw StateError('云端分片长度异常');
      }
      buffer.add(part);
    }
    if (buffer.length != expected) throw StateError('云端分片不完整，请重试');
    final received = await _crypto.invokeMethod<Uint8List>('decrypt', {
      'seq': seq,
      'ciphertext': buffer.takeBytes(),
    });
    if (received == null) throw StateError('安全解密未返回安装分片');
    // Engine platform replies are read-only. Own a bounded, mutable chunk so
    // replacing/closing the cache can wipe it without throwing UnsupportedError.
    // The temporary platform-message buffer itself is managed by the engine.
    final plain = Uint8List.fromList(received);
    if (_closed || plain.length != expected - 16) {
      plain.fillRange(0, plain.length, 0);
      if (!_closed) throw StateError('解密后的安装分片长度异常');
      throw StateError('安装已结束');
    }
    return plain;
  }

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (_closed ||
        offset < 0 ||
        count < 0 ||
        count > 65536 ||
        offset + count > length) {
      throw StateError('安装分片越界或会话已结束');
    }
    final out = Uint8List(count);
    var written = 0;
    try {
      while (written < count) {
        final index = (offset + written) ~/ 65536;
        if (index != _cachedIndex) {
          _cached.fillRange(0, _cached.length, 0);
          _cached = Uint8List(0);
          _cached = await _chunk(index);
          _cachedIndex = index;
        }
        final start = (offset + written) % 65536;
        final n = (_cached.length - start).clamp(0, count - written);
        if (n == 0) throw StateError('安装分片为空');
        out.setRange(written, written + n, _cached, start);
        written += n;
      }
      return out;
    } catch (_) {
      out.fillRange(0, out.length, 0);
      rethrow;
    }
  }

  Future<void> finish(bool success) async {
    if (_sid == null) return;
    try {
      await dio.post<dynamic>(
        'v1/store/sessions/$_sid/complete',
        data: {'success': success},
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      /* Reporting failure must not repeat a completed band install. */
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cancel.cancel();
    try {
      _cached.fillRange(0, _cached.length, 0);
    } finally {
      _cached = Uint8List(0);
      _cachedIndex = -1;
      await _crypto.invokeMethod<void>('close');
    }
  }
}

String cloudError(Object error) {
  if (error is StateError) return error.message;
  if (error is PlatformException) return error.message ?? '安全校验失败，安装已停止';
  if (error is DioException) {
    final data = error.response?.data;
    if ([
          400,
          403,
          409,
          410,
          413,
          429,
          503,
        ].contains(error.response?.statusCode) &&
        data is Map &&
        data['detail'] is String &&
        (data['detail'] as String).length <= 200) {
      return data['detail'] as String;
    }
    return switch (error.response?.statusCode) {
      400 || 422 => '应用资料无效，请检查 RPK 的清单和版本号',
      401 => '邮箱登录已过期，请重新登录',
      403 => '账号已停用或没有操作权限，请联系管理员',
      409 => '当前状态不允许此操作，请刷新后重试',
      404 => '应用不存在或已下架',
      410 => '安装会话已过期或被撤销，请重试',
      413 => '安装包不能超过 32 MB',
      429 => '操作过于频繁，请稍后重试',
      503 => '商店暂不可用或资源校验失败，请联系管理员',
      null => networkErrorMessage(error),
      >= 500 => '服务器暂时不可用，请稍后重试',
      _ => '服务器未能完成请求，请刷新后重试或联系管理员',
    };
  }
  if (error is TimeoutException) return '安装超时，已停止连接，请重新连接后重试';
  if (error is UnsupportedError || error is TypeError || error is RangeError) {
    return '安装数据处理异常，请更新 WristBox 后重试；若仍失败，请反馈当前安装阶段';
  }
  return friendlyError(error, installing: true);
}
