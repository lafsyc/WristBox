import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/cloud_store.dart';
import 'package:oronbox/src/protocols/xiaomi/transport/mass_payload_source.dart';
import 'package:oronbox/src/protocols/xiaomi/packet/mass_packet.dart';

class PackageAdapter implements HttpClientAdapter {
  PackageAdapter(this.bytes);
  final Uint8List bytes;
  final requested = <int>[];
  final reports = <bool>[];
  Map? beginBody;
  String? returnedGrantId;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/challenges')) {
      return ResponseBody.fromString(
        jsonEncode({'id': 'a' * 32, 'message': 'challenge'}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (options.path.endsWith('/sessions')) {
      beginBody = options.data as Map;
      return ResponseBody.fromString(
        jsonEncode({
          'envelope': base64Encode(
            utf8.encode(
              jsonEncode({
                'sessionId': 'fixture',
                if (returnedGrantId != null) 'activationId': returnedGrantId,
                'manifest': {
                  'size': bytes.length,
                  'md5': crypto.md5.convert(bytes).toString(),
                  'packageName': 'test.package',
                  'versionCode': 1,
                },
              }),
            ),
          ),
          'signature': 'fixture',
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (options.path.endsWith('/complete')) {
      reports.add((options.data as Map)['success'] as bool);
      return ResponseBody.fromString(
        '{}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    final index = int.parse(options.path.split('/').last);
    requested.add(index);
    final size = (bytes.length - index * 65536).clamp(0, 65536);
    return ResponseBody(Stream.value(Uint8List(size + 16)), 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = 'wristbox/store_crypto';
  const codec = StandardMethodCodec();
  late Uint8List bytes;
  late PackageAdapter adapter;
  late Dio dio;
  late int closes;
  Map? acceptArguments;
  setUp(() {
    bytes = Uint8List.fromList(List.generate(131077, (i) => (i * 37) & 255));
    adapter = PackageAdapter(bytes);
    dio = Dio()..httpClientAdapter = adapter;
    closes = 0;
    acceptArguments = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(channel, (message) async {
          final call = codec.decodeMethodCall(message);
          dynamic result;
          switch (call.method) {
            case 'prepare':
              result = 'fixture';
            case 'prove':
              result = 'proof';
            case 'accept':
              acceptArguments = call.arguments as Map;
              result = true;
            case 'decrypt':
              final start = (call.arguments['seq'] as int) * 65536;
              result = Uint8List.sublistView(
                bytes,
                start,
                (start + 65536).clamp(0, bytes.length),
              );
            case 'close':
              closes++;
              result = true;
          }
          // Flutter engine hands platform responses to Dart as READ-ONLY buffers.
          // setMockMethodCallHandler alone does not model that production behavior.
          return codec.encodeSuccessEnvelope(result).asUnmodifiableView();
        });
  });
  tearDown(() {
    dio.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(channel, null);
  });
  test(
    'selected grant must match the verified envelope before reading any chunks',
    () async {
      adapter.returnedGrantId = 'b' * 32;
      final source = CloudPackageSource(dio);
      await expectLater(
        source.initialize(
          'resource',
          'device',
          'n67',
          serial: 'TESTSN000001',
          grantId: 'a' * 32,
        ),
        throwsStateError,
      );
      expect(adapter.beginBody?['grantId'], 'a' * 32);
      expect(adapter.requested, isEmpty);
      await source.close();
      final matching = CloudPackageSource(dio);
      await matching.initialize(
        'resource',
        'device',
        'n67',
        serial: 'TESTSN000001',
        grantId: 'b' * 32,
      );
      await matching.close();
    },
  );
  test('read-only platform responses stream across encrypted chunk boundaries and close safely', () async {
    final source = CloudPackageSource(dio);
    await source.initialize('resource', 'device', 'n67');
    final frame = StreamingMassPayload(
      source,
      MassDataType.thirdPartyApp.value,
      0,
    );
    final collected = BytesBuilder();
    while (collected.length < frame.length) {
      collected.add(
        await frame.read((frame.length - collected.length).clamp(0, 2044)),
      );
    }
    expect(
      collected.takeBytes(),
      MassPacket.build(bytes, MassDataType.thirdPartyApp).encodeWithCrc32(),
    );
    await source.close();
    await source.close();
    await source.finish(true);
    expect(closes, 1);
    expect(adapter.requested, [0, 1, 2]);
    expect(adapter.reports, [true]);
  });
  test(
    'closing after first decrypted chunk still releases native session',
    () async {
      final source = CloudPackageSource(dio);
      await source.initialize('resource', 'device', 'n67');
      expect(await source.read(0, 10), bytes.sublist(0, 10));
      await source.close();
      expect(closes, 1);
    },
  );
  test(
    'activation identity is bound into session request and native verifier',
    () async {
      final source = CloudPackageSource(dio);
      await source.initialize(
        'resource',
        'device',
        'n67',
        serial: 'TESTSN000001',
        activationRequired: true,
      );
      expect(adapter.beginBody?['serial'], 'TESTSN000001');
      expect(acceptArguments?['activationRequired'], isTrue);
      expect(
        acceptArguments?['deviceIdentity'],
        crypto.sha256.convert(utf8.encode('n67\u0000TESTSN000001')).toString(),
      );
      await source.close();
    },
  );
}
