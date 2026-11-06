import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'operation_queue.dart';
import 'band_illustration.dart';

/// A single, paused-when-hidden clock shared by the painted mobile effects.
class MotionSurface extends StatefulWidget {
  const MotionSurface({super.key, required this.active, required this.builder});
  final bool active;
  final Widget Function(BuildContext, double) builder;
  @override
  State<MotionSurface> createState() => _MotionSurfaceState();
}

class _MotionSurfaceState extends State<MotionSurface>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  void _sync() {
    final animate =
        widget.active &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      if (!_clock.isAnimating) _clock.repeat();
    } else {
      _clock.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant MotionSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _clock,
    builder: (_, _) => widget.builder(context, _clock.value),
  );
}

BandScreen bandScreenForJob(InstallJob job) => switch (job.phase) {
  InstallPhase.connecting => BandScreen.connecting,
  InstallPhase.installing =>
    job.progress >= 1 ? BandScreen.confirming : BandScreen.transfer,
  InstallPhase.succeeded => BandScreen.done,
  InstallPhase.failed => BandScreen.error,
  InstallPhase.queued || InstallPhase.cancelled => BandScreen.idle,
};

class ConnectionOrbit extends StatelessWidget {
  const ConnectionOrbit({
    super.key,
    required this.ready,
    required this.connecting,
    this.pro = false,
    this.battery,
    this.job,
  });
  final bool ready, connecting, pro;
  final int? battery;
  final InstallJob? job;
  @override
  Widget build(BuildContext context) {
    final display = job != null
        ? bandScreenForJob(job!)
        : connecting
        ? BandScreen.connecting
        : ready
        ? BandScreen.battery
        : BandScreen.idle;
    final active =
        display == BandScreen.connecting ||
        display == BandScreen.transfer ||
        display == BandScreen.confirming ||
        (display == BandScreen.battery && battery != null);
    final label = switch (display) {
      BandScreen.idle => '等待连接',
      BandScreen.connecting => '正在连接',
      BandScreen.battery =>
        battery == null ? '设备已连接，电量待刷新' : '设备已连接，电量 ${battery!.clamp(0, 100)}%',
      BandScreen.transfer =>
        '正在传输 ${(job!.progress.clamp(0, 1) * 100).floor().clamp(0, 99)}%',
      BandScreen.confirming => '文件已传完，等待手环确认',
      BandScreen.done => '安装完成',
      BandScreen.error => '安装失败',
    };
    return Semantics(
      label: label,
      child: MotionSurface(
        active: active,
        builder: (_, t) => SizedBox(
          width: 130,
          height: 140,
          child: Center(
            child: BandIllustration(
              pro: pro,
              width: 100,
              height: 130,
              phase: t,
              screen: display,
              battery: ready ? battery : null,
              progress: job?.progress ?? 0,
            ),
          ),
        ),
      ),
    );
  }
}

