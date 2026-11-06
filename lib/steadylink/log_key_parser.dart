import 'dart:convert';

/// Complete objects and unambiguous explicit device identifiers establish
/// associations. Proximity, list order and display names never establish identity.
class LogKeyCandidate {
  const LogKeyCandidate({
    required this.key,
    required this.source,
    required this.line,
    this.name = '',
    this.model = '',
    this.address = '',
  });
  final String key, source, name, model, address;
  final int line;
  String get hint =>
      '•••• •••• •••• ${key.substring(key.length - 6).toUpperCase()}';
  @override
  String toString() => 'LogKeyCandidate(masked)';
}

String _label(Object? value) {
  if (value is! String) return '';
  final cleaned = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  return cleaned.substring(0, cleaned.length.clamp(0, 96));
}

String? _key(Object? value, {bool legacy = false}) {
  if (value is! String) return null;
  var result = value.trim();
  if (legacy && result.contains(':')) result = result.split(':').last;
  if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(result) || result == '0' * 32) {
    return null;
  }
  return result.toLowerCase();
}

String _address(Map<dynamic, dynamic> value) {
  for (final name in [
    'mac',
    'macAddress',
    'mac_address',
    'bluetoothAddress',
    'deviceMac',
    'btMac',
    'address',
  ]) {
    final raw = value[name];
    if (raw is String) {
      var mac = raw.trim().replaceAll('-', ':').toUpperCase();
      if (RegExp(r'^[0-9A-F]{12}$').hasMatch(mac)) {
        mac = List.generate(
          6,
          (i) => mac.substring(i * 2, i * 2 + 2),
        ).join(':');
      }
      if (RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(mac) &&
          mac != '00:00:00:00:00:00' &&
          mac != 'FF:FF:FF:FF:FF:FF') {
        return mac;
      }
    }
  }
  return '';
}

Iterable<String> _objects(String line) sync* {
  var depth = 0, start = -1, quoted = false, escaped = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (start < 0) {
      if (c == '{' || c == '[') {
        start = i;
        depth = 1;
        quoted = false;
      }
      continue;
    }
    if (escaped) {
      escaped = false;
      continue;
    }
    if (quoted && c == r'\') {
      escaped = true;
      continue;
    }
    if (c == '"') {
      quoted = !quoted;
      continue;
    }
    if (quoted) continue;
    if (c == '{' || c == '[') depth++;
    if (depth > 32) return;
    if (c == '}' || c == ']') {
      depth--;
      if (depth == 0) {
        yield line.substring(start, i + 1);
        start = -1;
      }
    }
  }
}

const _keyFields = [
  'encryptKey',
  'deviceKey',
  'encrypt_key',
  'authKey',
  'auth_key',
  'huamiAuthKey',
];

Map<dynamic, dynamic>? _map(Object? value) {
  if (value is Map) return value;
  if (value is String && value.length <= 128 * 1024) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return decoded;
    } on FormatException {
      /* An ordinary string is not device metadata. */
    }
  }
  return null;
}

// Only the established deviceInfo/device/detail/product schema may supply
// metadata across nested objects. Arbitrary payload parents are not inherited.
Map<dynamic, dynamic> _deviceMetadata(Map value) {
  final root = _map(value['deviceInfo']) ?? value;
  final device = _map(root['device']) ?? root;
  final detail = _map(device['detail']) ?? _map(root['detail']);
  final product = _map(device['product']);
  return {...?product, ...root, ...device, ...?detail};
}

Set<String> _identities(Map value) {
  final result = <String>{};
  for (final field in [
    'did',
    'deviceId',
    'device_id',
    'sn',
    'serialNumber',
    'serial_number',
  ]) {
    final raw = value[field];
    if (raw is! String && raw is! int) continue;
    final text = '$raw'.trim();
    if (text.isEmpty ||
        text.length > 128 ||
        text == '0' ||
        text == 'null' ||
        text.contains('*')) {
      continue;
    }
    final namespace = switch (field) {
      'device_id' => 'deviceId',
      'serialNumber' || 'serial_number' => 'sn',
      _ => field,
    };
    result.add('$namespace:$text');
  }
  return result;
}

/// A device has one card; different historical Keys remain explicitly selectable.
class LogDeviceGroup {
  LogDeviceGroup(this.candidates);
  final List<LogKeyCandidate> candidates;
  LogKeyCandidate get device => candidates.first;
}

List<LogDeviceGroup> groupLogDevices(List<LogKeyCandidate> candidates) {
  final groups = <String, List<LogKeyCandidate>>{};
  for (final c in candidates) {
    final identity = c.address.isEmpty ? 'unassigned:${c.key}' : c.address;
    (groups[identity] ??= []).add(c);
  }
  final result = groups.values.map(LogDeviceGroup.new).toList();
  result.sort(
    (a, b) => (a.device.address.isEmpty ? 1 : 0).compareTo(
      b.device.address.isEmpty ? 1 : 0,
    ),
  );
  return result;
}

