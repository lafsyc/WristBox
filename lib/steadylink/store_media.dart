import 'dart:typed_data';

import 'package:flutter/material.dart';

class StoreMediaImage extends StatefulWidget {
  const StoreMediaImage({
    super.key,
    required this.id,
    required this.load,
    this.width = 64,
    this.height = 64,
    this.fit = BoxFit.contain,
    this.radius = 18,
    this.preview = false,
  });
  final String id;
  final Future<Uint8List> Function(String) load;
  final double width, height, radius;
  final BoxFit fit;
  final bool preview;
  @override
  State<StoreMediaImage> createState() => _StoreMediaImageState();
}

class _StoreMediaImageState extends State<StoreMediaImage> {
  Future<Uint8List>? _image;
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(StoreMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.load != widget.load) _fetch();
  }

  void _fetch() {
    _image = widget.id.isEmpty ? null : widget.load(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget placeholder({bool error = false}) => Center(
      child: Icon(
        error
            ? Icons.broken_image_outlined
            : widget.preview
            ? Icons.photo_outlined
            : Icons.apps_rounded,
        color: colors.primary.withValues(alpha: .55),
        size: widget.preview ? 32 : 28,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ColoredBox(
          color: colors.surfaceContainerHighest.withValues(alpha: .55),
          child: _image == null
              ? placeholder()
              : FutureBuilder<Uint8List>(
                  future: _image,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Tooltip(
                        message: '图片暂时无法加载，请刷新重试',
                        child: placeholder(error: true),
                      );
                    }
                    if (!snapshot.hasData) {
                      return Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary.withValues(alpha: .4),
                          ),
                        ),
                      );
                    }
                    return Image.memory(
                      snapshot.data!,
                      fit: widget.fit,
                      gaplessPlayback: true,
                      errorBuilder: (_, error, stack) =>
                          placeholder(error: true),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
