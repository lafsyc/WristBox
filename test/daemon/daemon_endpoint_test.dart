import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/daemon/daemon_endpoint.dart';

void main() {
  test('uses a short writable macOS sandbox endpoint', () {
    final directory = resolveDaemonRuntimeDirectory(
      operatingSystem: 'macos',
      environment: const {'HOME': '/Users/orpudding'},
      systemTemporaryDirectory:
          '/Users/orpudding/Library/Containers/org.zxor.oronbox/Data/tmp',
    );
    expect(
      directory,
      '/Users/orpudding/Library/Containers/org.zxor.oronbox/Data/tmp/oronbox',
    );
    expect('$directory/daemon.sock'.length, lessThan(104));
  });

  test('uses the per-user temporary directory on unsandboxed macOS', () {
    expect(
      resolveDaemonRuntimeDirectory(
        operatingSystem: 'macos',
        environment: const {'HOME': '/Users/orpudding'},
        systemTemporaryDirectory: '/var/folders/example/T',
      ),
      '/var/folders/example/T/oronbox',
    );
  });

  test('uses the Windows local application-data directory', () {
    expect(
      resolveDaemonRuntimeDirectory(
        operatingSystem: 'windows',
        environment: const {
          'LOCALAPPDATA': r'C:\Users\orpudding\AppData\Local',
        },
        systemTemporaryDirectory: r'C:\Temp',
      ),
      r'C:\Users\orpudding\AppData\Local\OronBox\run',
    );
  });

  test('validates Windows daemon discovery metadata', () {
    final endpoint = WindowsDaemonEndpoint.fromJson(const {
      'port': 51234,
      'token': 'secret',
      'pid': 42,
      'protocolVersion': 1,
    });
    expect(endpoint.port, 51234);
    expect(endpoint.token, 'secret');
    expect(endpoint.pid, 42);
    expect(endpoint.toJson()['protocolVersion'], 1);
    expect(
      () => WindowsDaemonEndpoint.fromJson(const {'port': 0, 'token': ''}),
      throwsFormatException,
    );
  });
}
