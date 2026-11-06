import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/device/core/xiaomi_wearable_catalog.dart';

const storeModelNames = <String, String>{
  'm67': '小米手环 8 Pro',
  'n66': '小米手环 9',
  'n67': '小米手环 9 Pro',
  'o66': '小米手环 10',
  'o66nfc': '小米手环 10 NFC',
  'p67': '小米手环 10 Pro',
  'band11': '小米手环 11',
  'l61': '小米手表 S1 Pro',
  'n62': '小米手表 S3',
  'o62': '小米手表 S4',
  'o62m': '小米手表 S4 15周年纪念版',
  'o63': '小米手表 S4 41mm',
  'p62': '小米手表 S5',
  'n65': 'REDMI Watch 4',
  'o65': 'REDMI Watch 5',
  'o65m': 'REDMI Watch 5 eSIM',
  'p65': 'REDMI Watch 6',
};

String? storeModelForDevice(MiWearState? device, {SystemInfo? systemInfo}) {
  if (device == null) return null;
  for (final value in [systemInfo?.model, device.codename, device.name]) {
    final identity = normalizeXiaomiWearableIdentity(value);
    if (identity != null && storeModelNames.containsKey(identity.codename)) {
      return identity.codename;
    }
    // No guessed hardware codename: accept only an explicit Band 11 name.
    final name = value?.toLowerCase().replaceAll(RegExp(r'\s+'), '') ?? '';
    if (['小米手环11', 'xiaomismartband11', 'xiaomiband11'].contains(name)) {
      return 'band11';
    }
  }
  return null;
}

List<String> supportedModels(Map<String, dynamic> item) =>
    (item['supportedModels'] as List? ?? const []).whereType<String>().toList();

class StoreApp {
  StoreApp(this.id, Iterable<Map<String, dynamic>> resources)
    : variants = resources.toList() {
    variants.sort((a, b) {
      final version = (b['versionCode'] as num).compareTo(
        a['versionCode'] as num,
      );
      if (version != 0) return version;
      final created = ((b['created'] as num?) ?? 0).compareTo(
        (a['created'] as num?) ?? 0,
      );
      return created != 0 ? created : '${b['id']}'.compareTo('${a['id']}');
    });
  }
  final String id;
  final List<Map<String, dynamic>> variants;
  Map<String, dynamic>? forModel(String? model) {
    if (model == null) return null;
    for (final variant in variants) {
      if (supportedModels(variant).contains(model)) return variant;
    }
    return null;
  }

  Map<String, dynamic> display(String? model) =>
      forModel(model) ?? variants.first;
  Set<String> get models => variants.expand(supportedModels).toSet();
}

List<StoreApp> groupStoreApps(List<Map<String, dynamic>> resources) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final resource in resources) {
    if (resource['published'] != true && resource['published'] != 1) continue;
    final id =
        (resource['appId'] as String?) ?? resource['packageName'] as String;
    grouped.putIfAbsent(id, () => []).add(resource);
  }
  return grouped.entries.map((e) => StoreApp(e.key, e.value)).toList();
}
