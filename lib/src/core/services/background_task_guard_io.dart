import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('oronbox/background_tasks');

class BackgroundTaskHandle {
  const BackgroundTaskHandle(this.id);
  final int? id;

  Future<void> end() async {
    if (id == null || (!Platform.isAndroid && !Platform.isIOS)) return;
    await _channel.invokeMethod<void>('end', {'id': id});
  }
}

Future<BackgroundTaskHandle> beginBackgroundTask(String label) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return const BackgroundTaskHandle(null);
  }
  final id = await _channel.invokeMethod<int>('begin', {'label': label});
  return BackgroundTaskHandle(id);
}
