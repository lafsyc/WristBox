import 'package:flutter/material.dart';

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';

const darkThemePreference = 'steadylink.dark_theme';

Future<void> updateTitleBar(bool dark) async {
  if (!Platform.isWindows) return;
  try {
    await const MethodChannel('steadylink/appearance')
        .invokeMethod<void>('setDark', dark);
  } on MissingPluginException {
    // Widget previews have no native window.
  } on PlatformException catch (error) {
    debugPrint('Title bar appearance could not be updated: ${error.code}');
  }
}

final darkThemeProvider = NotifierProvider<Appearance, bool>(Appearance.new);

class Appearance extends Notifier<bool> {
  @override
  bool build() {
    final prefs = SharedPrefsService.instance;
    return prefs.isInitialized
        ? prefs.getBool(darkThemePreference) ?? true
        : true;
  }

  Future<void> toggle() async {
    state = !state;
    final dark = state;
    final prefs = SharedPrefsService.instance;
    if (prefs.isInitialized &&
        !await prefs.setBool(darkThemePreference, dark)) {
      throw StateError('主题已切换，但保存失败，下次启动可能恢复原主题');
    }
    if (dark == state) {
      await updateTitleBar(dark);
    }
  }
}
