import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'debug_server_protocol.dart';

enum DebugAuthStatus { authorized, pendingApproval, rejected }

class DebugAuthResult {
  const DebugAuthResult(this.status, {this.fingerprint});

  final DebugAuthStatus status;
  final String? fingerprint;
}

class DebugAuthorizedClient {
  const DebugAuthorizedClient({
    required this.fingerprint,
    required this.publicKey,
    required this.displayName,
    required this.scopes,
  });

  final String fingerprint;
  final DebugRsaPublicKey publicKey;
  final String displayName;
  final Set<String> scopes;

  Map<String, Object?> toJson() => {
    'fingerprint': fingerprint,
    'publicKey': publicKey.toJson(),
    'displayName': displayName,
    'scopes': scopes.toList()..sort(),
  };

  factory DebugAuthorizedClient.fromJson(Map<String, Object?> json) {
    final publicKey = DebugRsaPublicKey.fromJson(
      (json['publicKey'] as Map).cast<String, Object?>(),
    );
    final fingerprint =
        json['fingerprint']?.toString() ?? publicKey.fingerprint;
    if (fingerprint != publicKey.fingerprint) {
      throw const FormatException('Authorized client fingerprint mismatch');
    }
    final scopes = json['scopes'];
    return DebugAuthorizedClient(
      fingerprint: fingerprint,
      publicKey: publicKey,
      displayName: json['displayName']?.toString().trim() ?? '',
      scopes: scopes is List
          ? scopes.map((value) => value.toString()).toSet()
          : const {},
    );
  }
}

class DebugRsaPublicKey {
  const DebugRsaPublicKey({required this.modulus, required this.exponent});

  final BigInt modulus;
  final BigInt exponent;

  String get fingerprint {
    final digest = sha256.convert(utf8.encode(jsonEncode(toJson())));
    return 'SHA256:${digest.toString()}';
  }

  RSAPublicKey get pointyCastleKey => RSAPublicKey(modulus, exponent);

  Map<String, Object?> toJson() => {
    'kty': 'RSA',
    'n': _encodeBigInt(modulus),
    'e': _encodeBigInt(exponent),
  };

  factory DebugRsaPublicKey.fromJson(Map<String, Object?> json) {
    if (json['kty'] != 'RSA') {
      throw const FormatException('Unsupported debug public key type');
    }
    return DebugRsaPublicKey(
      modulus: _decodeBigInt(json['n']?.toString() ?? ''),
      exponent: _decodeBigInt(json['e']?.toString() ?? ''),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DebugRsaPublicKey &&
      other.modulus == modulus &&
      other.exponent == exponent;

  @override
  int get hashCode => Object.hash(modulus, exponent);
}

class DebugRsaKeyPair {
  const DebugRsaKeyPair({required this.publicKey, required this.privateKey});

  final DebugRsaPublicKey publicKey;
  final RSAPrivateKey privateKey;

  factory DebugRsaKeyPair.generate({int bitStrength = 2048}) {
    if (bitStrength < 2048) {
      throw ArgumentError.value(bitStrength, 'bitStrength', 'must be >= 2048');
    }
    final entropy = Random.secure();
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(List.generate(32, (_) => entropy.nextInt(256))),
        ),
      );
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), bitStrength, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    final publicKey = pair.publicKey;
    final privateKey = pair.privateKey;
    return DebugRsaKeyPair(
      publicKey: DebugRsaPublicKey(
        modulus: publicKey.modulus!,
        exponent: publicKey.exponent!,
      ),
      privateKey: privateKey,
    );
  }

  Uint8List sign(List<int> message) {
    final signer = Signer('SHA-256/RSA')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final signature = signer.generateSignature(Uint8List.fromList(message));
    return (signature as RSASignature).bytes;
  }

  Map<String, Object?> toJson() => {
    'public': publicKey.toJson(),
    'private': {
      'd': _encodeBigInt(privateKey.exponent!),
      'p': _encodeBigInt(privateKey.p!),
      'q': _encodeBigInt(privateKey.q!),
    },
  };

  factory DebugRsaKeyPair.fromJson(Map<String, Object?> json) {
    final publicKey = DebugRsaPublicKey.fromJson(
      (json['public'] as Map).cast<String, Object?>(),
    );
    final private = (json['private'] as Map).cast<String, Object?>();
    final privateKey = RSAPrivateKey(
      publicKey.modulus,
      _decodeBigInt(private['d']?.toString() ?? ''),
      _decodeBigInt(private['p']?.toString() ?? ''),
      _decodeBigInt(private['q']?.toString() ?? ''),
    );
    return DebugRsaKeyPair(publicKey: publicKey, privateKey: privateKey);
  }
}

class DebugServerAuthenticator {
  DebugServerAuthenticator({
    required this.serverId,
    required this.serverIdentity,
    DateTime Function()? now,
    this.challengeLifetime = const Duration(seconds: 30),
    Iterable<DebugAuthorizedClient> authorizedClients = const [],
  }) : now = now ?? DateTime.now {
    for (final client in authorizedClients) {
      _authorized[client.fingerprint] = client;
    }
  }

