import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// The AstroBox repository has manifests whose description field contains
/// literal, presentation-oriented HTML. This normalizer is deliberately
/// scoped to that source; community descriptions use different semantics.
class AstroBoxRepoDescription {
  const AstroBoxRepoDescription({required this.value, required this.isHtml});

  final String value;
  final bool isHtml;
}

AstroBoxRepoDescription normalizeAstroBoxRepoDescription(String raw) {
  final fragment = html_parser.parseFragment(raw);
  final serialized = fragment.nodes.map(_serializeNode).join().trim();
  final isHtml = RegExp(r'<(?:br|strong|em|del)>').hasMatch(serialized);
  return AstroBoxRepoDescription(
    value: isHtml
        ? serialized
        : fragment.nodes.map(_plainTextNode).join().trim(),
    isHtml: isHtml,
  );
}

String _plainTextNode(dom.Node node) {
  if (node is dom.Text) return node.data;
  if (node is! dom.Element) return '';
  if (node.localName == 'br') return '\n';
  if (node.localName == 'script' || node.localName == 'style') return '';
  return node.nodes.map(_plainTextNode).join();
}

String _serializeNode(dom.Node node) {
  if (node is dom.Text) return _escapeHtml(node.data);
  if (node is! dom.Element) return '';

  final name = node.localName?.toLowerCase();
  if (name == 'script' || name == 'style' || name == 'iframe') return '';
  if (name == 'br') return '<br/>';

  final children = node.nodes.map(_serializeNode).join();
  if (children.isEmpty) return '';

  return switch (name) {
    'b' || 'strong' => '<strong>$children</strong>',
    'i' || 'em' => '<em>$children</em>',
    's' || 'del' => '<del>$children</del>',
    'span' => _isBold(node) ? '<strong>$children</strong>' : children,
    _ => children,
  };
}

bool _isBold(dom.Element element) {
  final style = element.attributes['style']?.toLowerCase() ?? '';
  return RegExp(r'font-weight\s*:\s*(?:bold|[6-9]00)').hasMatch(style);
}

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
