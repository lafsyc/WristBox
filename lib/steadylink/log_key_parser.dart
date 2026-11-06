import 'dart:convert';

/// Metadata is attached only when it belongs to the same decoded JSON object.
/// Nearby lines, list order and device names are never treated as identity proof.
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
    'bluetoothAddress',
    'deviceMac',
    'btMac',
    'address',
  ]) {
    final raw = value[name];
    if (raw is String) {
      final mac = raw.trim().replaceAll('-', ':').toUpperCase();
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

List<LogKeyCandidate> parseLogKeyRecords(List<Map<String, dynamic>> records) {
  if (records.length > 512) throw const FormatException('日志候选记录过多，请重新导出日志');
  final found = <String, LogKeyCandidate>{};
  var size = 0;
  for (final record in records) {
    final text = record['text'] as String? ?? '';
    final truncatedStart = record['truncatedStart'] == true;
    final truncatedEnd = record['truncatedEnd'] == true;
    size += text.length;
    if (text.length > 128 * 1024 || size > 2 * 1024 * 1024) {
      throw const FormatException('日志候选内容过大，请重新导出日志');
    }
    final source = _label(record['source']),
        number = (record['line'] as num?)?.toInt() ?? 0;
    final associated = <String>{};
    void add(String key, [Map<dynamic, dynamic>? metadata]) {
      final address = metadata == null ? '' : _address(metadata);
      final candidate = LogKeyCandidate(
        key: key,
        source: source,
        line: number,
        name: _label(metadata?['productName'] ?? metadata?['deviceName']),
        model: _label(metadata?['model']),
        address: address,
      );
      final id = '$key\u0000$address';
      final old = found[id];
      // Do not replace useful metadata with an unlabelled repetition.
      if (old == null ||
          candidate.name.isNotEmpty ||
          candidate.model.isNotEmpty) {
        found[id] = candidate;
      }
      if (found.length > 200) {
        throw const FormatException('Key 数量过多，请选择最近生成的日志');
      }
    }

    void walk(dynamic value, int depth) {
      if (depth > 32) return;
      if (value is Map) {
        for (final field in ['encryptKey', 'deviceKey']) {
          final key = _key(value[field], legacy: field == 'deviceKey');
          if (key != null) {
            associated.add(key);
            add(key, value);
          }
        }
        for (final nested in value.values) {
          if (nested is Map || nested is List) walk(nested, depth + 1);
          if (nested is String && nested.contains('encryptKey')) {
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

    // A window can start inside a JSON string; apparent objects in it cannot
    // safely establish which device owns the Key.
    for (final object
        in truncatedStart || truncatedEnd ? const <String>[] : _objects(text)) {
      dynamic value;
      try {
        value = jsonDecode(object);
      } on FormatException {
        continue;
      }
      walk(value, 0);
    }
    // Text/escaped/multiline log fragments can supply a key without dependable
    // device metadata. Keep them explicitly unassigned for manual confirmation.
    final plain = text.replaceAll(r'\"', '"');
    final pattern = RegExp(
      r'''["']?\b(encryptKey|deviceKey)["']?\s*[:=]\s*["']?([A-Za-z0-9:_-]+)''',
    );
    for (final match in pattern.allMatches(plain)) {
      // Never accept an incomplete field/token at a cut edge. The overlapping
      // next window supplies the complete field, including its delimiter.
      if ((truncatedStart && match.start == 0) ||
          (truncatedEnd && match.end == plain.length)) {
        continue;
      }
      final key = _key(match.group(2), legacy: match.group(1) == 'deviceKey');
      if (key != null && !associated.contains(key)) add(key);
    }
  }
  return found.values.toList();
}
