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

List<int>? firmwareParts(String value) {
  final raw = value.trim();
  if (!RegExp(r'^[0-9]{1,6}(\.[0-9]{1,6}){1,5}$').hasMatch(raw)) return null;
  final parts = raw.split('.').map(int.parse).toList();
  return [...parts, ...List.filled(6 - parts.length, 0)];
}

int compareFirmware(List<int> a, List<int> b) {
  for (var i = 0; i < 6; i++) {
    final result = a[i].compareTo(b[i]);
    if (result != 0) return result;
  }
  return 0;
}

String? firmwareMismatch(
  Map<String, dynamic> item,
  String model,
  String firmware,
) {
  final rules = (item['firmwareRules'] as List? ?? const []).whereType<Map>();
  final rule = rules.where((r) => r['model'] == model).firstOrNull;
  if (rule == null || rule['mode'] == 'any') return null;
  final current = firmwareParts(firmware);
  if (current == null) return '此安装包限制固件版本，请连接手环并刷新设备信息后再试。';
  if (rule['mode'] == 'exact') {
    final versions = (rule['versions'] as List? ?? const [])
        .whereType<String>();
    if (versions.any(
      (v) =>
          firmwareParts(v) != null &&
          compareFirmware(current, firmwareParts(v)!) == 0,
    )) {
      return null;
    }
    return '固件不匹配：当前 $firmware，需要 ${versions.join('、')}。';
  }
  final min = firmwareParts('${rule['minVersion'] ?? ''}');
  final max = firmwareParts('${rule['maxVersion'] ?? ''}');
  if (rule['mode'] == 'range' &&
      min != null &&
      max != null &&
      compareFirmware(current, min) >= 0 &&
      compareFirmware(current, max) <= 0) {
    return null;
  }
  return '固件不匹配：当前 $firmware，需要 ${rule['minVersion']} 至 ${rule['maxVersion']}。';
}

String firmwareSummary(Map<String, dynamic> item) =>
    (item['firmwareRules'] as List? ?? const [])
        .whereType<Map>()
        .map((r) {
          final name = storeModelNames[r['model']] ?? r['model'];
          final detail = switch (r['mode']) {
            'exact' => (r['versions'] as List? ?? []).join('、'),
            'range' => '${r['minVersion']} 至 ${r['maxVersion']}',
            _ => '不限固件',
          };
          return '$name：$detail';
        })
        .join('\n');

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
  Map<String, dynamic>? forDevice(String? model, String firmware) {
    if (model == null) return null;
    return variants
        .where(
          (v) =>
              supportedModels(v).contains(model) &&
              firmwareMismatch(v, model, firmware) == null,
        )
        .firstOrNull;
  }

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
