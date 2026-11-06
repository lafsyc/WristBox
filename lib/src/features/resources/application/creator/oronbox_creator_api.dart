import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:oronbox/src/core/constants/oronbox_server.dart';
import 'package:oronbox/src/core/errors/coded_error.dart';
import 'package:oronbox/src/core/logging/logging_service.dart';
import 'package:oronbox/src/core/network/app_http_transport.dart';
import 'package:oronbox/src/core/network/http_observability_interceptor.dart';
import 'package:oronbox/src/features/accounts/services/bandbbs_auth_service.dart';
import 'package:oronbox/src/features/accounts/services/oronbox_session_client.dart';

class OronBoxCreatorApi {
  OronBoxCreatorApi({required OronBoxSessionAccess sessions, Dio? dio})
    : _sessionAccess = sessions,
      _sessions = OronBoxSessionClient(sessions),
      _dio =
          dio ??
          createAppHttpTransport(
            options: BaseOptions(baseUrl: oronBoxServerBaseUrl),
          );

  final OronBoxSessionAccess _sessionAccess;
  final OronBoxSessionClient _sessions;
  final Dio _dio;
  static final _log = getLogger('CreatorApi');

  Future<Object?> request(
    String method,
    String path, {
    Object? data,
    Map<String, Object?>? query,
    String stage = 'request',
  }) async {
    final response = await _requestResponse(
      method,
      path,
      data: data,
      query: query,
      stage: stage,
    );
    return response.data;
  }

