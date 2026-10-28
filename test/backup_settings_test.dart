import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fayma/services/backup/backup_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('conserve des identifiants stables', () async {
    final settings = BackupSettings();

    final device = await settings.deviceId();
    final shop = await settings.shopId();

    expect(device, isNotEmpty);
    expect(shop, isNotEmpty);
    expect(await settings.deviceId(), device);
    expect(await settings.shopId(), shop);

    await settings.setShopId('boutique-restauree');
    expect(await settings.shopId(), 'boutique-restauree');
  });

  test('mémorise la date de la dernière sauvegarde', () async {
    final settings = BackupSettings();
    final at = DateTime(2026, 10, 22, 9, 30);

    expect(await settings.lastBackupAt(), isNull);
    await settings.setLastBackupAt(at);

    expect(await settings.lastBackupAt(), at);
  });
}
