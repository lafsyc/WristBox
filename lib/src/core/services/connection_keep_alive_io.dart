import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('oronbox/background_tasks');

/// Android-only: keeps a connectedDevice foreground service (and therefore
/// the process and BLE link) alive while a device is connected. No-op on
/// every other platform.
Future<void> beginConnectionKeepAlive(String label, {int? battery}) async {
  if (!Platform.isAndroid) return;
  await _channel.invokeMethod<void>('beginConnection', {
    'label': label,
    'battery': battery,
  });
}

Future<void> updateConnectionKeepAlive(String label, {int? battery}) async {
  if (!Platform.isAndroid) return;
  await _channel.invokeMethod<void>('updateConnection', {
    'label': label,
    'battery': battery,
  });
}

Future<void> endConnectionKeepAlive() async {
  if (!Platform.isAndroid) return;
  await _channel.invokeMethod<void>('endConnection');
}
