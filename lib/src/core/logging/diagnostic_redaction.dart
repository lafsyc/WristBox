const _hidden = '<redacted>';

final _credentialName = RegExp(
  r'^(?:authorization|cookies?|setcookie|password|passwd|pass|.*token|.*secret|apikey|encryptkey|devicekey|authkey|wrappedkey|privatekey|ssecurity|psecurity|key)$',
  caseSensitive: false,
);
final _namedCredential = RegExp(
  r'''\b(authorization|cookies?|set-cookie|password|passwd|pass[_-]?token|access[_-]?token|refresh[_-]?token|service[_-]?token|token|client[_-]?secret|secret|api[_-]?key|encrypt[_-]?key|device[_-]?key|auth[_-]?key|wrapped[_-]?key|private[_-]?key|ssecurity|psecurity)(["']?\s*[:=]\s*)(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;}\]&]+)''',
  caseSensitive: false,
);
final _headers = RegExp(
  r'\b(authorization|cookie|set-cookie)\s*:\s*[^\r\n]+',
  caseSensitive: false,
);
final _bearer = RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false);

String redactDiagnosticText(String value) {
  // Bound diagnostics independently of protocol payload sizes.
  if (value.length > 16384) return '[oversized diagnostic omitted]';
  var text = value;
  text = text.replaceAllMapped(_headers, (m) => '${m[1]}: $_hidden');
  text = text.replaceAll(_bearer, 'Bearer $_hidden');
  return text.replaceAllMapped(
    _namedCredential,
    (m) => '${m[1]}${m[2]}$_hidden',
  );
}

Object? redactDiagnosticValue(Object? value, [int depth = 0]) {
  if (depth > 8) return '[truncated]';
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries.take(100))
        redactDiagnosticText(entry.key.toString()):
            _credentialName.hasMatch(
              entry.key.toString().replaceAll(RegExp(r'[^A-Za-z]'), ''),
            )
            ? _hidden
            : redactDiagnosticValue(entry.value, depth + 1),
    };
  }
  if (value is Iterable) {
    return value
        .take(100)
        .map((v) => redactDiagnosticValue(v, depth + 1))
        .toList();
  }
  if (value == null || value is num || value is bool) return value;
  return redactDiagnosticText(value.toString());
}
