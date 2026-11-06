import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/backend.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart'
    show ProtocolState;

const target = MiWearState(name: 'Test band', addr: 'AA:BB:CC:DD:EE:01', connectType: 'spp');
const app = AppInfo(
  packageName: 'test.app',
  appName: 'Test app',
  versionCode: 1,
  canRemove: true,
);

class RemovalManager extends LocalDeviceManager {
  RemovalManager(this.removed);
  final bool removed;
  int sends = 0;
  int queries = 0;
  @override
  DeviceManagerState build() => const DeviceManagerState(
    currentDevice: target,
    pairedDevices: [target],
    protocolState: ProtocolState.ready,
    apps: [app],
  );
  @override
  Future<void> uninstallApp(AppInfo app) async {
    sends++;
    state = state.copyWith(apps: []); // Upstream's optimistic update.
  }

  @override
  Future<void> fetchApps() async {
    queries++;
    state = state.copyWith(apps: removed ? [] : [app]);
  }
}

void main() {
  for (final removed in [true, false]) {
    test(
      'uninstall success requires device confirmation (removed: $removed)',
      () async {
        final manager = RemovalManager(removed);
        final container = ProviderContainer(
          overrides: [deviceManagerProvider.overrideWith(() => manager)],
        );
        addTearDown(container.dispose);
        final backend = container.read(steadyBackendProvider);
        final result = backend.uninstall(target.addr, app);
        if (removed) {
          await result;
          expect(manager.queries, 1);
        } else {
          await expectLater(result, throwsStateError);
          expect(manager.queries, 3);
        }
        expect(
          manager.sends,
          1,
        ); // Never resend an uncertain destructive request.
        expect(backend.queue.busy, isFalse);
      },
    );
  }
}