class MobileTransferCard extends StatelessWidget {
  const MobileTransferCard({super.key, required this.job, this.cancel});
  final InstallJob job;
  final VoidCallback? cancel;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final waiting = job.phase == InstallPhase.installing && job.progress >= 1;
    final active =
        job.phase == InstallPhase.connecting ||
        job.phase == InstallPhase.installing;
    final done = job.phase == InstallPhase.succeeded;
    final failed = job.phase == InstallPhase.failed;
    final color = failed
        ? colors.error
        : done
        ? (colors.brightness == Brightness.dark
              ? const Color(0xFF91D5AC)
              : const Color(0xFF216C4A))
        : colors.primary;
    final status = switch (job.phase) {
      InstallPhase.queued => '排队中',
      InstallPhase.connecting => '正在连接',
      InstallPhase.installing => waiting ? '等待手环确认' : '正在传输',
      InstallPhase.succeeded => '安装完成',
      InstallPhase.failed => '安装失败',
      InstallPhase.cancelled => '已取消',
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: active ? .25 : .10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  done
                      ? Icons.check_rounded
                      : failed
                      ? Icons.error_outline_rounded
                      : Icons.install_mobile_rounded,
                  size: 21,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      job.deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (job.phase == InstallPhase.queued && cancel != null)
                IconButton(
                  onPressed: cancel,
                  tooltip: '取消排队',
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    status,
                    key: ValueKey(status),
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (job.phase == InstallPhase.installing && !waiting)
                TweenAnimationBuilder<double>(
                  tween: Tween(end: job.progress.clamp(0, 1)),
                  duration: const Duration(milliseconds: 280),
                  builder: (_, value, _) => Text(
                    '${(value * 100).floor().clamp(0, 99)}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.5,
                      color: colors.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 10),
            Semantics(
              label: status,
              value: waiting || job.phase == InstallPhase.connecting
                  ? null
                  : '${(job.progress * 100).floor()}%',
              child: MotionSurface(
                active: active,
                builder: (_, phase) => TweenAnimationBuilder<double>(
                  tween: Tween(end: job.progress.clamp(0, 1)),
                  duration: const Duration(milliseconds: 260),
                  builder: (_, value, _) => CustomPaint(
                    key: const ValueKey('transfer-wave'),
                    size: const Size(double.infinity, 24),
                    painter: _WavePainter(
                      value,
                      phase,
                      job.phase == InstallPhase.connecting || waiting,
                      color,
                      colors.onSurface.withValues(alpha: .12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              waiting
                  ? '正在等待手环确认安装结果'
                  : job.phase == InstallPhase.connecting
                  ? '请保持手环在附近'
                  : '请保持连接，完成后会自动更新状态',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (job.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${job.error}\n请刷新应用列表确认结果，再决定是否重试。',
                style: TextStyle(fontSize: 12, color: colors.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(
    this.progress,
    this.phase,
    this.indeterminate,
    this.color,
    this.track,
  );
  final double progress, phase;
  final bool indeterminate;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = track
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    final length = size.width * (indeterminate ? .4 : progress);
    final start = indeterminate ? (size.width + length) * phase - length : 0.0;
    final path = Path();
    for (double x = start; x <= start + length; x += 1) {
      final wave = y + math.sin(x / 13 - phase * math.pi * 4) * 3;
      if (x == start) {
        path.moveTo(x, wave);
      } else {
        path.lineTo(x, wave);
      }
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
    canvas.drawCircle(Offset(size.width, y), 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.color != color ||
      old.track != track ||
      old.indeterminate != indeterminate;
}

class MotionPreview extends StatefulWidget {
  const MotionPreview({super.key});
  @override
  State<MotionPreview> createState() => _MotionPreviewState();
}

class _MotionPreviewState extends State<MotionPreview> {
  int _stage = 1;
  @override
  Widget build(BuildContext context) {
    final sample = InstallJob(
      path: '示例应用.rpk',
      deviceId: 'preview-only',
      deviceName: '演示设备 · 不操作真实手环',
    );
    sample.phase = [
      InstallPhase.connecting,
      InstallPhase.installing,
      InstallPhase.installing,
      InstallPhase.succeeded,
      InstallPhase.failed,
    ][_stage.clamp(0, 4)];
    sample.progress = _stage == 1
        ? .68
        : _stage >= 2
        ? 1
        : 0;
    return Scaffold(
      appBar: AppBar(title: const Text('动效预览')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('仅预览界面效果，不连接设备或安装应用。'),
          const SizedBox(height: 24),
          Center(
            child: ConnectionOrbit(
              ready: _stage != 0,
              connecting: _stage == 0,
              battery: 86,
              job: _stage == 5 ? null : sample,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 6; i++)
                ChoiceChip(
                  label: Text(['连接', '传输', '确认', '完成', '失败', '电量'][i]),
                  selected: _stage == i,
                  onSelected: (_) => setState(() => _stage = i),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (_stage != 5) MobileTransferCard(job: sample),
          if (_stage == 5) const Center(child: Text('示例电量 86% · 液面高度对应电量')),
        ],
      ),
    );
  }
}
