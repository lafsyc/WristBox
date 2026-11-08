import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:oronbox/src/core/services/rfcomm_driver.dart';

bool canRetryDeviceConnection(Object error) {
  if (error is SppConnectFailure) return error.retryable;
  if (error is SppBondRemovalFailed) return false;
  if (error is PlatformException) {
    final code = error.code.toUpperCase();
    if (!SppConnectFailure(code).retryable) return false;
  }
  final text = error.toString().toLowerCase();
  return !const [
    'cancelled',
    'canceled',
    'permission',
    'unauthorized',
    'bluetooth_off',
    'bluetooth_disabled',
    'adapter disabled',
    'auth hmac',
    'auth key',
    'authkey',
    'auth confirm rejected',
    'pairing_rejected',
    'pairing_timeout',
    'pairing_failed',
    '已取消',
    '权限不足',
    'key 无效',
  ].any(text.contains);
}

Duration deviceConnectionRetryDelay(int failedAttempts, {double? randomUnit}) {
  final baseMs = min(1500 * (1 << (failedAttempts - 1).clamp(0, 4)), 12000);
  final jitter = (randomUnit ?? Random().nextDouble()).clamp(0.0, 1.0);
  return Duration(milliseconds: (baseMs * (0.8 + jitter * 0.4)).round());
}

/// Polling keeps cancellation responsive during backoff without a new timer
/// ownership mechanism. A cancelled/superseded attempt must never reconnect.
Future<bool> waitForDeviceConnectionRetry(
  Duration delay, {
  required bool Function() isCancelled,
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < delay) {
    if (isCancelled()) return false;
    final remaining = delay - clock.elapsed;
    await Future<void>.delayed(
      remaining < const Duration(milliseconds: 100)
          ? remaining
          : const Duration(milliseconds: 100),
    );
  }
  return !isCancelled();
}
