import 'dart:typed_data';

/// Caller owns the source and must close it on success, cancellation and error.
abstract class MassPayloadSource {
  int get length;
  Uint8List get md5;

  /// Returns an owned buffer of exactly [count] bytes. No full-package buffer.
  Future<Uint8List> read(int offset, int count);
  Future<void> close();
}

/// Sequential MASS framing with incremental CRC. Retains at most one fragment.
class StreamingMassPayload {
  StreamingMassPayload(this.source, int dataType, this.resume)
    : header = Uint8List(22) {
    if (resume < 0 || resume > source.length || source.md5.length != 16) {
      throw StateError('安装数据长度无效');
    }
    header[1] = dataType;
    header.setRange(2, 18, source.md5);
    ByteData.sublistView(header)
        .setUint32(18, source.length - resume, Endian.little);
  }
  final MassPayloadSource source;
  final int resume;
  final Uint8List header;
  int _position = 0, _crc = 0xffffffff;
  int get length => 22 + source.length - resume + 4;

  Future<Uint8List> read(int count) async {
    if (count < 0 || _position + count > length) throw StateError('安装分片越界');
    final out = Uint8List(count);
    var written = 0;
    final dataEnd = length - 4;
    while (written < count) {
      if (_position < 22) {
        final n = (22 - _position).clamp(0, count - written);
        out.setRange(written, written + n, header, _position);
        _update(Uint8List.sublistView(out, written, written + n));
        written += n;
        _position += n;
      } else if (_position < dataEnd) {
        final n = (dataEnd - _position).clamp(0, count - written);
        final bytes = await source.read(resume + _position - 22, n);
        try {
          if (bytes.length != n) throw StateError('安装数据提前结束');
          out.setRange(written, written + n, bytes);
          _update(bytes);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
        written += n;
        _position += n;
      } else {
        final crc = (_crc ^ 0xffffffff) & 0xffffffff;
        out[written++] = (crc >> (8 * (_position++ - dataEnd))) & 255;
      }
    }
    return out;
  }

  void _update(Uint8List bytes) {
    for (final b in bytes) {
      _crc ^= b;
      for (var bit = 0; bit < 8; bit++) {
        _crc = (_crc >> 1) ^ ((_crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
  }
}
