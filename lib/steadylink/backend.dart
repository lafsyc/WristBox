import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/core/logging/logging_service.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/features/resources/services/resource_payload_analyzer.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart'
    show ProtocolState;

import 'operation_queue.dart';
import 'cloud_store.dart';
import 'store_models.dart';
import 'local_package.dart';

import 'package:oronbox/src/features/accounts/models/mi_account_models.dart';

class ActivationCancelled implements Exception {}

class SteadyBackend {
  SteadyBackend(this.ref) {
    queue = OperationQueue(connect: ensureConnected, install: _install);
  }
  final Ref ref;
  late final OperationQueue queue;
  int _connectCancelRevision = 0;
  Future<void> cancelConnection() async {
    if (!state.connecting) return;
    _connectCancelRevision++;
    await manager.cancelConnect();
  }

  DeviceManager get manager => ref.read(deviceManagerProvider.notifier);
  DeviceManagerState get state => ref.read(deviceManagerProvider);
  MiWearState device(String id) =>
      state.pairedDevices.firstWhere((d) => d.addr == id);

  Future<void> importDevice(MiWearState value) => queue.maintain(() async {
    await manager.importSharedDevice(value);
    queue.connectionError = null;
  });

  Future<int> syncDevices(List<MiCloudDevice> values) =>
      queue.maintain(() async {
        final count = await manager.importMiCloudDevices(values);
        queue.connectionError = null;
        return count;
      });

  Future<void> updateKey(String id, String key) => queue.maintain(() async {
    await manager.importSharedDevice(device(id).copyWith(authkey: key));
    queue.connectionError = null;
  });

  Future<void> removeDevice(String id) => queue.maintain(() async {
    await manager.removeDevice(id);
    queue.forget(id);
  });