  final String serverId;
  final DebugRsaKeyPair serverIdentity;
  final DateTime Function() now;
  final Duration challengeLifetime;
  final _authorized = <String, DebugAuthorizedClient>{};
  final _pending = <String, DebugAuthorizedClient>{};
  final _challenges = <String, _ChallengeState>{};

  String get serverFingerprint => serverIdentity.publicKey.fingerprint;

  List<DebugAuthorizedClient> get authorizedClients =>
      List.unmodifiable(_authorized.values);

  List<DebugAuthorizedClient> get pendingClients =>
      List.unmodifiable(_pending.values);

  DebugAuthChallenge issueChallenge({
    required String clientId,
    required DebugRsaPublicKey clientKey,
    required Set<String> scopes,
    String? displayName,
  }) {
    final challenge = DebugAuthChallenge(
      challengeId: _randomId('challenge'),
      serverId: serverId,
      serverNonce: _randomToken(),
      clientNonce: _randomToken(),
      clientFingerprint: clientKey.fingerprint,
      scopes: Set.unmodifiable(scopes),
      expiresAt: now().toUtc().add(challengeLifetime),
    );
    _challenges[challenge.challengeId] = _ChallengeState(
      challenge: challenge,
      clientId: clientId,
      clientKey: clientKey,
      displayName: displayName?.trim().isEmpty == true
          ? null
          : displayName?.trim(),
    );
    return challenge;
  }

  DebugAuthResult verify({
    required String challengeId,
    required String clientId,
    required DebugRsaPublicKey clientKey,
    required Set<String> scopes,
    required List<int> signature,
  }) {
    final state = _challenges.remove(challengeId);
    if (state == null || now().toUtc().isAfter(state.challenge.expiresAt)) {
      return const DebugAuthResult(DebugAuthStatus.rejected);
    }
    if (state.clientId != clientId || state.clientKey != clientKey) {
      return const DebugAuthResult(DebugAuthStatus.rejected);
    }
    if (!scopes.containsAll(state.challenge.scopes) ||
        !state.challenge.scopes.containsAll(scopes)) {
      return const DebugAuthResult(DebugAuthStatus.rejected);
    }
    final transcript = DebugAuthTranscript.encode(
      challengeId: state.challenge.challengeId,
      serverId: state.challenge.serverId,
      clientId: clientId,
      serverNonce: state.challenge.serverNonce,
      clientNonce: state.challenge.clientNonce,
      clientFingerprint: clientKey.fingerprint,
      scopes: scopes,
    );
    if (!_verifySignature(clientKey, transcript, signature)) {
      return const DebugAuthResult(DebugAuthStatus.rejected);
    }
    final fingerprint = clientKey.fingerprint;
    final authorized = _authorized[fingerprint];
    if (authorized != null) {
      if (!authorized.scopes.containsAll(scopes)) {
        return const DebugAuthResult(DebugAuthStatus.rejected);
      }
      return DebugAuthResult(
        DebugAuthStatus.authorized,
        fingerprint: fingerprint,
      );
    }
    _pending[fingerprint] = DebugAuthorizedClient(
      fingerprint: fingerprint,
      publicKey: clientKey,
      displayName: state.displayName ?? clientId,
      scopes: Set.unmodifiable(scopes),
    );
    return DebugAuthResult(
      DebugAuthStatus.pendingApproval,
      fingerprint: fingerprint,
    );
  }

  void approveClient(DebugAuthorizedClient client) {
    _pending.remove(client.fingerprint);
    _authorized[client.fingerprint] = client;
  }

  void rejectClient(String fingerprint) {
    _pending.remove(fingerprint);
  }

  void revokeClient(String fingerprint) {
    _authorized.remove(fingerprint);
  }

  void clearExpiredChallenges() {
    final current = now().toUtc();
    _challenges.removeWhere(
      (_, state) => current.isAfter(state.challenge.expiresAt),
    );
  }
}

class _ChallengeState {
  const _ChallengeState({
    required this.challenge,
    required this.clientId,
    required this.clientKey,
    this.displayName,
  });

  final DebugAuthChallenge challenge;
  final String clientId;
  final DebugRsaPublicKey clientKey;
  final String? displayName;
}

bool _verifySignature(
  DebugRsaPublicKey publicKey,
  List<int> message,
  List<int> signature,
) {
  try {
    final verifier = Signer(
      'SHA-256/RSA',
    )..init(false, PublicKeyParameter<RSAPublicKey>(publicKey.pointyCastleKey));
    return verifier.verifySignature(
      Uint8List.fromList(message),
      RSASignature(Uint8List.fromList(signature)),
    );
  } catch (_) {
    return false;
  }
}

String _randomId(String prefix) => '$prefix-${_randomToken()}';

String _randomToken() {
  final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String _encodeBigInt(BigInt value) {
  if (value == BigInt.zero) return 'AA';
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return base64Url.encode(bytes).replaceAll('=', '');
}

BigInt _decodeBigInt(String encoded) {
  if (encoded.isEmpty) throw const FormatException('Missing RSA integer');
  final padded = '$encoded${'=' * ((4 - encoded.length % 4) % 4)}';
  final bytes = base64Url.decode(padded);
  return BigInt.parse(
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    radix: 16,
  );
}
