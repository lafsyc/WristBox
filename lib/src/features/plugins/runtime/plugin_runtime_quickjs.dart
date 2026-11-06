import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quickjs_engine/quickjs_engine.dart';

import 'plugin_runtime.dart';

({bool succeeded, String encodedPayload}) encodeQuickJsHostSettlement(
  bool succeeded,
  Object? payload,
) {
  try {
    return (succeeded: succeeded, encodedPayload: jsonEncode(payload));
  } catch (error) {
    return (
      succeeded: false,
      encodedPayload: jsonEncode('Host result serialization failed: $error'),
    );
  }
}

PluginRuntime createPluginRuntime() => _QuickJsPluginRuntime();

class _QuickJsPluginRuntime implements PluginRuntime {
  QuickJsRuntime2? _runtime;
  PluginHostCall? _hostCall;
  final _timers = <int, Timer>{};
  final _hostRequests = <String>{};

  @override
  Map<String, Object?> get diagnostics => {
    'engine': 'quickjs',
    'running': _runtime != null,
    'timers': _timers.length,
  };

  @override
  Future<void> start({
    required String pluginId,
    required String pluginName,
    required String pluginVersion,
    required String runtimeVersion,
    required Uint8List entryBytes,
    required String bootstrap,
    required PluginHostCall hostCall,
  }) async {
    await close();
    final runtime = QuickJsRuntime2(
      stackSize: 1024 * 1024,
      // The native bridge does not export jsSetMemoryLimit, even though the
      // Dart FFI surface declares it. Keep memory limits disabled until the
      // upstream bridge exports the symbol on every platform.
      memoryLimit: 0,
      timeout: 10 * 1000,
      hostPromiseRejectionHandler: (reason) {
        unawaited(
          Future.sync(
            () => hostCall('runtime.reportError', [reason.toString()]),
          ).then<void>((_) {}, onError: (_, _) {}),
        );
      },
    );
    _runtime = runtime;
    _hostCall = hostCall;

    JavascriptRuntime.channelFunctionsRegistered[runtime
        .getEngineInstanceId()]!['OronBoxHost'] = (dynamic message) {
      final json = (message as Map).cast<String, Object?>();
      final requestId = json['requestId']?.toString() ?? '';
      final method = json['method']?.toString() ?? '';
      final arguments = (json['args'] as List?)?.cast<Object?>() ?? const [];
      if (method == 'runtime.setTimer') {
        _scheduleHostRequest(runtime, requestId, () => _setTimer(arguments));
        return null;
      }
      if (method == 'runtime.clearTimer') {
        _scheduleHostRequest(runtime, requestId, () => _clearTimer(arguments));
        return null;
      }
      _scheduleHostRequest(
        runtime,
        requestId,
        () => hostCall(method, arguments),
      );
      return null;
    };

    if (bootstrap.isNotEmpty) {
      _evaluate(runtime, bootstrap, name: 'oronbox_plugin_host.js');
      _evaluate(
        runtime,
        '__zbSetRuntimeGlobals('
        '${jsonEncode(pluginId)}, '
        '${jsonEncode(pluginName)}, '
        '${jsonEncode(pluginVersion)}, '
        '${jsonEncode(runtimeVersion)})',
        name: 'oronbox_plugin_globals.js',
      );
    }
    _evaluate(runtime, utf8.decode(entryBytes), name: '$pluginId/main.js');
    await _runOperation(runtime, '__zbStartPlugin()');
  }

  @override
  Future<void> invokeCallback(String callbackId, [Object? value]) async {
    await invokeRegistered(callbackId, value == null ? const [] : [value]);
  }

  @override
  Future<Object?> invokeRegistered(
    String callbackId,
    List<Object?> arguments,
  ) async {
    final runtime = _requiredRuntime;
    return _runOperation(
      runtime,
      '__zbInvokeRegistered('
      '${jsonEncode(callbackId)}, ${jsonEncode(arguments)})',
    );
  }

  @override
  Future<void> dispatchEvent(String name, String payload) async {
    final runtime = _requiredRuntime;
    await _runOperation(
      runtime,
      '__zbDispatchEvent(${jsonEncode(name)}, ${jsonEncode(payload)})',
    );
  }

