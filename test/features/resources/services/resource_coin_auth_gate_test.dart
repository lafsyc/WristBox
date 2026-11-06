import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/commands/command_protocol.dart';
import 'package:oronbox/src/features/accounts/services/bandbbs_auth_service.dart';
import 'package:oronbox/src/features/accounts/services/oronbox_coin_service.dart';

void main() {
  test('does not request coin status when the user is signed out', () async {
    final host = _RecordingHost();
    final container = ProviderContainer(
      overrides: [
        bandBbsAuthProvider.overrideWith(_SignedOutAuthNotifier.new),
        oronBoxCoinServiceProvider.overrideWithValue(OronBoxCoinService(host)),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(oronBoxMyCoinsProvider('resource-id').future),
      0,
    );
    expect(host.methods, isEmpty);
  });
}

class _SignedOutAuthNotifier extends BandBbsAuthNotifier {
  @override
  BandBbsAuthState build() => BandBbsAuthState.empty;
}

class _RecordingHost implements OronBoxCommandBus {
  final methods = <String>[];

  @override
  Stream<CommandEvent> get events => const Stream.empty();

  @override
  Future<CommandResult> execute(OronBoxCommand command) async {
    methods.add(command.method);
    return const CommandResult.success({'my_coins': 0});
  }

  @override
  Future<void> close() async {}
}
