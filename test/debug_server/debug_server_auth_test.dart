import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/debug_server/debug_server_auth.dart';
import 'package:oronbox/src/debug_server/debug_server_protocol.dart';

void main() {
  test('known client authenticates with a signed one-time challenge', () {
    final server = DebugRsaKeyPair.generate(bitStrength: 2048);
    final client = DebugRsaKeyPair.generate(bitStrength: 2048);
    final auth = DebugServerAuthenticator(
      serverId: 'server-1',
      serverIdentity: server,
      now: () => DateTime.utc(2026, 1, 1),
    );

    final fingerprint = client.publicKey.fingerprint;
    auth.approveClient(
      DebugAuthorizedClient(
        fingerprint: fingerprint,
        publicKey: client.publicKey,
        displayName: 'Test client',
        scopes: {'device.list'},
      ),
    );
    final challenge = auth.issueChallenge(
      clientId: 'client-1',
      clientKey: client.publicKey,
      scopes: {'device.list'},
    );
    final signature = client.sign(
      DebugAuthTranscript.encode(
        challengeId: challenge.challengeId,
        serverId: 'server-1',
        clientId: 'client-1',
        serverNonce: challenge.serverNonce,
        clientNonce: challenge.clientNonce,
        clientFingerprint: fingerprint,
        scopes: {'device.list'},
      ),
    );

    final result = auth.verify(
      challengeId: challenge.challengeId,
      clientId: 'client-1',
      clientKey: client.publicKey,
      scopes: {'device.list'},
      signature: signature,
    );

    expect(result.status, DebugAuthStatus.authorized);
    expect(result.fingerprint, fingerprint);
    expect(
      auth
          .verify(
            challengeId: challenge.challengeId,
            clientId: 'client-1',
            clientKey: client.publicKey,
            scopes: {'device.list'},
            signature: signature,
          )
          .status,
      DebugAuthStatus.rejected,
    );
  });

  test('unknown client remains pending until explicitly approved', () {
    final server = DebugRsaKeyPair.generate(bitStrength: 2048);
    final client = DebugRsaKeyPair.generate(bitStrength: 2048);
    final auth = DebugServerAuthenticator(
      serverId: 'server-1',
      serverIdentity: server,
      now: () => DateTime.utc(2026, 1, 1),
    );
    final challenge = auth.issueChallenge(
      clientId: 'client-1',
      clientKey: client.publicKey,
      scopes: {'install.upload'},
      displayName: 'Test IDE',
    );
    final signature = client.sign(
      DebugAuthTranscript.encode(
        challengeId: challenge.challengeId,
        serverId: 'server-1',
        clientId: 'client-1',
        serverNonce: challenge.serverNonce,
        clientNonce: challenge.clientNonce,
        clientFingerprint: client.publicKey.fingerprint,
        scopes: {'install.upload'},
      ),
    );

    final pending = auth.verify(
      challengeId: challenge.challengeId,
      clientId: 'client-1',
      clientKey: client.publicKey,
      scopes: {'install.upload'},
      signature: signature,
    );

    expect(pending.status, DebugAuthStatus.pendingApproval);
    expect(
      auth.pendingClients.single.fingerprint,
      client.publicKey.fingerprint,
    );
    expect(auth.pendingClients.single.displayName, 'Test IDE');

    auth.approveClient(auth.pendingClients.single);
    final nextChallenge = auth.issueChallenge(
      clientId: 'client-1',
      clientKey: client.publicKey,
      scopes: {'install.upload'},
    );
    final nextSignature = client.sign(
      DebugAuthTranscript.encode(
        challengeId: nextChallenge.challengeId,
        serverId: 'server-1',
        clientId: 'client-1',
        serverNonce: nextChallenge.serverNonce,
        clientNonce: nextChallenge.clientNonce,
        clientFingerprint: client.publicKey.fingerprint,
        scopes: {'install.upload'},
      ),
    );

    expect(
      auth
          .verify(
            challengeId: nextChallenge.challengeId,
            clientId: 'client-1',
            clientKey: client.publicKey,
            scopes: {'install.upload'},
            signature: nextSignature,
          )
          .status,
      DebugAuthStatus.authorized,
    );
  });

  test('expired challenges are rejected', () {
    var now = DateTime.utc(2026, 1, 1);
    final server = DebugRsaKeyPair.generate(bitStrength: 2048);
    final client = DebugRsaKeyPair.generate(bitStrength: 2048);
    final auth = DebugServerAuthenticator(
      serverId: 'server-1',
      serverIdentity: server,
      now: () => now,
      challengeLifetime: const Duration(seconds: 30),
    );
    auth.approveClient(
      DebugAuthorizedClient(
        fingerprint: client.publicKey.fingerprint,
        publicKey: client.publicKey,
        displayName: 'Test client',
        scopes: {'device.list'},
      ),
    );
    final challenge = auth.issueChallenge(
      clientId: 'client-1',
      clientKey: client.publicKey,
      scopes: {'device.list'},
    );
    now = now.add(const Duration(seconds: 31));

    final signature = client.sign(
      DebugAuthTranscript.encode(
        challengeId: challenge.challengeId,
        serverId: 'server-1',
        clientId: 'client-1',
        serverNonce: challenge.serverNonce,
        clientNonce: challenge.clientNonce,
        clientFingerprint: client.publicKey.fingerprint,
        scopes: {'device.list'},
      ),
    );

    expect(
      auth
          .verify(
            challengeId: challenge.challengeId,
            clientId: 'client-1',
            clientKey: client.publicKey,
            scopes: {'device.list'},
            signature: signature,
          )
          .status,
      DebugAuthStatus.rejected,
    );
  });
}
