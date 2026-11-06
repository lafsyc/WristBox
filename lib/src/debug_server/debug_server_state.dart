import 'debug_server_auth.dart';
import 'debug_server_protocol.dart';

enum DebugServerStatus { stopped, starting, running, stopping, error }

class DebugServerState {
  const DebugServerState({
    this.status = DebugServerStatus.stopped,
    this.info,
    this.addresses = const [],
    this.pendingClients = const [],
    this.authorizedClients = const [],
    this.error,
  });

  final DebugServerStatus status;
  final DebugServerInfo? info;
  final List<String> addresses;
  final List<DebugAuthorizedClient> pendingClients;
  final List<DebugAuthorizedClient> authorizedClients;
  final String? error;

  bool get isRunning => status == DebugServerStatus.running;
  bool get isBusy =>
      status == DebugServerStatus.starting ||
      status == DebugServerStatus.stopping;

  DebugServerState copyWith({
    DebugServerStatus? status,
    DebugServerInfo? info,
    List<String>? addresses,
    List<DebugAuthorizedClient>? pendingClients,
    List<DebugAuthorizedClient>? authorizedClients,
    String? error,
    bool clearInfo = false,
    bool clearError = false,
  }) {
    return DebugServerState(
      status: status ?? this.status,
      info: clearInfo ? null : info ?? this.info,
      addresses: addresses ?? this.addresses,
      pendingClients: pendingClients ?? this.pendingClients,
      authorizedClients: authorizedClients ?? this.authorizedClients,
      error: clearError ? null : error ?? this.error,
    );
  }
}
