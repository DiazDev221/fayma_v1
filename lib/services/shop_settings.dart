import 'package:shared_preferences/shared_preferences.dart';

/// Paramètres de la boutique : nom utilisé dans les SMS.
///
/// Le nom est stocké dans les préférences locales. Il n'est pas un secret :
/// il sert uniquement de signature dans les SMS envoyés aux clients.
abstract class ShopSettingsStore {
  /// Nom de la boutique, ou chaîne vide s'il n'a pas encore été renseigné.
  Future<String> readShopName();

  /// Enregistre le nom. Un nom vide retire la signature des SMS.
  Future<void> saveShopName(String name);
}

class ShopSettings implements ShopSettingsStore {
  ShopSettings({SharedPreferences? preferences}) : _preferences = preferences;

  static const _shopNameKey = 'fayma.shop.name';

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  @override
  Future<String> readShopName() async {
    final prefs = await _prefs;
    return prefs.getString(_shopNameKey)?.trim() ?? '';
  }

  @override
  Future<void> saveShopName(String name) async {
    final prefs = await _prefs;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_shopNameKey);
    } else {
      await prefs.setString(_shopNameKey, trimmed);
    }
  }
}
