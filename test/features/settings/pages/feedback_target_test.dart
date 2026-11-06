import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/features/settings/pages/feedback_page.dart';

void main() {
  test('feedback targets serialize reports with distinct kinds', () {
    const resource = FeedbackTarget(
      type: FeedbackTargetType.resource,
      source: 'oronbox',
      id: 'resource-id',
      name: 'Resource',
    );
    const comment = FeedbackTarget(
      type: FeedbackTargetType.comment,
      source: 'comment',
      id: 'comment-id',
      name: 'Comment author',
    );

    expect(resource.reportKind, 'resource_report');
    expect(comment.reportKind, 'comment_report');
  });
}
