import 'package:oronbox/src/core/models/bt_models.dart';

import 'log_key_parser.dart';
import 'store_models.dart';

class LogDeviceChoice {
  const LogDeviceChoice(this.device, this.candidates);
  final MiWearState device;
  final List<LogKeyCandidate> candidates;
}

List<LogDeviceChoice> logDeviceChoices(
  List<LogKeyCandidate> candidates,
  List<MiWearState> known,
) {
  final devices = {for (final d in known) d.addr.toUpperCase(): d};
  for (final c in candidates) {
    if (c.address.isEmpty) continue;
    final model = storeModelForDevice(
      MiWearState(
        name: c.name,
        addr: c.address,
        connectType: 'spp',
        codename: c.model,
      ),
    );
    devices.putIfAbsent(
      c.address,
      () => MiWearState(
        name: c.name.isNotEmpty
            ? c.name
            : storeModelNames[model] ?? '蓝牙设备 ${c.address.substring(12)}',
        addr: c.address,
        connectType: 'spp',
        codename: model,
      ),
    );
  }
  final result = <LogDeviceChoice>[];
  for (final d in devices.values) {
    final exact = candidates
        .where((c) => c.address == d.addr.toUpperCase())
        .toList();
    final possible = candidates
        .where((c) => c.address.isEmpty && logAddressMatches(c, d.addr))
        .toList();
    final unique = <String, LogKeyCandidate>{};
    // Prefer explicit associations; order is only a trial order, not proof of validity.
    for (final c in [...exact.reversed, ...possible.reversed]) {
      unique.putIfAbsent(c.key, () => c);
    }
    if (unique.isNotEmpty) {
      result.add(LogDeviceChoice(d, unique.values.toList()));
    }
  }
  return result;
}

class LogImportCancelled implements Exception {}

class LogImportRestoreFailed implements Exception {}

bool _keyRejected(Object error) {
  final text = error.toString().toLowerCase();
  if ([
    'permission',
    'denied',
    'unauthorized',
    'cancel',
    '取消',
    'timeout',
    'timed out',
    '配对',
  ].any(text.contains)) {
    return false;
  }
  return ['auth', '认证', 'decrypt', 'handshake'].any(text.contains);
}

/// The caller holds the connection queue for the whole operation. Only an
/// authenticated connection finishes the import. Rollback restores the
/// previous device (or removes the temporary new device) on any final failure.
Future<void> verifyLogDeviceChoice({
  required LogDeviceChoice choice,
  required Future<void> Function(MiWearState) save,
  required Future<void> Function(String) connect,
  required Future<void> Function() rollback,
  required bool Function() cancelled,
}) async {
  var changed = false;
  try {
    final keys = choice.candidates.map((c) => c.key).toSet().take(3).toList();
    if (keys.isEmpty) throw StateError('日志中没有可用的连接 Key');
    for (var i = 0; i < keys.length; i++) {
      if (cancelled()) throw LogImportCancelled();
      changed = true;
      await save(choice.device.copyWith(authkey: keys[i]));
      if (cancelled()) throw LogImportCancelled();
      try {
        await connect(choice.device.addr);
        if (cancelled()) throw LogImportCancelled();
        return;
      } catch (error) {
        if (cancelled()) throw LogImportCancelled();
        if (i == keys.length - 1 || !_keyRejected(error)) rethrow;
      }
    }
  } catch (_) {
    if (changed) {
      try {
        await rollback();
      } catch (_) {
        throw LogImportRestoreFailed();
      }
    }
    rethrow;
  }
}
