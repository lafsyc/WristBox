import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/protocols/xiaomi/packet/mass_packet.dart';
import 'package:oronbox/src/protocols/xiaomi/transport/mass_payload_source.dart';

class _Source extends MassPayloadSource {
  _Source(this.bytes);
  final Uint8List bytes;
  int largestRead = 0;
  @override
  int get length => bytes.length;
  @override
  Uint8List get md5 => Uint8List.fromList(crypto.md5.convert(bytes).bytes);
  @override
  Future<Uint8List> read(int offset, int count) async {
    largestRead = max(largestRead, count);
    return Uint8List.fromList(bytes.sublist(offset, offset + count));
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('streamed bytes and CRC match existing MASS format at resume and fragment boundaries', () async {
    final random = Random(37);
    for (final size in [1, 22, 128, 65537, 200003]) {
      final bytes = Uint8List.fromList(
        List.generate(size, (_) => random.nextInt(256)),
      );
      for (final type in [MassDataType.thirdPartyApp, MassDataType.watchface]) {
        for (final resume in {0, size ~/ 2, size}) {
          for (final slice in [1, 238, 2044, 8192]) {
            final source = _Source(bytes);
            final payload = StreamingMassPayload(source, type.value, resume);
            final collected = BytesBuilder();
            while (collected.length < payload.length) {
              collected.add(
                await payload.read(
                  min(slice, payload.length - collected.length),
                ),
              );
            }
            expect(
              collected.takeBytes(),
              MassPacket.build(bytes, type).encodeWithCrc32(sentLength: resume),
            );
            expect(source.largestRead, lessThanOrEqualTo(slice));
          }
        }
      }
    }
  });
  test('invalid bounds fail closed', () async {
    final source = _Source(Uint8List(8));
    expect(() => StreamingMassPayload(source, 64, 9), throwsStateError);
    final payload = StreamingMassPayload(source, 64, 0);
    await expectLater(payload.read(payload.length + 1), throwsStateError);
  });
}
