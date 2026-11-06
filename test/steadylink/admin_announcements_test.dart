import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/admin_api.dart';
import 'package:oronbox/steadylink/admin_releases_page.dart';

class NoticeApi extends AdminApi {
  NoticeApi() : super(Dio());
  final reads = <String>[];
  final writes = <String>[];
  Map<String, dynamic>? notice;
  @override
  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    reads.add(path);
    return {
      'items': [if (notice != null) Map<String, dynamic>.from(notice!)],
    };
  }

  @override
  Future<void> change(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    writes.add('$method $path');
    if (path.endsWith('/publication')) {
      notice!['published'] = body['published'];
    } else {
      notice = {...?notice, ...body, 'id': 'test-notice', 'published': false};
    }
  }
}

void main() {
  testWidgets(
    'mobile admin drafts, previews, confirms publication and withdraws',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = NoticeApi();
      await tester.pumpWidget(
        MaterialApp(home: AdminAnnouncementsPage(connect: () async => api)),
      );
      await tester.pumpAndSettle();
      expect(api.reads, ['announcements']);
      expect(find.text('新建版本'), findsNothing);
      await tester.tap(find.text('新建公告'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '测试公告');
      await tester.enterText(find.byType(TextField).at(1), '这是一条测试弹窗。');
      await tester.tap(find.text('预览弹窗'));
      await tester.pumpAndSettle();
      expect(find.text('关闭预览'), findsOneWidget);
      expect(api.writes, isEmpty);
      await tester.tap(find.text('关闭预览'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存草稿'));
      await tester.pumpAndSettle();
      expect(api.notice!['platform'], 'android');
      expect(api.notice!['published'], false);
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(api.writes, ['POST announcements']);
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '发布').last);
      await tester.pumpAndSettle();
      expect(api.notice!['published'], true);
      expect(find.text('已发布'), findsOneWidget);
      await tester.tap(find.text('撤回'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '撤回').last);
      await tester.pumpAndSettle();
      expect(api.notice!['published'], false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed permission check never opens the editor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAnnouncementsPage(
          connect: () async => throw StateError('请使用管理员邮箱账号登录'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('重新检查权限'), findsOneWidget);
    expect(find.text('新建公告'), findsNothing);
    expect(find.textContaining('管理员'), findsWidgets);
  });
}
