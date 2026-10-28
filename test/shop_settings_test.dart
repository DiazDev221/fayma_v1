import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fayma/services/shop_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('enregistre, relit et retire le nom de la boutique', () async {
    final settings = ShopSettings();

    expect(await settings.readShopName(), isEmpty);

    await settings.saveShopName('  Boutique Awa  ');
    expect(await settings.readShopName(), 'Boutique Awa');

    await settings.saveShopName('   ');
    expect(await settings.readShopName(), isEmpty);
  });

  test('le nom est relu par une nouvelle instance', () async {
    final settings = ShopSettings();
    await settings.saveShopName('Boutique Awa');

    final other = ShopSettings();
    expect(await other.readShopName(), 'Boutique Awa');
  });
}
