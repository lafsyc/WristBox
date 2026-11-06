import 'dart:convert';

class CreatorBandBbsBindingEntry {
  const CreatorBandBbsBindingEntry({
    required this.categoryId,
    required this.resourceId,
    this.url = '',
  });

  final String categoryId;
  final String resourceId;
  final String url;
}

List<CreatorBandBbsBindingEntry> parseCreatorBandBbsBinding(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map) return const [];
  final entries = <CreatorBandBbsBindingEntry>[];
  for (final entry in decoded.entries) {
    final categoryId = entry.key.toString();
    final item = entry.value;
    final resourceId = item is Map
        ? item['resource_id']?.toString() ?? ''
        : item?.toString() ?? '';
    if (categoryId.isEmpty || resourceId.isEmpty) continue;
    entries.add(
      CreatorBandBbsBindingEntry(
        categoryId: categoryId,
        resourceId: resourceId,
        url: item is Map ? item['url']?.toString() ?? '' : '',
      ),
    );
  }
  entries.sort(
    (a, b) => (int.tryParse(a.categoryId) ?? 0).compareTo(
      int.tryParse(b.categoryId) ?? 0,
    ),
  );
  return entries;
}

Map<String, Object?>? creatorExternalBinding(
  List<Map<String, Object?>> bindings,
  String provider,
) => bindings.where((binding) => binding['provider'] == provider).firstOrNull;
