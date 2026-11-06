import 'package:dio/dio.dart';
import 'package:oronbox/src/core/errors/coded_error.dart';
import 'package:oronbox/src/features/accounts/services/bandbbs_auth_service.dart';

class OronBoxAuthRequiredException implements CodedError {
  const OronBoxAuthRequiredException();

  @override
  String get code => 'auth_required';

  @override
  String get message => 'BandBBS account is not signed in';

  @override
  Object? get details => null;

  @override
  String toString() => message;
}

class OronBoxSessionClient {
  const OronBoxSessionClient(this._sessions);

  final OronBoxSessionAccess _sessions;

  Future<Response<T>> send<T>(
    Future<Response<T>> Function(Options authorization) operation,
  ) async {
    final session = await _sessions.sessionIfNeeded();
    if (session == null) throw const OronBoxAuthRequiredException();
    try {
      return await operation(
        Options(headers: {'Authorization': 'Bearer ${session.accessToken}'}),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
      try {
        await _sessions.expireSession();
      } catch (_) {
        // The authenticated request already proved the session invalid.
        // Failure to notify the host must not hide the user-facing expiry.
      }
      throw const BandBbsSessionExpiredException();
    }
  }
}
