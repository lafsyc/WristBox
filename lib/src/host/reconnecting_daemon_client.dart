import 'dart:async';
import 'dart:io';

import 'package:oronbox/src/command_bus/command_observability.dart';
import 'package:oronbox/src/commands/command_protocol.dart';
import 'package:oronbox/src/core/logging/diagnostic_event.dart';
import 'package:oronbox/src/core/logging/logging_service.dart';
import 'package:oronbox/src/daemon/daemon_client.dart';

/// A stable GUI-side adapter over daemon process restarts
class ReconnectingDaemonClient implements OronBoxCommandBus {
  static final _log = getLogger('DaemonClient');

  OronBoxDaemonClient? _client;
  StreamSubscription<CommandEvent>? _subscription;
  Future<OronBoxDaemonClient>? _connecting;
  Timer? _reconnectTimer;
  final _events = StreamController<CommandEvent>.broadcast();
  StreamSubscription<DiagnosticEvent>? _diagnosticSubscription;
  late final Future<CommandResult> _diagnosticSessionReady;
  final _diagnosticSessionId = '$pid-${DateTime.now().microsecondsSinceEpoch}';
  final _diagnosticSessionStartedAt = DateTime.now();
  bool _closed = false;
  DateTime? _lastReconnectWarning;
  int _reconnectAttempts = 0;

  ReconnectingDaemonClient() {
    if (diagnosticProcess == DiagnosticProcess.frontend) {
      _diagnosticSessionReady = execute(
        OronBoxCommand(
          method: 'debug.session.start',
          params: {
            'sessionId': _diagnosticSessionId,
            'startedAt': _diagnosticSessionStartedAt.toIso8601String(),
          },
        ),
      );
    } else {
      _diagnosticSessionReady = Future.value(const CommandResult.success());
    }
    if (diagnosticProcess == DiagnosticProcess.frontend ||
        diagnosticProcess == DiagnosticProcess.pluginWindow) {
      _diagnosticSubscription = oronBoxDiagnosticStream.listen((event) {
        unawaited(_publishDiagnostic(event));
      });
    }
    scheduleMicrotask(_reconnect);
  }

  Future<void> _publishDiagnostic(DiagnosticEvent event) async {
    try {
      await _diagnosticSessionReady;
      await execute(
        OronBoxCommand(
          method: 'debug.publish',
          params: {'sessionId': _diagnosticSessionId, 'record': event.toJson()},
        ),
      );
    } catch (_) {
      // Diagnostic forwarding must never affect the application itself.
    }
  }

  @override
  Stream<CommandEvent> get events => _events.stream;

  @override
  Future<CommandResult> execute(OronBoxCommand command) async {
    final observable = isObservableCommand(command.method);
    final stopwatch = Stopwatch()..start();
    var retried = false;
    try {
      var client = await _ensureClient();
      var result = await client.execute(command);
      if (result.error?.code == 'daemon_disconnected') {
        retried = true;
        await _detach(client);
        client = await _ensureClient();
        result = await client.execute(command);
      }
      stopwatch.stop();
      if (observable && !result.ok) {
        logDiagnostic(
          _log,
          Level.WARNING,
          'Daemon command rejected',
          fields: {
            'method': command.method,
            'durationMs': stopwatch.elapsedMilliseconds,
            'retried': retried,
            'code': result.error!.code,
          },
          error: result.error!.message,
        );
      }
      return result;
    } catch (error, stackTrace) {
      stopwatch.stop();
      if (observable) {
        logDiagnostic(
          _log,
          Level.SEVERE,
          'Daemon command failed',
          fields: {
            'method': command.method,
            'durationMs': stopwatch.elapsedMilliseconds,
            'retried': retried,
          },
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<OronBoxDaemonClient> _ensureClient() {
    final current = _client;
    if (current != null) return Future.value(current);
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<OronBoxDaemonClient> _connect() async {
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        final client = await _attach(await OronBoxDaemonClient.connect());
        logDiagnostic(
          _log,
          Level.INFO,
          'Connected to OronBox daemon',
          fields: {
            'durationMs': stopwatch.elapsedMilliseconds,
            'autostarted': attempt > 0,
          },
        );
        return client;
      } catch (error) {
        lastError = error;
        logDiagnostic(
          _log,
          Level.FINE,
          'OronBox daemon connect attempt failed',
          fields: {'attempt': attempt + 1},
          error: error,
        );
        if (attempt == 0) await _startDaemon();
      }
    }
    throw StateError('Unable to start OronBox daemon: $lastError');
  }

  Future<void> _startDaemon() async {
    final stopwatch = Stopwatch()..start();
    logDiagnostic(_log, Level.INFO, 'Starting OronBox daemon');
    await Process.start(Platform.resolvedExecutable, const [
      '--nogui',
      'daemon',
      'run',
    ], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (var attempt = 0; attempt < 49; attempt += 1) {
      try {
        final client = await OronBoxDaemonClient.connect(
          timeout: const Duration(milliseconds: 250),
        );
        await client.close();
        logDiagnostic(
          _log,
          Level.INFO,
          'OronBox daemon became ready',
          fields: {'durationMs': stopwatch.elapsedMilliseconds},
        );
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<OronBoxDaemonClient> _attach(OronBoxDaemonClient client) async {
    await _subscription?.cancel();
    if (_closed) {
      await client.close();
      throw StateError('Application host client is closed');
    }
    _client = client;
    _subscription = client.events.listen((event) {
      if (event.event == 'daemon.disconnected') {
        unawaited(_detach(client));
        return;
      }
      _events.add(event);
    }, onDone: () => unawaited(_detach(client)));
    return client;
  }

  Future<void> _detach(OronBoxDaemonClient client) async {
    if (!identical(_client, client)) return;
    _client = null;
    logDiagnostic(_log, Level.WARNING, 'Disconnected from OronBox daemon');
    await _subscription?.cancel();
    _subscription = null;
    if (!_closed) {
      _events.add(const CommandEvent('host.disconnected'));
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(milliseconds: 500), _reconnect);
    }
  }

  Future<void> _reconnect() async {
    if (_closed || _client != null || _connecting != null) return;
    try {
      await _ensureClient();
      _reconnectAttempts = 0;
      if (!_closed) _events.add(const CommandEvent('host.connected'));
    } catch (error) {
      if (_closed) return;
      _reconnectAttempts += 1;
      const backoff = Duration(seconds: 2);
      logDiagnostic(
        _log,
        Level.FINE,
        'OronBox daemon reconnect failed; retrying',
        fields: {
          'attempt': _reconnectAttempts,
          'backoffMs': backoff.inMilliseconds,
        },
        error: error,
      );
      final now = DateTime.now();
      if (_lastReconnectWarning == null ||
          now.difference(_lastReconnectWarning!) >
              const Duration(seconds: 30)) {
        _lastReconnectWarning = now;
        logDiagnostic(
          _log,
          Level.WARNING,
          'OronBox daemon reconnect deferred',
          fields: {
            'attempt': _reconnectAttempts,
            'backoffMs': backoff.inMilliseconds,
          },
          error: error,
        );
      }
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(backoff, _reconnect);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _diagnosticSubscription?.cancel();
    await _client?.close();
    await _events.close();
  }
}