  Future<Object?> publicRequest(
    String method,
    String path, {
    Map<String, Object?>? query,
  }) async {
    final session = await _optionalSession('public.auth');
    final response = await _send(
      () => _dio.request<Object?>(
        path,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {
            if (session != null)
              'Authorization': 'Bearer ${session.accessToken}',
          },
        ),
      ),
      stage: 'public',
    );
    return response.data;
  }

  Future<Response<Object?>> _requestResponse(
    String method,
    String path, {
    Object? data,
    Map<String, Object?>? query,
    required String stage,
  }) async {
    final response = await _send(
      () => _sessions.send<Object?>(
        (authorization) => _dio.request<Object?>(
          path,
          data: data,
          queryParameters: query,
          options: authorization.copyWith(method: method),
        ),
      ),
      stage: stage,
    );
    return response;
  }

  Future<OronBoxSession?> _optionalSession(String stage) async {
    try {
      return await _sessionAccess.sessionIfNeeded();
    } on DioException catch (error) {
      throw CreatorApiException.fromDio(error, stage: stage);
    } on CodedError catch (error) {
      throw CreatorApiException(
        code: error.code,
        message: error.message,
        details: {'stage': stage, 'cause': error.details},
      );
    }
  }

  Future<Object?> publish({
    required String resourceId,
    required Uint8List bundle,
    void Function(double progress)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    logDiagnostic(
      _log,
      Level.INFO,
      'Creator publish started',
      fields: {'resource': resourceId, 'bytes': bundle.length},
    );
    try {
      final response = await _send(
        () => _sessions.send<Object?>(
          (authorization) => _dio.post<Object?>(
            '/api/creator/resources/$resourceId/publish',
            data: Stream.fromIterable([bundle]),
            options: authorization.copyWith(
              headers: {
                ...?authorization.headers,
                Headers.contentLengthHeader: bundle.length,
                Headers.contentTypeHeader: 'application/zip',
              },
            ),
            onSendProgress: (sent, total) {
              if (total > 0) onProgress?.call(sent / total);
            },
          ),
        ),
        stage: 'publish',
      );
      stopwatch.stop();
      logDiagnostic(
        _log,
        Level.INFO,
        'Creator publish completed',
        fields: {
          'resource': resourceId,
          'bytes': bundle.length,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      return response.data;
    } catch (error, stackTrace) {
      stopwatch.stop();
      final failure = switch (error) {
        CreatorApiException value => value,
        CodedError value => CreatorApiException(
          code: value.code,
          message: value.message,
          details: {'stage': 'publish', 'cause': value.details},
        ),
        _ => CreatorApiException(
          code: 'publish_failed',
          message: _friendlyMessage(error),
          details: const {'stage': 'publish'},
        ),
      };
      logDiagnostic(
        _log,
        Level.WARNING,
        'Creator publish failed',
        fields: {
          'resource': resourceId,
          'bytes': bundle.length,
          'durationMs': stopwatch.elapsedMilliseconds,
          'code': failure.code,
          ...failure.details,
        },
        error: failure.message,
        stackTrace: error is CreatorApiException ? null : stackTrace,
      );
      throw failure;
    }
  }

  Future<Object?> saveDraft({
    required String resourceId,
    required Uint8List bundle,
  }) async {
    final response = await _send(
      () => _sessions.send<Object?>(
        (authorization) => _dio.put<Object?>(
          '/api/creator/resources/$resourceId/draft',
          data: Stream.fromIterable([bundle]),
          options: authorization.copyWith(
            headers: {
              ...?authorization.headers,
              Headers.contentLengthHeader: bundle.length,
              Headers.contentTypeHeader: 'application/zip',
            },
          ),
        ),
      ),
      stage: 'draft',
    );
    return response.data;
  }

  Future<Uint8List> downloadBlob(String resourceId, String digest) async {
    final response = await _send(
      () => _sessions.send<List<int>>(
        (authorization) => _dio.get<List<int>>(
          '/api/creator/resources/$resourceId/blobs/$digest',
          options: authorization.copyWith(responseType: ResponseType.bytes),
        ),
      ),
      stage: 'blob',
    );
    return Uint8List.fromList(response.data ?? const []);
  }

  Future<Map<String, Object?>> resourceRelationships(String resourceId) async =>
      _map(
        await request(
          'GET',
          '/api/creator/resources/$resourceId/relationships',
        ),
      );

  Future<void> inviteCollaborator(String resourceId, int bandBbsUserId) async {
    await request(
      'POST',
      '/api/creator/resources/$resourceId/collaborators',
      data: {'bandbbs_user_id': bandBbsUserId},
    );
  }

  Future<void> removeCollaborator(String resourceId, String userId) async {
    await request(
      'DELETE',
      '/api/creator/resources/$resourceId/collaborators/$userId',
    );
  }

  Future<void> setResourceSource({
    required String resourceId,
    required String authorName,
    required String sourceUrl,
    required String licenseName,
    required String authorizationNote,
  }) async {
    await request(
      'PUT',
      '/api/creator/resources/$resourceId/source',
      data: {
        'author_name': authorName,
        'source_url': sourceUrl,
        'license_name': licenseName,
        'authorization_note': authorizationNote,
      },
    );
  }

  Future<List<Map<String, Object?>>> collaborationInvitations() async {
    final root = _map(await request('GET', '/api/collaborations'));
    return (root['invitations'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList();
  }

  Future<void> acceptCollaboration(String resourceId) async {
    await request('POST', '/api/resources/$resourceId/collaboration/accept');
  }

  Future<void> declineCollaboration(String resourceId) async {
    await request('DELETE', '/api/resources/$resourceId/collaboration');
  }

  Future<Map<String, Object?>> creatorCoinStats() async =>
      _map(await request('GET', '/api/creator/coins/stats'));

  Map<String, Object?> _map(Object? value) => value is Map
      ? value.cast<String, Object?>()
      : throw CreatorApiException(
          code: 'invalid_response',
          message: 'The OronBox server returned an invalid response',
          details: const {},
        );

  Future<Response<T>> _send<T>(
    Future<Response<T>> Function() operation, {
    required String stage,
  }) async {
    try {
      return await operation();
    } on DioException catch (error) {
      throw CreatorApiException.fromDio(error, stage: stage);
    }
  }

  static String _friendlyMessage(Object error) {
    final text = error.toString();
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }
}

class CreatorApiException implements CodedError {
  const CreatorApiException({
    required this.code,
    required this.message,
    required this.details,
  });

  factory CreatorApiException.fromDio(
    DioException error, {
    required String stage,
  }) {
    final status = error.response?.statusCode;
    final summary = safeHttpErrorSummary(error.response?.data);
    final serverMessage = summary['serverMessage']?.toString();
    final serverCode = summary['serverCode']?.toString();
    final message = serverMessage?.isNotEmpty == true
        ? serverMessage!
        : switch ((status, error.type)) {
            (413, _) => 'The selected file is too large',
            (400, _) => 'The server rejected the selected file',
            (_, DioExceptionType.connectionTimeout) ||
            (_, DioExceptionType.sendTimeout) ||
            (
              _,
              DioExceptionType.receiveTimeout,
            ) => 'The server did not respond in time',
            (_, DioExceptionType.connectionError) =>
              'Unable to connect to the OronBox server',
            _ =>
              status == null
                  ? 'The request to the OronBox server failed'
                  : 'The OronBox server returned HTTP $status',
          };
    return CreatorApiException(
      code: serverCode ?? (status == null ? 'network_error' : 'http_$status'),
      message: message,
      details: {
        'stage': stage,
        'endpoint': safeHttpEndpoint(error.requestOptions.uri),
        if (status != null) 'status': status,
        'errorType': error.type.name,
        if (httpRequestId(error.response) case final requestId?)
          'requestId': requestId,
      },
    );
  }

  @override
  final String code;
  @override
  final String message;
  @override
  final Map<String, Object?> details;

  @override
  String toString() => message;
}
