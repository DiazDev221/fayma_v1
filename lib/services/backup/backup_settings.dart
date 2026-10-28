import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Paramètres persistants de la sauvegarde : identifiants stables et date du
/// dernier export.
abstract class BackupSettingsStore {
  /// Identifiant stable de cette installation.
  Future<String> deviceId();

  /// Identifiant stable de la boutique. Il voyage dans la sauvegarde.
  Future<String> shopId();

  /// Adopte l'identifiant de boutique d'une sauvegarde restaurée.
  Future<void> setShopId(String shopId);

  Future<DateTime?> lastBackupAt();

  Future<void> setLastBackupAt(DateTime at);
}

class BackupSettings implements BackupSettingsStore {
  BackupSettings({SharedPreferences? preferences}) : _preferences = preferences;

  static const _deviceIdKey = 'fayma.backup.device_id';
  static const _shopIdKey = 'fayma.backup.shop_id';
  static const _lastBackupKey = 'fayma.backup.last_at';

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  @override
  Future<String> deviceId() => _stableId(_deviceIdKey, 'appareil');

  @override
  Future<String> shopId() => _stableId(_shopIdKey, 'boutique');

  Future<String> _stableId(String key, String prefix) async {
    final prefs = await _prefs;
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;

    final id = '$prefix-${DateTime.now().microsecondsSinceEpoch}-'
        '${_randomHex(8)}';
    await prefs.setString(key, id);
    return id;
  }

  @override
  Future<void> setShopId(String shopId) async {
    if (shopId.trim().isEmpty) return;
    final prefs = await _prefs;
    await prefs.setString(_shopIdKey, shopId);
  }

  @override
  Future<DateTime?> lastBackupAt() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_lastBackupKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  @override
  Future<void> setLastBackupAt(DateTime at) async {
    final prefs = await _prefs;
    await prefs.setString(_lastBackupKey, at.toUtc().toIso8601String());
  }

  String _randomHex(int byteCount) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