List<LogKeyCandidate> parseLogKeyRecords(List<Map<String, dynamic>> records) {
  if (records.length > 512) throw const FormatException('日志候选记录过多，请重新导出日志');
  final entries = <({String key, Map metadata, String source, int line})>[];
  final byIdentity = <String, Map<String, Map>>{};
  final byAddress = <String, Map>{};
  var size = 0, objects = 0;
  for (final record in records) {
    final text = record['text'] as String? ?? '';
    final truncatedStart = record['truncatedStart'] == true;
    final truncatedEnd = record['truncatedEnd'] == true;
    size += text.length;
    if (text.length > 128 * 1024 || size > 2 * 1024 * 1024) {
      throw const FormatException('日志候选内容过大，请重新导出日志');
    }
    final source = _label(record['source']);
    final number = (record['line'] as num?)?.toInt() ?? 0;
    final associated = <String>{};
    void add(String key, Map metadata) {
      entries.add((key: key, metadata: metadata, source: source, line: number));
      if (entries.length > 4096) {
        throw const FormatException('日志设备记录过多，请重新导出日志');
      }
    }

    void walk(dynamic value, int depth) {
      if (depth > 32) return;
      if (value is Map) {
        if (++objects > 4096) throw const FormatException('日志结构过多，请重新导出日志');
        final metadata = _deviceMetadata(value);
        final address = _address(metadata);
        if (address.isNotEmpty) {
          byAddress[address] = {...?byAddress[address], ...metadata};
          for (final identity in _identities(metadata)) {
            (byIdentity[identity] ??= {})[address] = metadata;
          }
        }
        for (final field in _keyFields) {
          final key = _key(metadata[field], legacy: field == 'deviceKey');
          if (key != null) {
            associated.add(key);
            add(key, metadata);
          }
        }
        for (final nested in value.values) {
          if (nested is Map || nested is List) walk(nested, depth + 1);
          if (nested is String && _keyFields.any(nested.contains)) {
            dynamic decoded;
            try {
              decoded = jsonDecode(nested);
            } on FormatException {
              continue;
            }
            walk(decoded, depth + 1);
          }
        }
      } else if (value is List) {
        for (final nested in value) {
          walk(nested, depth + 1);
        }
      }
    }

    // Truncated windows cannot prove JSON context. Native code additionally
    // emits complete objects with string context preserved across all windows.
    for (final object
        in truncatedStart || truncatedEnd || record['metadataAllowed'] == false
            ? const <String>[]
            : _objects(text)) {
      dynamic decoded;
      try {
        decoded = jsonDecode(object);
      } on FormatException {
        continue;
      }
      walk(decoded, 0);
    }
    final plain = text.replaceAll(r'\"', '"');
    final pattern = RegExp(
      r'''["']?\b(encryptKey|deviceKey|encrypt_key|authKey|auth_key|huamiAuthKey)["']?\s*[:=]\s*["']?([A-Za-z0-9:_-]+)''',
    );
    for (final match in pattern.allMatches(plain)) {
      if ((truncatedStart && match.start == 0) ||
          (truncatedEnd && match.end == plain.length)) {
        continue;
      }
      final key = _key(match.group(2), legacy: match.group(1) == 'deviceKey');
      if (key != null && !associated.contains(key)) add(key, {});
    }
  }
  final found = <String, LogKeyCandidate>{};
  final ambiguousKeys = <String>{};
  for (final entry in entries) {
    var metadata = entry.metadata;
    var address = _address(metadata);
    if (address.isEmpty) {
      final matches = <String, Map>{};
      for (final identity in _identities(metadata)) {
        matches.addAll(byIdentity[identity] ?? {});
      }
      if (matches.length == 1) address = matches.keys.single;
      if (matches.length > 1) ambiguousKeys.add(entry.key);
    }
    if (address.isNotEmpty) metadata = {...?byAddress[address], ...metadata};
    final candidate = LogKeyCandidate(
      key: entry.key,
      source: entry.source,
      line: entry.line,
      address: address,
      name: _label(
        metadata['productName'] ?? metadata['deviceName'] ?? metadata['name'],
      ),
      model: _label(metadata['model'] ?? metadata['codename']),
    );
    final id = '${entry.key}\u0000$address';
    final old = found[id];
    if (old == null ||
        candidate.name.isNotEmpty ||
        candidate.model.isNotEmpty) {
      found[id] = candidate;
    }
  }
  // Suppress a fragment-only repetition when the identical Key already has
  // exactly one complete device association. Conflicting associations stay visible.
  final bound = <String, Set<String>>{};
  for (final c in found.values) {
    if (c.address.isNotEmpty) (bound[c.key] ??= {}).add(c.address);
  }
  found.removeWhere(
    (_, c) =>
        c.address.isEmpty &&
        bound[c.key]?.length == 1 &&
        !ambiguousKeys.contains(c.key),
  );
  if (found.length > 200) throw const FormatException('Key 数量过多，请选择最近生成的日志');
  return found.values.toList();
}
