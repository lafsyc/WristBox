/// Deployment values are supplied when building; source checkouts have no
/// production service endpoint. Local Bluetooth features need no server config.
const wristBoxAuthUrl = String.fromEnvironment('WRISTBOX_AUTH_URL');
const wristBoxAuthUsesBundledCa = bool.fromEnvironment(
  'WRISTBOX_AUTH_USE_BUNDLED_CA',
);

bool isSecureServiceUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

/// Pin the bundled trust root only to the configured service origin, never to
/// unrelated hosts or ports supplied through a client override.
bool shouldUseBundledCa(
  String requestBase, {
  String configuredBase = wristBoxAuthUrl,
  bool enabled = wristBoxAuthUsesBundledCa,
}) {
  if (!enabled ||
      !isSecureServiceUrl(configuredBase) ||
      !isSecureServiceUrl(requestBase)) {
    return false;
  }
  final configured = Uri.parse(configuredBase);
  final request = Uri.parse(requestBase);
  return configured.host == request.host && configured.port == request.port;
}
