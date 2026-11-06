import 'package:flutter/widgets.dart';

import 'mi_account_two_factor_resolver_base.dart';

MiAccountTwoFactorResolver createPlatformMiAccountTwoFactorResolver() {
  return const WebMiAccountTwoFactorResolver();
}

class WebMiAccountTwoFactorResolver implements MiAccountTwoFactorResolver {
  const WebMiAccountTwoFactorResolver();

  @override
  Future<String> resolve(BuildContext context, Uri notificationUrl) {
    throw UnsupportedError(
      'Xiaomi 2FA is not available on web because browser cookie access is isolated',
    );
  }
}
