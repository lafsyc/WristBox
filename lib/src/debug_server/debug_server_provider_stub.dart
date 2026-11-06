import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debug_server_state.dart';

final debugServerProvider =
    NotifierProvider<DebugServerController, DebugServerState>(
      DebugServerController.new,
    );

class DebugServerController extends Notifier<DebugServerState> {
  @override
  DebugServerState build() => const DebugServerState();

  Future<void> start() async {}
  Future<void> stop() async {}
  Future<void> approve(String fingerprint) async {}
  Future<void> reject(String fingerprint) async {}
  Future<void> revoke(String fingerprint) async {}
}
