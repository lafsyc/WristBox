import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/steadylink/store_models.dart';
import 'package:oronbox/src/core/models/bt_models.dart';

void main() {
  Map<String, dynamic> item(
    String id,
    List<String> models, {
    int code = 1,
    bool published = true,
  }) => {
    'id': id,
    'appId': 'cats',
    'packageName': 'com.cats.$id',
    'versionCode': code,
    'supportedModels': models,
    'published': published,
  };
  test('four packages map to the seven explicitly supported models', () {
    final apps = groupStoreApps([
      item('336', ['n67', 'p67']),
      item('212', ['o66', 'band11']),
      item('192', ['n66']),
      item('432', ['o65', 'p65']),
    ]);
    expect(apps, hasLength(1));
    for (final entry in {
      'n67': '336',
      'p67': '336',
      'o66': '212',
      'band11': '212',
      'n66': '192',
      'o65': '432',
      'p65': '432',
    }.entries) {
      expect(apps.single.forModel(entry.key)?['id'], entry.value);
    }
    expect(apps.single.forModel('o66nfc'), isNull);
    expect(apps.single.forModel('m67'), isNull);
    expect(apps.single.forModel(null), isNull);
  });
  test('selects highest compatible version, excludes drafts and never falls back across models', () {
    final app = groupStoreApps([
      item('old', ['n67']),
      item('new', ['n67'], code: 10),
      item('other', ['o66'], code: 100),
      item('draft', ['n67'], code: 1000, published: false),
    ]).single;
    expect(app.forModel('n67')?['id'], 'new');
    expect(app.forModel('band11'), isNull);
  });
  test(
    'real device information wins; names do not confuse Pro or NFC variants',
    () {
      const device = MiWearState(
        name: '小米手环10',
        addr: 'AA',
        connectType: 'spp',
        codename: 'o66',
      );
      const info = SystemInfo(
        serialNumber: '',
        firmwareVersion: '',
        imei: '',
        model: 'miwear.watch.n67',
      );
      expect(storeModelForDevice(device, systemInfo: info), 'n67');
      expect(storeModelForDevice(device), 'o66');
      expect(
        storeModelForDevice(device.copyWith(name: '小米手环 11', codename: null)),
        'band11',
      );
      expect(
        storeModelForDevice(
          device.copyWith(name: 'Xiaomi Smart Band 10 NFC', codename: null),
        ),
        'o66nfc',
      );
      expect(
        storeModelForDevice(device.copyWith(name: '未知手环', codename: null)),
        isNull,
      );
    },
  );
}