  Future<void> ensureConnected(String id) async {
    final target = device(id);
    if (state.currentDevice?.addr == id &&
        state.protocolState == ProtocolState.ready) {
      return;
    }
    final key = target.authkey;
    if (key == null || !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(key)) {
      throw StateError('设备 Key 无效，请重新同步小米账号');
    }
    // Do not enter nested transport retries when Windows has no usable radio.
    // Check anew on every user attempt so enabling Bluetooth needs no restart.
    if (Platform.isWindows || Platform.isAndroid) {
      try {
        await const MethodChannel('oronbox/classic_spp')
            .invokeMethod<void>('checkAvailability');
      } on PlatformException catch (error) {
        throw StateError(error.message ?? '蓝牙不可用，请检查权限和蓝牙开关后重试');
      }
    }
    // Android already retries in the transport manager. Do not cancel the
    // user's pairing confirmation with an overlapping outer retry cycle.
    final attempts = Platform.isAndroid ? 1 : 2;
    final cancelRevision = _connectCancelRevision;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        await manager
            .connect(
              target.addr,
              target.name,
              key,
              connectType: target.connectType,
            )
            .timeout(Duration(seconds: Platform.isAndroid ? 240 : 55));
        if (cancelRevision != _connectCancelRevision) throw StateError('已取消连接');
        if (state.currentDevice?.addr == id &&
            state.protocolState == ProtocolState.ready) {
          return;
        }
        throw StateError(state.error ?? '设备认证未完成');
      } catch (_) {
        await manager.cancelConnect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
        await manager.disconnect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
        if (cancelRevision != _connectCancelRevision) throw StateError('已取消连接');
        if (attempt == attempts - 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
  }

  Future<void> _install(InstallJob job, void Function(double) progress) async {
    final file = File(job.path);
    if (!isLocalInstallFile(job.path)) {
      throw StateError('请选择 RPK 或 BIN 安装包');
    }
    final size = await file.length();
    if (size == 0 || size > 64 * 1024 * 1024) {
      throw StateError('安装包大小必须在 0–64 MB 之间');
    }
    final analysis = analyzeLocalPackage(
      job.fileName,
      await file.readAsBytes(),
    );
    if (state.currentDevice?.addr != job.deviceId ||
        state.protocolState != ProtocolState.ready) {
      throw StateError('目标设备连接已改变，请重新连接后重试');
    }
    await manager.setBatteryRefreshPaused(true);
    try {
      final transfer = analysis.type == LocalDeviceInstallType.watchface
          ? manager.installWatchface(
              analysis.payload,
              watchfaceId: analysis.identifier!,
              onProgress: progress,
            )
          : manager.installApp(
              analysis.payload,
              packageName: analysis.identifier!,
              onProgress: progress,
            );
      await transfer.timeout(const Duration(minutes: 5));
    } catch (_) {
      // Tear down a timed-out session; Future.timeout alone doesn't stop it.
      await manager.disconnect().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      rethrow;
    } finally {
      await manager.setBatteryRefreshPaused(false);
    }
    // Installation acknowledgement is authoritative. List refresh failure is
    // separate and must not turn a successful install into a retryable failure.
    try {
      await (analysis.type == LocalDeviceInstallType.watchface
              ? manager.fetchWatchfaces()
              : manager.fetchApps())
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> installCloud(
    CloudStore store,
    String resourceId,
    String deviceId,
    void Function(double) progress, {
    required String expectedModel,
    String? expectedGrantId,
    void Function(String)? onStage,
    Future<bool> Function(String model, String serial)? onActivationRequired,
  }) => queue.exclusive(deviceId, () async {
    CloudPackageSource? source;
    var isWatchface = false;
    var success = false;
    await manager.setBatteryRefreshPaused(true);
    try {
      onStage?.call('正在读取手环身份信息');
      await manager.fetchSystemInfo().timeout(const Duration(seconds: 20));
      final model = storeModelForDevice(
        state.currentDevice,
        systemInfo: state.systemInfo,
      );
      if (state.currentDevice?.addr != deviceId ||
          model == null ||
          model != expectedModel) {
        throw StateError('连接后的手环型号与所选版本不一致，请刷新商店重新匹配');
      }
      final serial = state.systemInfo?.serialNumber.trim().toUpperCase() ?? '';
      final firmware = state.systemInfo?.firmwareVersion.trim() ?? '';
      void checkTarget() {
        if ((state.systemInfo?.firmwareVersion.trim() ?? '') != firmware ||
            state.currentDevice?.addr != deviceId ||
            state.protocolState != ProtocolState.ready ||
            (state.systemInfo?.serialNumber.trim().toUpperCase() ?? '') !=
                serial ||
            storeModelForDevice(
                  state.currentDevice,
                  systemInfo: state.systemInfo,
                ) !=
                model) {
          throw StateError('设备连接或身份已改变，请重新连接目标手环后再试');
        }
      }

      checkTarget();
      onStage?.call('正在校验型号、固件和资源授权');
      final entitlement = await store.activationStatus(
        resourceId,
        model,
        serial,
        grantId: expectedGrantId,
        firmware: firmware,
      );
      checkTarget();
      if (entitlement['required'] == true && entitlement['activated'] != true) {
        if (onActivationRequired == null) {
          throw StateError('此资源需要卡密激活，请打开应用详情激活');
        }
        onStage?.call('等待卡密激活');
        if (!await onActivationRequired(model, serial)) {
          throw ActivationCancelled();
        }
        checkTarget();
      }
      // A card dialog may remain open for minutes. Re-read the authenticated
      // connection rather than trusting the identity cached before the dialog.
      await manager.fetchSystemInfo().timeout(const Duration(seconds: 20));
      checkTarget();
      onStage?.call('正在建立安全安装会话');
      source = await store.open(
        resourceId,
        deviceId,
        model,
        serial: serial,
        activationRequired: entitlement['required'] == true,
        grantId: expectedGrantId,
        firmware: firmware,
      );
      checkTarget();
      onStage?.call('安全校验完成，正在准备手环接收');
      final type = source.manifest['installType'] ?? 'app';
      if (type != 'app' && type != 'watchface') {
        throw StateError('此安装包类型暂不支持，请更新 WristBox');
      }
      isWatchface = type == 'watchface';
      if (expectedGrantId != null && !isWatchface) {
        onStage?.call('正在核对已安装版本');
        await manager.fetchApps().timeout(const Duration(seconds: 15));
        checkTarget();
        final installed = state.apps
            .where((a) => a.packageName == source!.manifest['packageName'])
            .firstOrNull;
        if (installed != null &&
            installed.versionCode > (source.manifest['versionCode'] as int)) {
          throw StateError('手环已安装更高版本，无需降级安装');
        }
      }
      void onProgress(double value) {
        checkTarget();
        progress(value);
      }

      final transfer = isWatchface
          ? manager.installCloudWatchface(
              source,
              deviceId: deviceId,
              watchfaceId: source.manifest['watchfaceId'] as String,
              onProgress: onProgress,
            )
          : manager.installCloudApp(
              source,
              deviceId: deviceId,
              packageName: source.manifest['packageName'] as String,
              versionCode: source.manifest['versionCode'] as int,
              onProgress: onProgress,
            );
      await transfer.timeout(const Duration(minutes: 18));
      success = true;
    } catch (error) {
      // Teardown must not replace the actual installation error or prevent the
      // Bluetooth session from resetting after a failed first transfer.
      getLogger('CloudInstall').warning('Install failed: ${error.runtimeType}');
      try {
        await source?.close();
      } catch (_) {}
      if (source != null || error is TimeoutException) {
        try {
          await manager.disconnect().timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      rethrow;
    } finally {
      try {
        await source?.close();
      } catch (_) {}
      try {
        await manager.setBatteryRefreshPaused(false);
      } catch (_) {}
      try {
        await source?.finish(success);
      } catch (_) {}
    }
    try {
      await (isWatchface ? manager.fetchWatchfaces() : manager.fetchApps())
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  });

  Future<void> refresh(String id) => queue.exclusive(id, () async {
    try {
      await manager.refreshDeviceData().timeout(const Duration(seconds: 20));
      await manager.fetchApps().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      await manager.disconnect();
      rethrow;
    }
  });

  Future<void> uninstall(String id, AppInfo app) => queue.exclusive(
    id,
    () async {
      if (!app.canRemove) throw StateError('该应用不允许卸载');
      try {
        await manager.uninstallApp(app).timeout(const Duration(seconds: 30));
        // A sent request is not proof of removal. Query the device before
        // reporting success; never automatically resend an uninstall.
        for (var attempt = 0; attempt < 3; attempt++) {
          await manager.fetchApps().timeout(const Duration(seconds: 15));
          if (!state.apps.any((a) => a.packageName == app.packageName)) return;
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
        throw StateError('设备仍返回该应用，尚未确认卸载完成，请刷新列表后检查');
      } on TimeoutException {
        await manager.disconnect();
        rethrow;
      }
    },
  );
}

final steadyBackendProvider = Provider<SteadyBackend>((ref) {
  final backend = SteadyBackend(ref);
  ref.onDispose(backend.queue.dispose);
  return backend;
});
