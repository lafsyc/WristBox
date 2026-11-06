import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_message.dart';

enum InstallPhase {
  queued,
  connecting,
  installing,
  succeeded,
  failed,
  cancelled,
}

class InstallJob {
  InstallJob({
    required this.path,
    required this.deviceId,
    required this.deviceName,
  });
  final String path;
  final String deviceId;
  final String deviceName;
  InstallPhase phase = InstallPhase.queued;
  double progress = 0;
  String? error;
  String get fileName => path.replaceAll('\\', '/').split('/').last;
}

/// The physical connection has one owner. A queued install never reads a
/// mutable UI selection, and selecting another device cannot interrupt it.
class OperationQueue extends ChangeNotifier {
  OperationQueue({required this.connect, required this.install});
  final Future<void> Function(String deviceId) connect;
  final Future<void> Function(InstallJob job, void Function(double) progress)
  install;
  final List<InstallJob> jobs = [];
  Future<void>? _running;
  String? _selected;
  int _selectionRevision = 0;
  bool _disposed = false;
  String? connectionError;
  String? activeDevice;
  bool get busy => _running != null;
  Future<void> get settled => _running ?? Future<void>.value();

  /// Protect saved credentials without opening a Bluetooth connection.
  Future<T> maintain<T>(Future<T> Function() action) async {
    if (busy) throw StateError('请等待当前连接或安装任务完成，再修改设备资料');
    final completer = Completer<void>();
    final revision = _selectionRevision;
    _running = completer.future;
    _notify();
    try {
      return await action();
    } finally {
      _running = null;
      completer.complete();
      _notify();
      if (jobs.any((j) => j.phase == InstallPhase.queued) ||
          (_selected != null && revision != _selectionRevision)) {
        _start();
      }
    }
  }

  void forget(String deviceId) {
    if (_selected == deviceId) {
      _selected = null;
      _selectionRevision++;
      connectionError = null;
    }
    for (final job in jobs.where((j) => j.deviceId == deviceId)) {
      if (job.phase == InstallPhase.queued) job.phase = InstallPhase.cancelled;
    }
    _notify();
  }

  void select(String deviceId) {
    _selected = deviceId;
    _selectionRevision++;
    connectionError = null;
    _start();
  }

  void add(Iterable<InstallJob> incoming) {
    for (final job in incoming) {
      if (!jobs.any(
        (j) =>
            j.deviceId == job.deviceId &&
            j.path == job.path &&
            (j.phase == InstallPhase.queued ||
                j.phase == InstallPhase.connecting ||
                j.phase == InstallPhase.installing),
      )) {
        jobs.add(job);
      }
    }
    _start();
  }

  void cancel(InstallJob job) {
    if (job.phase != InstallPhase.queued) return;
    job.phase = InstallPhase.cancelled;
    _notify();
  }

  void clearFinished() {
    jobs.removeWhere(
      (j) => const [
        InstallPhase.succeeded,
        InstallPhase.failed,
        InstallPhase.cancelled,
      ].contains(j.phase),
    );
    _notify();
  }

  Future<void> exclusive(
    String deviceId,
    Future<void> Function() action,
  ) async {
    if (busy) throw StateError('请等待当前连接或安装任务完成');
    final completer = Completer<void>();
    _running = completer.future;
    activeDevice = deviceId;
    _notify();
    try {
      await connect(deviceId);
      await action();
    } finally {
      activeDevice = null;
      _running = null;
      completer.complete();
      _notify();
      if (jobs.any((j) => j.phase == InstallPhase.queued) ||
          (_selected != null && _selected != deviceId)) {
        _start();
      }
    }
  }

  void _start() {
    if (_disposed || busy) {
      _notify();
      return;
    }
    final completer = Completer<void>();
    _running = completer.future;
    _notify();
    unawaited(
      _drain().whenComplete(() {
        _running = null;
        activeDevice = null;
        completer.complete();
        _notify();
      }),
    );
  }

  Future<void> _drain() async {
    while (!_disposed) {
      final pending = jobs.where((j) => j.phase == InstallPhase.queued);
      if (pending.isNotEmpty) {
        final job = pending.first;
        activeDevice = job.deviceId;
        job.phase = InstallPhase.connecting;
        _notify();
        try {
          await connect(job.deviceId);
          job.phase = InstallPhase.installing;
          _notify();
          await install(job, (progress) {
            job.progress = progress.clamp(0, 1);
            _notify();
          });
          job.progress = 1;
          job.phase = InstallPhase.succeeded;
        } catch (error) {
          job.error = friendlyError(error, installing: true);
          job.phase = InstallPhase.failed;
          // Never replay an installation with an unknown result automatically.
        }
        _notify();
        continue;
      }
      final target = _selected;
      final revision = _selectionRevision;
      if (target == null) return;
      activeDevice = target;
      try {
        await connect(target);
        connectionError = null;
      } catch (error) {
        connectionError = friendlyError(error);
      }
      _notify();
      if (revision == _selectionRevision &&
          !jobs.any((j) => j.phase == InstallPhase.queued)) {
        return;
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
