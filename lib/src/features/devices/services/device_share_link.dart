import 'package:oronbox/src/core/models/bt_models.dart';

class DeviceShareLink {
  const DeviceShareLink._();

  static Uri build(MiWearState device) {
    return Uri(
      scheme: 'https',
      host: 'oronbox.zxor.org',
      path: '/open',
      queryParameters: {
        'source': 'deviceQr',
        'name': device.name,
        'mac': device.addr.replaceAll(':', ''),
        if (device.authkey case final authkey? when authkey.isNotEmpty)
          'authkey': authkey,
      },
    );
  }

  static Uri buildDeepLink(MiWearState device) {
    return Uri(
      scheme: 'oronbox',
      host: 'open',
      queryParameters: _parameters(device),
    );
  }

  static Uri buildAstroBoxCompatible(MiWearState device) {
    return Uri(
      scheme: 'https',
      host: 'astrobox.online',
      path: '/open',
      queryParameters: _parameters(device),
    );
  }

  static Map<String, String> _parameters(MiWearState device) => {
    'source': 'deviceQr',
    'name': device.name,
    'mac': device.addr.replaceAll(':', ''),
    if (device.authkey case final authkey? when authkey.isNotEmpty)
      'authkey': authkey,
  };

  static MiWearState? parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return null;

    final isOronBox = uri.scheme == 'oronbox' && uri.host == 'open';
    final isOronBoxWeb =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'oronbox.zxor.org' &&
        uri.path == '/open';
    final isAstroBox =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'astrobox.online' &&
        uri.path == '/open';
    if (!isOronBox && !isOronBoxWeb && !isAstroBox) return null;

    if (uri.queryParameters['source'] != 'deviceQr') return null;
    final name = uri.queryParameters['name'];
    final mac = uri.queryParameters['mac'];
    if (name == null || name.isEmpty || mac == null || mac.isEmpty) {
      return null;
    }

    final addr = _formatMac(mac);
    if (addr == null) return null;

    return MiWearState(
      name: name,
      addr: addr,
      connectType: 'spp',
      authkey: uri.queryParameters['authkey'] ?? '',
      disconnected: true,
    );
  }

  static String? _formatMac(String value) {
    final compact = value.replaceAll(':', '').toUpperCase();
    final valid = RegExp(r'^[0-9A-F]{12}$').hasMatch(compact);
    if (!valid) return null;
    return List.generate(
      6,
      (index) => compact.substring(index * 2, index * 2 + 2),
    ).join(':');
  }
}