  @override
  Future<void> close() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    final runtime = _runtime;
    if (runtime == null) return;
    if (_hostRequests.isNotEmpty) {
      final result = runtime.evaluate(
        '__zbRejectAllHostRequests("Plugin runtime closed")',
      );
      if (!result.isError) runtime.dispatch();
      _hostRequests.clear();
    }
    _hostCall = null;
    _runtime = null;
    JavascriptRuntime.channelFunctionsRegistered.remove(
      runtime.getEngineInstanceId(),
    );
    runtime.dispose();
  }

  QuickJsRuntime2 get _requiredRuntime {
    final runtime = _runtime;
    if (runtime == null) throw StateError('Plugin is not running');
    return runtime;
  }

  void _scheduleHostRequest(
    QuickJsRuntime2 runtime,
    String requestId,
    FutureOr<Object?> Function() operation,
  ) {
    if (requestId.isEmpty) return;
    _hostRequests.add(requestId);
    scheduleMicrotask(() {
      Future<Object?>.sync(operation)
          .timeout(const Duration(seconds: 60))
          .then(
            (value) {
              _hostRequests.remove(requestId);
              _settleHostRequest(runtime, requestId, true, value);
            },
            onError: (Object error, StackTrace _) {
              _hostRequests.remove(requestId);
              _settleHostRequest(runtime, requestId, false, error.toString());
            },
          );
    });
  }

  void _settleHostRequest(
    QuickJsRuntime2 runtime,
    String requestId,
    bool succeeded,
    Object? payload,
  ) {
    if (!identical(_runtime, runtime)) return;
    try {
      final settlement = encodeQuickJsHostSettlement(succeeded, payload);
      final result = runtime.evaluate(
        '__zbSettleHostRequest('
        '${jsonEncode(requestId)}, ${settlement.succeeded}, '
        '${settlement.encodedPayload})',
      );
      if (result.isError) {
        throw StateError(result.stringResult);
      }
      runtime.dispatch();
    } catch (error) {
      unawaited(
        Future.sync(
          () => _hostCall?.call('runtime.reportError', [error.toString()]),
        ).then<void>((_) {}, onError: (_, _) {}),
      );
    }
  }

  void _evaluate(
    QuickJsRuntime2 runtime,
    String source, {
    required String name,
  }) {
    final result = runtime.evaluate(source, name: name);
    if (result.isError) throw StateError(result.stringResult);
  }

  Future<Object?> _runOperation(
    QuickJsRuntime2 runtime,
    String expression,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    final started = runtime.evaluate('__zbBeginOperation(() => ($expression))');
    if (started.isError) throw StateError(started.stringResult);
    final operationId = started.rawResult;
    if (operationId is! num) {
      throw StateError('Plugin operation did not return an operation ID');
    }
    while (identical(_runtime, runtime)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Plugin operation timed out');
      }
      await runtime.dispatch();
      final polled = runtime.evaluate(
        '__zbPollOperation(${operationId.toInt()})',
      );
      if (polled.isError) throw StateError(polled.stringResult);
      final status = (jsonDecode(polled.stringResult) as Map)
          .cast<String, Object?>();
      switch (status['state']) {
        case 'fulfilled':
          return status['value'];
        case 'rejected':
          throw StateError(status['error']?.toString() ?? 'Plugin failed');
        case 'missing':
          throw StateError('Plugin operation disappeared');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('Plugin was closed before the operation completed');
  }

  Object? _setTimer(List<Object?> arguments) {
    final id = (arguments.firstOrNull as num?)?.toInt();
    if (id == null) throw const FormatException('Timer ID is required');
    final milliseconds = ((arguments.elementAtOrNull(1) as num?)?.toInt() ?? 0)
        .clamp(0, 0x7fffffff);
    final repeat = arguments.elementAtOrNull(2) == true;
    _timers.remove(id)?.cancel();
    final duration = Duration(
      milliseconds: repeat && milliseconds == 0 ? 1 : milliseconds,
    );
    _timers[id] = repeat
        ? Timer.periodic(duration, (_) => unawaited(_fireTimer(id)))
        : Timer(duration, () {
            _timers.remove(id);
            unawaited(_fireTimer(id));
          });
    return null;
  }

  Object? _clearTimer(List<Object?> arguments) {
    final id = (arguments.firstOrNull as num?)?.toInt();
    if (id != null) _timers.remove(id)?.cancel();
    return null;
  }

  Future<void> _fireTimer(int id) async {
    final runtime = _runtime;
    if (runtime == null) return;
    try {
      await _runOperation(runtime, '__zbFireTimer($id)');
    } catch (error) {
      await Future.sync(
        () => _hostCall?.call('log.error', ['Timer $id failed: $error']),
      );
    }
  }
}
