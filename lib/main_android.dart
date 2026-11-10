import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/src/core/providers/app_settings_providers.dart';

import 'steadylink/mobile_app.dart';

/// Android distribution entry. Desktop UI is not part of the public checkout.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SharedPrefsService.instance.init();
    await initializeAndroidConnectionPreferences();
    await SharedPrefsService.instance.setBool('auto_reconnect', false);
    await SharedPrefsService.instance.setBool('remove_bond_before_spp', false);
    runApp(const ProviderScope(child: SteadyMobileApp()));
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ListView(
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 20),
                  const Text('WristBox 启动遇到问题', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 12),
                  SelectableText(error.toString()),
                  const SizedBox(height: 16),
                  const Text('请重新打开应用；如仍失败，请保留此错误信息。'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
