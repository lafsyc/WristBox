import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/command_bus/local_command_bus.dart';
import 'package:oronbox/src/commands/command_protocol.dart';
import 'package:oronbox/src/host/application_host.dart';

OronBoxCommandBus createGuiApplicationHost() {
  final container = ProviderContainer();
  return ApplicationHost(
    LocalCommandBus(container),
    onClose: container.dispose,
  );
}
