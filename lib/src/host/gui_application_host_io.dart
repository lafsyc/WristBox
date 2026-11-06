import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/command_bus/local_command_bus.dart';
import 'package:oronbox/src/commands/command_protocol.dart';
import 'package:oronbox/src/core/services/background_task_guard.dart';
import 'package:oronbox/src/host/application_host.dart';
import 'package:oronbox/src/host/reconnecting_daemon_client.dart';

OronBoxCommandBus createGuiApplicationHost() {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    return ReconnectingDaemonClient();
  }
  final container = ProviderContainer();
  return ApplicationHost(
    LocalCommandBus(container),
    onClose: container.dispose,
    beginTaskExecution: (task) async {
      final backgroundTask = await beginBackgroundTask(
        task.command.params['title']?.toString() ?? 'OronBox task',
      );
      return backgroundTask.end;
    },
  );
}
