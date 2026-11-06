import 'dart:math' as math;

import 'package:flutter/material.dart';

bool isProBand(String name) => name.toLowerCase().contains('pro');

enum BandScreen { idle, connecting, battery, transfer, confirming, done, error }

/// Independently drawn AstroBox-inspired outline with live device status.
class BandIllustration extends StatelessWidget {
  const BandIllustration({
    super.key,
    this.pro = false,
    this.width = 92,
    this.height = 120,
    this.phase = 0,
    this.screen = BandScreen.idle,
    this.battery,
    this.progress = 0,
  });
  final bool pro;
  final double width, height, phase, progress;
  final BandScreen screen;
  final int? battery;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _BandPainter(
          pro,
          phase,
          screen,
          battery,
          progress,
          Theme.of(context).colorScheme.onSurface,
          width < 60,
        ),
      ),
    ),
  );
}

class _BandPainter extends CustomPainter {
  _BandPainter(
    this.pro,
    this.phase,
    this.screen,
    this.battery,
    this.progress,
    this.outline,
    this.compact,
  );
  final bool pro, compact;
  final double phase, progress;
  final int? battery;
  final BandScreen screen;
  final Color outline;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 92, size.height / 120);
    canvas.save();
    canvas.translate(
      (size.width - 92 * scale) / 2,
      (size.height - 120 * scale) / 2,
    );
    canvas.scale(scale);
    final body = Rect.fromCenter(
      center: const Offset(46, 60),
      width: pro ? 74 : 48,
      height: 108,
    );
    final radius = pro ? 21.0 : 24.0;
    final shell = RRect.fromRectAndRadius(body, Radius.circular(radius));
    canvas.drawRRect(shell, Paint()..color = const Color(0xFF14181F));
    canvas.drawRRect(
      shell,
      Paint()
        ..color = outline.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    final face = body.deflate(4.5);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(face, Radius.circular(radius - 4.5)),
    );
    canvas.drawRect(
      face,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF19222C), Color(0xFF10171F)],
        ).createShader(face),
    );
    const mint = Color(0xFF80E3CA);
    const violet = Color(0xFFC4B1FF);
    final tint = screen == BandScreen.error
        ? const Color(0xFFFFA298)
        : screen == BandScreen.transfer || screen == BandScreen.confirming
        ? violet
        : mint;
    if (screen == BandScreen.battery && battery != null) {
      _liquid(
        canvas,
        face,
        battery!.clamp(0, 100) / 100,
        battery! <= 15 ? const Color(0xFFFFBA85) : mint,
      );
    } else if (screen == BandScreen.transfer) {
      _liquid(canvas, face, progress.clamp(0, 1), violet);
    } else if (screen == BandScreen.done) {
      _liquid(canvas, face, 1, mint);
    } else if (screen == BandScreen.connecting ||
        screen == BandScreen.confirming) {
      final y = face.top - 25 + (face.height + 50) * phase;
      final beam = Rect.fromLTWH(face.left, y - 25, face.width, 50);
      canvas.drawRect(
        beam,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tint.withValues(alpha: 0),
              tint.withValues(alpha: .24),
              tint.withValues(alpha: 0),
            ],
          ).createShader(beam),
      );
    }
    if (compact) {
      _glyph(canvas, const Offset(46, 60), tint, screen);
    } else {
      _glyph(
        canvas,
        Offset(
          46,
          screen == BandScreen.done || screen == BandScreen.error ? 60 : 29,
        ),
        screen == BandScreen.error ? tint : const Color(0xFFDBEEE9),
        screen,
      );
      final value = switch (screen) {
        BandScreen.battery =>
          battery == null ? '—' : '${battery!.clamp(0, 100)}',
        BandScreen.transfer =>
          '${(progress.clamp(0, 1) * 100).floor().clamp(0, 99)}',
        _ => '',
      };
      if (value.isNotEmpty) {
        final suffix = screen == BandScreen.transfer || battery != null
            ? '%'
            : '';
        _text(canvas, '$value$suffix', const Offset(46, 88), 12, opacity: .9);
      } else if (screen != BandScreen.done && screen != BandScreen.error) {
        for (var i = 0; i < 3; i++) {
          final active =
              screen == BandScreen.connecting ||
              screen == BandScreen.confirming;
          final opacity = active
              ? .25 + .65 * (1 + math.sin(phase * math.pi * 2 - i * 1.5)) / 2
              : .25;
          canvas.drawCircle(
            Offset(38 + i * 8, 70),
            1.8,
            Paint()..color = tint.withValues(alpha: opacity),
          );
        }
      }
    }
    canvas.restore();
    canvas.restore();
  }

  void _liquid(Canvas canvas, Rect face, double fraction, Color color) {
    if (fraction <= 0) return;
    // Mean liquid height is the measured fraction; edge cases flatten exactly.
    final envelope = math.min(1.0, math.min(fraction, 1 - fraction) * 12);
    final amplitude = (pro ? 5.6 : 4.4) * envelope;
    final level = face.bottom - face.height * fraction;
    final hue = HSVColor.fromColor(color).hue;
    final depth = HSVColor.fromAHSV(1, (hue + 12) % 360, .78, .26).toColor();
    final middle = HSVColor.fromAHSV(1, hue, .64, .68).toColor();
    for (var layer = 0; layer < 3; layer++) {
      final water = Path()..moveTo(face.left, face.bottom);
      final crest = Path();
      for (double x = face.left; x <= face.right + 1; x += .75) {
        final position = (x - face.left) / face.width * math.pi * 2;
        final travel = phase * math.pi * 2 * (layer == 1 ? -1 : 1);
        final y =
            level +
            amplitude *
                (.78 * math.sin(position + travel + layer * 1.9) +
                    .22 * math.sin(position * 2 - travel + layer));
        water.lineTo(x, y);
        if (x == face.left) {
          crest.moveTo(x, y);
        } else {
          crest.lineTo(x, y);
        }
      }
      water.lineTo(face.right, face.bottom);
      water.close();
      final front = layer == 2;
      canvas.drawPath(
        water,
        Paint()
          ..shader =
              LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .45, 1],
                colors: front
                    ? [
                        color.withValues(alpha: .92),
                        middle.withValues(alpha: .94),
                        depth,
                      ]
                    : [
                        color.withValues(alpha: .22 + layer * .13),
                        middle.withValues(alpha: .18),
                        depth.withValues(alpha: .35),
                      ],
              ).createShader(
                Rect.fromLTRB(
                  face.left,
                  level - amplitude,
                  face.right,
                  face.bottom,
                ),
              ),
      );
      if (front && fraction < 1) {
        canvas.drawPath(
          crest,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .85
            ..shader = LinearGradient(
              colors: [
                color.withValues(alpha: .2),
                Colors.white.withValues(alpha: .65),
                color.withValues(alpha: .2),
              ],
              begin: Alignment(-1 + math.sin(phase * math.pi * 2) * .5, -1),
              end: Alignment(1 + math.sin(phase * math.pi * 2) * .5, 1),
            ).createShader(face),
        );
      }
    }
    // A quiet underwater glow gives depth without texture assets or blur passes.
    final glow = Rect.fromCircle(
      center: Offset(
        face.center.dx + math.sin(phase * math.pi * 2) * 8,
        face.bottom,
      ),
      radius: face.width * .75,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        face.left,
        math.min(face.bottom, level + amplitude),
        face.right,
        face.bottom,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: .13), color.withValues(alpha: 0)],
        ).createShader(glow),
    );
  }

  void _glyph(Canvas canvas, Offset center, Color color, BandScreen mode) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final paint = Paint()
      ..color = mode == BandScreen.idle ? const Color(0xFFA0A9B7) : color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (mode) {
      case BandScreen.battery:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-7, -4, 13, 8),
            const Radius.circular(2),
          ),
          paint,
        );
        canvas.drawLine(const Offset(8, -1.5), const Offset(8, 1.5), paint);
        if (battery != null && battery! > 0) {
          canvas.drawRect(
            Rect.fromLTWH(-4.5, -1.7, 8 * battery!.clamp(0, 100) / 100, 3.4),
            Paint()..color = color,
          );
        }
      case BandScreen.transfer:
        path
          ..moveTo(0, -7)
          ..lineTo(0, 3)
          ..moveTo(-4, 0)
          ..lineTo(0, 4)
          ..lineTo(4, 0)
          ..moveTo(-7, 5)
          ..lineTo(-7, 8)
          ..lineTo(7, 8)
          ..lineTo(7, 5);
      case BandScreen.confirming:
        canvas.drawCircle(
          Offset.zero,
          7,
          paint..color = color.withValues(alpha: .25),
        );
        canvas.drawArc(
          const Rect.fromLTWH(-7, -7, 14, 14),
          phase * math.pi * 2,
          math.pi * 1.3,
          false,
          paint..color = color,
        );
      case BandScreen.done:
        path
          ..moveTo(-6, 0)
          ..lineTo(-1, 5)
          ..lineTo(7, -5);
      case BandScreen.error:
        path
          ..moveTo(-5, -5)
          ..lineTo(5, 5)
          ..moveTo(5, -5)
          ..lineTo(-5, 5);
      case BandScreen.idle:
      case BandScreen.connecting:
        path
          ..moveTo(-5, -5)
          ..lineTo(5, 4)
          ..lineTo(0, 9)
          ..lineTo(0, -9)
          ..lineTo(5, -4)
          ..lineTo(-5, 5);
    }
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    double size, {
    double opacity = 1,
  }) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Roboto',
          color: Colors.white.withValues(alpha: opacity),
          fontSize: size,
          fontWeight: FontWeight.w500,
          shadows: const [Shadow(color: Color(0x66000000), blurRadius: 3)],
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    painter.layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _BandPainter old) =>
      old.pro != pro ||
      old.phase != phase ||
      old.screen != screen ||
      old.battery != battery ||
      old.progress != progress ||
      old.outline != outline ||
      old.compact != compact;
}
