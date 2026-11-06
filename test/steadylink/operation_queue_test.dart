import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/operation_queue.dart';

InstallJob job(String id, [String file = 'app.rpk']) =>
    InstallJob(path: file, deviceId: id, deviceName: id);
void main() {
  test('switching during upload preserves the installation target', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final events = <String>[];
    final queue = OperationQueue(
      connect: (id) async => events.add('connect:$id'),
      install: (job, progress) async {
        events.add('install:${job.deviceId}');
        started.complete();
        await gate.future;
      },
    );
    addTearDown(queue.dispose);
    final first = job('band9pro');
    queue.add([first]);
    await started.future;
    queue.select('band10');
    queue.select('band11');
    expect(events, ['connect:band9pro', 'install:band9pro']);
    gate.complete();
    await queue.settled;
    expect(events, ['connect:band9pro', 'install:band9pro', 'connect:band11']);
    expect(first.phase, InstallPhase.succeeded);
  });
  test(
    'a failed upload is not replayed and the next device still works',
    () async {
      final installed = <String>[];
      final queue = OperationQueue(
        connect: (_) async {},
        install: (job, _) async {
          installed.add(job.deviceId);
          if (job.deviceId == 'A') throw StateError('link lost');
        },
      );
      addTearDown(queue.dispose);
      final a = job('A'), b = job('B');
      queue.add([a, b]);
      await queue.settled;
      expect(installed, ['A', 'B']);
      expect(a.phase, InstallPhase.failed);
      expect(b.phase, InstallPhase.succeeded);
    },
  );
  test(
    'connection failure never starts transfer; explicit retry recovers',
    () async {
      var available = false;
      var transfers = 0;
      final queue = OperationQueue(
        connect: (_) async {
          if (!available) throw StateError('offline');
        },
        install: (_, _) async {
          transfers++;
        },
      );
      addTearDown(queue.dispose);
      final first = job('A');
      queue.add([first]);
      await queue.settled;
      expect(first.phase, InstallPhase.failed);
      expect(transfers, 0);
      available = true;
      final retry = job('A');
      queue.add([retry]);
      await queue.settled;
      expect(retry.phase, InstallPhase.succeeded);
      expect(transfers, 1);
    },
  );
  test(
    'duplicate drops are coalesced and queued jobs can be cancelled',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final installed = <String>[];
      final queue = OperationQueue(
        connect: (_) async {},
        install: (job, _) async {
          installed.add(job.path);
          started.complete();
          await gate.future;
        },
      );
      addTearDown(queue.dispose);
      final next = job('A', 'other.rpk');
      queue.add([job('A'), job('A'), next]);
      await started.future;
      queue.cancel(next);
      gate.complete();
      await queue.settled;
      expect(queue.jobs.length, 2);
      expect(installed, ['app.rpk']);
      expect(next.phase, InstallPhase.cancelled);
    },
  );
  test(
    'uninstall and install share the same exclusive connection owner',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final events = <String>[];
      final queue = OperationQueue(
        connect: (id) async => events.add('connect:$id'),
        install: (job, _) async {
          events.add('install:${job.deviceId}');
        },
      );
      addTearDown(queue.dispose);
      final removal = queue.exclusive('A', () async {
        events.add('uninstall:A');
        started.complete();
        await gate.future;
      });
      await started.future;
      queue.add([job('B')]);
      expect(events, ['connect:A', 'uninstall:A']);
      gate.complete();
      await removal;
      await queue.settled;
      expect(events, ['connect:A', 'uninstall:A', 'connect:B', 'install:B']);
    },
  );
}
