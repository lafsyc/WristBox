import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:mdns_dart/mdns_dart.dart';
import 'package:oronbox/src/core/logging/logging_service.dart';

const debugMdnsServiceType = '_oronbox-debug._tcp';

/// LAN mDNS advertisement for the ODS endpoint.
///
/// Delegates to [MDNSServer] so only genuine DNS queries are answered and
/// self-announcement loops can never feed back into the server. Interface
/// enumeration is moved to a background isolate because it can stall on
/// Android; mDNS remains an enhancement and must never block the UI.
class DebugMdnsAdvertiser {
  DebugMdnsAdvertiser({
    required this.serverId,
    required this.displayName,
    required this.platform,
    required this.port,
    required this.fingerprint,
  });

  final String serverId;
  final String displayName;
  final String platform;
  final int port;
  final String fingerprint;

  MDNSServer? _server;
  static final _log = getLogger('DebugMdnsAdvertiser');

  Future<bool> start() async {
    if (_server != null) return true;
    final ips = await _localAddresses();
    if (ips.isEmpty) {
      _log.warning('mDNS advertisement skipped: no LAN IPv4 address');
      return false;
    }
    final txt = <String, String>{
      'v': '1',
      'id': serverId,
      'fp': fingerprint,
      'name': displayName,
      'platform': platform,
      'proto': 'http',
      'auth': 'challenge-rsa',
      'secure': '0',
    };
    final service = MDNSService(
      instance: _serviceInstance(displayName, serverId),
      service: debugMdnsServiceType,
      domain: 'local.',
      hostName: _hostname(),
      port: port,
      ips: ips,
      txt: MDNSService.createTXTRecords(txt),
    );
    final server = MDNSServer(
      MDNSServerConfig(
        zone: service,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      ),
    );
    try {
      await server.start();
    } catch (error, stackTrace) {
      // mDNS is an enhancement. A restricted network must not prevent ODS
      // from starting or serving a manually entered address.
      _log.warning('mDNS advertisement failed', error, stackTrace);
      return false;
    }
    _server = server;
    return true;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.stop();
  }

  String _hostname() {
    var host = serverId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-');
    if (host.isEmpty) host = 'oronbox';
    return '$host.local';
  }

  Future<List<InternetAddress>> _localAddresses() async {
    try {
      // NetworkInterface.list performs a synchronous interface enumeration
      // that can stall the caller's isolate for seconds on Android. Run it on
      // a separate isolate so mDNS startup never freezes the UI.
      return await Isolate.run<List<InternetAddress>>(() async {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
        interfaces.sort(
          (left, right) => _interfacePriority(
            left.name,
          ).compareTo(_interfacePriority(right.name)),
        );
        final addresses = <InternetAddress>[];
        for (final networkInterface in interfaces) {
          for (final address in networkInterface.addresses) {
            if (address.isLoopback || !_isUsableLanAddress(address)) continue;
            if (!addresses.contains(address)) addresses.add(address);
          }
        }
        return addresses;
      }).timeout(const Duration(milliseconds: 1500));
    } catch (_) {
      return const [];
    }
  }
}

String _safeLabel(String value) {
  final label = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
  if (label.isEmpty) return 'OronBox';
  return label.length <= 63 ? label : label.substring(0, 63);
}

String _serviceInstance(String displayName, String serverId) {
  final suffix = _serverSuffix(serverId);
  final safeName = _safeLabel(displayName);
  final maximumNameLength = 63 - suffix.length - 1;
  final shortenedName = safeName.length <= maximumNameLength
      ? safeName
      : safeName.substring(0, maximumNameLength);
  return '$shortenedName-$suffix';
}

String _serverSuffix(String value) {
  final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (normalized.isEmpty) return 'server';
  return normalized.length <= 8
      ? normalized
      : normalized.substring(normalized.length - 8);
}

int _interfacePriority(String name) {
  final normalized = name.toLowerCase();
  if (RegExp(r'^(en\d+|eth\d+|wlan\d+|wi-?fi)').hasMatch(normalized)) {
    return 0;
  }
  if (RegExp(
    r'^(utun|tun|tap|awdl|llw|bridge|docker|veth|vmnet|virbr|ap\d)',
  ).hasMatch(normalized)) {
    return 2;
  }
  return 1;
}

bool _isUsableLanAddress(InternetAddress address) {
  final parts = address.address.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((part) => part == null)) return false;
  final first = parts[0]!;
  final second = parts[1]!;
  if (first == 0 || first == 127 || first >= 224) return false;
  if (first == 169 && second == 254) return false;
  if (first == 198 && (second == 18 || second == 19)) return false;
  return true;
}
