import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/core/services/rfcomm_driver.dart';
import 'package:oronbox/src/features/devices/domain/connection_retry_policy.dart';
import 'package:oronbox/steadylink/error_message.dart';

void main() {
  test('actionable pairing, permission and key errors never auto retry', () {
    for (final code in [
      'PAIRING_REJECTED',
      'PAIRING_FAILED',
      'PAIRING_TIMEOUT',
      'BLUETOOTH_PERMISSION_DENIED',
      'BLUETOOTH_OFF',
      'CONNECT_CANCELLED',
    ]) {
      expect(
        canRetryDeviceConnection(SppConnectFailure(code)),
        isFalse,
        reason: code,
      );
      expect(
        canRetryDeviceConnection(PlatformException(code: code)),
        isFalse,
        reason: code,
      );
    }
    expect(
      canRetryDeviceConnection(ArgumentError('Auth HMAC mismatch')),
      isFalse,
    );
    expect(
      canRetryDeviceConnection(StateError('auth confirm rejected by device')),
      isFalse,
    );
    expect(
      canRetryDeviceConnection(const SppConnectFailure('CONNECT_FAILED')),
      isTrue,
    );
    expect(canRetryDeviceConnection(TimeoutException('socket')), isTrue);
  });

  test(
    'backoff increases, is bounded, and has deterministic jitter limits',
    () {
      expect(
        deviceConnectionRetryDelay(1, randomUnit: 0),
        const Duration(milliseconds: 1200),
      );
      expect(
        deviceConnectionRetryDelay(1, randomUnit: 1),
        const Duration(milliseconds: 1800),
      );
      expect(
        deviceConnectionRetryDelay(2, randomUnit: .5),
        const Duration(seconds: 3),
      );
      expect(
        deviceConnectionRetryDelay(100, randomUnit: .5),
        const Duration(seconds: 12),
      );
    },
  );

  test(
    'cancellation during backoff exits before another attempt can start',
    () async {
      var cancelled = false;
      final watch = Stopwatch()..start();
      final wait = waitForDeviceConnectionRetry(
        const Duration(seconds: 10),
        isCancelled: () => cancelled,
      );
      cancelled = true;
      expect(await wait, isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    },
  );

  test(
    'pairing timeouts and permission denials have specific Chinese guidance',
    () {
      expect(
        friendlyError(const SppConnectFailure('PAIRING_TIMEOUT')),
        contains('配对确认超时'),
      );
      expect(
        friendlyError(const SppConnectFailure('PAIRING_REJECTED')),
        contains('停止重试'),
      );
      expect(
        friendlyError(const SppConnectFailure('BLUETOOTH_PERMISSION_DENIED')),
        contains('附近的设备'),
      );
    },
  );
}
