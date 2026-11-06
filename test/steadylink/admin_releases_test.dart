import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/admin_api.dart';
import 'package:oronbox/steadylink/admin_releases_page.dart';

class ReleaseApi extends AdminApi {
  ReleaseApi() : super(Dio());
  final changes = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, dynamic>? query,
  ]) async => {
    'items': path == 'client-releases'
        ? [
            {
              'id': 'test',
              'platform': 'android',
              'version': '0.9.1',
              'build': 18,
              'title': '新的更新',
              'notes': '提升稳定性',
              'mandatory': true,
              'published': false,
              'size': 102400,
            },
          ]
        : [],
  };
  @override
  Future<void> change(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    changes.add({'method': method, 'path': path, ...body});
  }
}

void main() {
  testWidgets(
    'publishing requires confirmation and notices are saved as drafts',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReleaseApi();
      await tester.pumpWidget(MaterialApp(home: AdminReleasesPage(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(find.textContaining('强制更新，低版本用户'), findsOneWidget);
      expect(api.changes, isEmpty);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, '发布')));
      await tester.pumpAndSettle();
      expect(api.changes.single['published'], true);
      await tester.tap(find.text('发布公告'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建公告'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '公告标题');
      await tester.enterText(find.byType(TextField).at(1), '公告正文');
      await tester.tap(find.text('保存草稿'));
      await tester.pumpAndSettle();
      expect(api.changes.last['path'], 'announcements');
      expect(api.changes.last['body'], '公告正文');
      expect(api.changes.last.containsKey('published'), false);
      expect(tester.takeException(), isNull);
    },
  );
}
