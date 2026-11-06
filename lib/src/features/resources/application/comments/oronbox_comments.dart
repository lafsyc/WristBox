import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/commands/command_protocol.dart';
import 'package:oronbox/src/core/errors/coded_error.dart';
import 'package:oronbox/src/host/application_host_provider.dart';

final oronBoxCommentsApiProvider = Provider(
  (ref) => OronBoxCommentsApi(ref.watch(applicationHostProvider)),
);

class OronBoxCommentsApi {
  OronBoxCommentsApi(this._host);
  final OronBoxCommandBus _host;

  Future<List<OronBoxComment>> list(
    String resourceId, {
    DateTime? before,
  }) async {
    final value = await _execute('comment.list', {
      'resource': resourceId,
      if (before != null) 'before': before.toUtc().toIso8601String(),
    });
    final root = value is Map
        ? value.cast<String, Object?>()
        : const <String, Object?>{};
    return (root['comments'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => OronBoxComment.fromJson(item.cast<String, Object?>()))
        .where((comment) => !comment.deleted)
        .toList();
  }

  Future<OronBoxComment> create(
    String resourceId,
    String body, {
    String parentId = '',
  }) async {
    final value = await _execute('comment.create', {
      'resource': resourceId,
      'body': body,
      'parentId': parentId,
    });
    return OronBoxComment.fromJson((value as Map).cast<String, Object?>());
  }

  Future<void> delete(String commentId) =>
      _execute('comment.delete', {'comment': commentId});

  Future<Object?> _execute(String method, Map<String, Object?> params) async {
    final result = await _host.execute(
      OronBoxCommand(method: method, params: params),
    );
    if (!result.ok) {
      throw CommentApiException(result.error!.code, result.error!.message);
    }
    return result.value;
  }
}

class CommentApiException implements CodedError {
  const CommentApiException(this.code, this.message);

  @override
  final String code, message;

  @override
  Object? get details => null;

  @override
  String toString() => message;
}

class OronBoxComment {
  const OronBoxComment({
    required this.id,
    required this.body,
    required this.username,
    required this.avatarUrl,
    required this.bandBbsUserId,
    required this.createdAt,
    required this.deleted,
    required this.moderationState,
    required this.moderationAction,
    required this.replies,
  });
  final String id, body, username, avatarUrl, moderationState;
  final String moderationAction;
  final int bandBbsUserId;
  final DateTime createdAt;
  final bool deleted;
  final List<OronBoxComment> replies;

  factory OronBoxComment.fromJson(Map<String, Object?> json) => OronBoxComment(
    id: json['id']?.toString() ?? '',
    body: json['body']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    avatarUrl: json['avatar_url']?.toString() ?? '',
    bandBbsUserId: (json['bandbbs_user_id'] as num?)?.toInt() ?? 0,
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
    deleted: json['deleted'] == true,
    moderationState: json['moderation_state']?.toString() ?? 'visible',
    moderationAction: json['moderation_action']?.toString() ?? '',
    replies: (json['replies'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => OronBoxComment.fromJson(item.cast<String, Object?>()))
        .where((comment) => !comment.deleted)
        .toList(),
  );

  OronBoxComment copyWith({List<OronBoxComment>? replies}) => OronBoxComment(
    id: id,
    body: body,
    username: username,
    avatarUrl: avatarUrl,
    bandBbsUserId: bandBbsUserId,
    createdAt: createdAt,
    deleted: deleted,
    moderationState: moderationState,
    moderationAction: moderationAction,
    replies: replies ?? this.replies,
  );
}
