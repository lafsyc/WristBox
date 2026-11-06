import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const maxAvatarSourceBytes = 20 * 1024 * 1024;

Future<Uint8List> readAvatarFile(String path) async {
  final file = File(path);
  final length = await file.length();
  if (length == 0 || length > maxAvatarSourceBytes) {
    throw StateError('请选择不超过 20 MB 的图片');
  }
  final output = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (output.length + chunk.length > maxAvatarSourceBytes) {
      throw StateError('图片不能超过 20 MB');
    }
    output.add(chunk);
  }
  return output.takeBytes();
}

Future<ui.Image> decodeAvatarPreview(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > maxAvatarSourceBytes) {
    throw StateError('请选择不超过 20 MB 的图片');
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width < 16 ||
        descriptor.height < 16 ||
        descriptor.width > 16000 ||
        descriptor.height > 16000 ||
        descriptor.width * descriptor.height > 64000000) {
      throw StateError('图片尺寸过大或过小，请选择边长 16–16000 像素、最多 6400 万像素的图片');
    }
    final factor = math.min(
      1.0,
      1536 / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * factor).round()),
      targetHeight: math.max(1, (descriptor.height * factor).round()),
    );
    if (codec.frameCount != 1) throw StateError('头像暂不支持动图，请选择静态图片');
    return (await codec.getNextFrame()).image;
  } on StateError {
    rethrow;
  } catch (_) {
    throw StateError('无法读取此图片，请换用 JPG、PNG 或 WebP 静态图片');
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Rect avatarCropRect(int width, int height, double zoom, Offset center) {
  final side = math.min(width, height) / zoom.clamp(1.0, 5.0);
  final x = center.dx.clamp(side / 2, width - side / 2);
  final y = center.dy.clamp(side / 2, height - side / 2);
  return Rect.fromCenter(center: Offset(x, y), width: side, height: side);
}

Future<Uint8List> encodeAvatarCrop(ui.Image image, Rect crop) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    crop,
    const Rect.fromLTWH(0, 0, 512, 512),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  ui.Image? output;
  try {
    output = await picture.toImage(512, 512);
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes > 2 * 1024 * 1024) {
      throw StateError('图片压缩失败，请更换图片');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    output?.dispose();
    picture.dispose();
  }
}

class AvatarCropDialog extends StatefulWidget {
  const AvatarCropDialog({super.key, required this.image});
  final ui.Image image;
  @override
  State<AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<AvatarCropDialog> {
  late final ui.Image _image;
  @override
  void initState() {
    super.initState();
    _image = widget.image.clone();
  }

  @override
  void dispose() {
    _image.dispose();
    super.dispose();
  }

  late Offset _center = Offset(_image.width / 2, _image.height / 2);
  double _zoom = 1, _startZoom = 1;
  Offset _startCenter = Offset.zero, _startFocal = Offset.zero;
  bool _busy = false;
  String? _error;
  Rect get _crop => avatarCropRect(_image.width, _image.height, _zoom, _center);
  void _constrain() => _center = _crop.center;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('裁切头像'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final side = math.min(constraints.maxWidth, 320.0);
                  return GestureDetector(
                    key: const ValueKey('avatar-crop-canvas'),
                    onScaleStart: _busy
                        ? null
                        : (d) {
                            _startZoom = _zoom;
                            _startCenter = _crop.center;
                            _startFocal = d.localFocalPoint;
                          },
                    onScaleUpdate: _busy
                        ? null
                        : (d) => setState(() {
                            final minSide = math.min(
                              _image.width,
                              _image.height,
                            );
                            final anchor =
                                _startCenter +
                                (_startFocal - Offset(side / 2, side / 2)) *
                                    (minSide / _startZoom / side);
                            _zoom = (_startZoom * d.scale).clamp(1.0, 5.0);
                            _center =
                                anchor -
                                (d.localFocalPoint -
                                        Offset(side / 2, side / 2)) *
                                    (minSide / _zoom / side);
                            _constrain();
                          }),
                    child: Semantics(
                      label: '头像裁切预览，可拖动图片并双指缩放',
                      image: true,
                      child: CustomPaint(
                        size: Size.square(side),
                        painter: _CropPainter(_image, _crop),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text('拖动调整位置，双指或滑杆缩放', textAlign: TextAlign.center),
              Slider(
                value: _zoom,
                min: 1,
                max: 5,
                label: '${_zoom.toStringAsFixed(1)} 倍',
                semanticFormatterCallback: (v) => '${v.toStringAsFixed(1)} 倍',
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _zoom = v;
                        _constrain();
                      }),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _zoom = 1;
                        _center = Offset(_image.width / 2, _image.height / 2);
                      }),
                child: const Text('重置裁切'),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    final data = await encodeAvatarCrop(_image, _crop);
                    if (context.mounted) Navigator.pop(context, data);
                  } catch (_) {
                    if (mounted) {
                      setState(() {
                        _busy = false;
                        _error = '图片处理失败，请重试';
                      });
                    }
                  }
                },
          child: const Text('使用头像'),
        ),
      ],
    ),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.crop);
  final ui.Image image;
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawImageRect(
      image,
      crop,
      rect,
      Paint()..filterQuality = FilterQuality.high,
    );
    final shade = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addOval(rect.deflate(1)),
    );
    canvas.drawPath(shade, Paint()..color = const Color(0x88000000));
    canvas.drawOval(
      rect.deflate(1),
      Paint()
        ..color = const Color(0xDFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      image != old.image || crop != old.crop;
}
