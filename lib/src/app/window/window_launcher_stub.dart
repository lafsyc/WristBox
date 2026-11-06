import 'dart:async';

import 'package:oronbox/src/app/window/window_launch_spec.dart';

bool get supportsSecondaryWindows => false;
Stream<List<String>> get primaryLaunchArguments => const Stream.empty();

Future<bool> initializeWindowCoordinator(
  WindowLaunchSpec spec, {
  List<String> launchArguments = const [],
}) async => true;
Future<void> notifySecondaryWindowReady() async {}
Future<bool> openDebugWindow() async => false;
Future<bool> closeDebugWindow() async => false;
Future<bool> openPluginWindow(String pluginId) async => false;
Future<bool> takePluginWindow(String pluginId) async => true;
Future<void> setSecondaryWindowIcon(String? base64Icon) async {}
Future<void> setSecondaryWindowTitle(String title) async {}
Stream<void> get secondaryWindowHandoffs => const Stream<void>.empty();
Future<void> shutdownSecondaryWindows() async {}
Future<void> reportSecondaryWindowBounds({
  required String role,
  required double width,
  required double height,
  required double x,
  required double y,
}) async {}
