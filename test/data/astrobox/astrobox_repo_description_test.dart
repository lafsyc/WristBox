import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/data/astrobox/astrobox_repo_description.dart';

void main() {
  test('normalizes AstroBox manifest presentation markup only', () {
    const raw =
        '为Canopus模块打造的手环端管理器与注入器。<br/><span '
        'style="color: #ff6b6b; font-size: 26px; font-weight: 700">'
        '注意！！！</span>';

    final result = normalizeAstroBoxRepoDescription(raw);

    expect(result.isHtml, isTrue);
    expect(result.value, contains('手环端管理器与注入器。<br/>'));
    expect(result.value, contains('<strong>注意！！！</strong>'));
    expect(result.value, isNot(contains('<span')));
    expect(result.value, isNot(contains('style=')));
  });

  test('keeps ordinary AstroBox descriptions as plain text', () {
    final result = normalizeAstroBoxRepoDescription('普通描述 & 说明');

    expect(result.isHtml, isFalse);
    expect(result.value, '普通描述 & 说明');
  });
}
