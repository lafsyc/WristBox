import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/device/core/xiaomi_wearable_catalog.dart';

void main() {
  group('Xiaomi wearable identity normalization', () {
    test('Band 11 product identities and Bluetooth suffixes retain NFC', () {
      for (final name in [
        'q66nfc',
        'miwear.watch.q66nfc',
        'band11nfc',
        'Xiaomi Smart Band 11 NFC 3AE8',
        '小米手环11 NFC版 3ae8',
      ]) {
        expect(
          normalizeXiaomiWearableIdentity(name)?.codename,
          'q66nfc',
          reason: name,
        );
      }
      for (final name in [
        'q66',
        'q66cn',
        'miwear.watch.q66cn',
        'band11',
        'Xiaomi Smart Band 11 3AE8',
      ]) {
        expect(
          normalizeXiaomiWearableIdentity(name)?.codename,
          'q66',
          reason: name,
        );
      }
      expect(
        normalizeXiaomiWearableIdentity('Xiaomi Smart Band 11 Pro 3AE8'),
        isNull,
      );
      expect(
        normalizeXiaomiWearableIdentity('Xiaomi Smart Band 111 3AE8'),
        isNull,
      );
    });
    test('normalizes AB v2 id, upstream model, hardware model and names', () {
      final inputs = [
        'xmb9p',
        'miwear.watch.n67cn',
        'M2401B1',
        'n67',
        'N67',
        '小米手环9 Pro',
        'Xiaomi Smart Band 9 Pro',
      ];

      for (final input in inputs) {
        final identity = normalizeXiaomiWearableIdentity(input);
        expect(identity?.codename, 'n67', reason: input);
        expect(identity?.displayName, 'Xiaomi Smart Band 9 Pro');
      }
    });

    test('normalizes REDMI Watch 5 eSIM aliases', () {
      final inputs = [
        'xmrw5xring',
        'miwear.watch.o65m',
        'M2428W1',
        'o65m',
        'REDMI Watch 5 eSIM',
        '红米手表5 eSIM',
      ];

      for (final input in inputs) {
        final identity = normalizeXiaomiWearableIdentity(input);
        expect(identity?.codename, 'o65m', reason: input);
        expect(identity?.displayName, 'REDMI Watch 5 eSIM');
      }
    });

    test('groups only Xiaomi Watch S3 and S4 variants as series', () {
      final grouped = xiaomiWearableIdentities.values
          .where((identity) => identity.seriesName != null)
          .map((identity) => identity.codename)
          .toSet();

      expect(grouped, {'n62', 'o62', 'o62m', 'o63'});
      expect(xiaomiWearableIdentities['l61']?.seriesName, isNull);
      expect(xiaomiWearableIdentities['p62']?.seriesName, isNull);
      expect(xiaomiWearableIdentities['o65']?.seriesName, isNull);
    });
  });
}
