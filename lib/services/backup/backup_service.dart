import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/credit_repository.dart';
import '../shop_settings.dart';
import 'backup_crypto.dart';
import 'backup_exception.dart';
import 'backup_format.dart';
import 'backup_serializer.dart';
import 'backup_settings.dart';

/// Contenu chiffré d'une sauvegarde, avant écriture sur disque.
class BackupData {
  const BackupData({
    required this.bytes,
    required this.fileName,
    required this.createdAt,
    required this.clientCount,
    required this.operationCount,
  });

  final Uint8List bytes;
  final String fileName;
  final DateTime createdAt;
  final int clientCount;
  final int operationCount;

  int get byteLength => bytes.length;
}

/// Résultat d'un export, prêt à être partagé.
class BackupExport {
  const BackupExport({
    required this.file,
    required this.createdAt,
    required this.clientCount,
    required this.operationCount,
  });

  final File file;
  final DateTime createdAt;
  final int clientCount;
  final int operationCount;
}

/// Sauvegarde déchiffrée et validée, en attente de confirmation.
class BackupPreview {
  const BackupPreview({
    required this.payload,
    required this.sourceName,
  });

  final BackupPayload payload;
  final String sourceName;
}

/// Orchestre l'export et la restauration d'une sauvegarde chiffrée.
class BackupService {
  BackupService({
    required this.repository,
    required this.settings,
    this.shopSettings,
    BackupSerializer serializer = const BackupSerializer(),
    BackupCrypto crypto = const BackupCrypto(),
    Future<Directory> Function()? directoryProvider,
    Future<String> Function()? appVersionProvider,
  })  : _serializer = serializer,
        _crypto = crypto,
        _directoryProvider = directoryProvider ?? getTemporaryDirectory,
        _appVersionProvider = appVersionProvider ?? _defaultAppVersion;

  /// Taille maximale acceptée pour un fichier importé (protection mémoire).
  static const int maxBackupBytes = 64 * 1024 * 1024;

  final CreditRepository repository;
  final BackupSettingsStore settings;

  /// Paramètres de la boutique, pour inclure son nom dans la sauvegarde et
  /// le restaurer. Facultatif : les tests et les usages sans boutique
  /// continuent de fonctionner.
  final ShopSettingsStore? shopSettings;

  final BackupSerializer _serializer;
  final BackupCrypto _crypto;
  final Future<Directory> Function() _directoryProvider;
  final Future<String> Function() _appVersionProvider;

  Future<DateTime?> lastBackupAt() => settings.lastBackupAt();

  Future<void> markBackupDone(DateTime at) => settings.setLastBackupAt(at);

  /// Crée le contenu chiffré d'une sauvegarde, sans écrire de fichier.
  Future<BackupData> createData() async {
    final snapshot = await repository.snapshot();
    final appVersion = await _appVersionProvider();
    final deviceId = await settings.deviceId();
    final shopId = await settings.shopId();
    final shopName = await _readShopName();
    final createdAt = DateTime.now();

    final clear = _serializer.encode(
      snapshot: snapshot,
      appVersion: appVersion,
      schemaVersion: repository.schemaVersion,
      deviceId: deviceId,
      shopId: shopId,
      shopName: shopName,
      createdAt: createdAt,
    );
    final encrypted = await _crypto.encryptText(clear);

    return BackupData(
      bytes: Uint8List.fromList(utf8.encode(encrypted)),
      fileName: _fileName(createdAt),
      createdAt: createdAt,
      clientCount: snapshot.clientCount,
      operationCount: snapshot.operationCount,
    );
  }

  /// Crée un fichier chiffré dans le dossier temporaire de l'application.
  Future<BackupExport> export() async {
    final data = await createData();

    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, data.fileName));
    final partial = File('${file.path}.part');
    await partial.writeAsBytes(data.bytes, flush: true);
    await partial.rename(file.path);

    return BackupExport(
      file: file,
      createdAt: data.createdAt,
      clientCount: data.clientCount,
      operationCount: data.operationCount,
    );
  }

  /// Lit et déchiffre un fichier sans toucher aux données existantes.
  ///
  /// [legacyRecoveryCode] n'est utile que pour les sauvegardes créées avant
  /// la suppression du code de récupération.
  Future<BackupPreview> inspectFile(
    File file, {
    String? legacyRecoveryCode,
  }) async {
    final int length;
    try {
      length = await file.length();
    } on FileSystemException catch (error) {
      throw BackupException(
        'Impossible de lire le fichier de sauvegarde.',
        cause: error,
      );
    }
    if (length == 0) {
      throw const BackupException('Le fichier de sauvegarde est vide.');
    }
    if (length > maxBackupBytes) {
      throw const BackupException(
        'Ce fichier est trop volumineux pour être une sauvegarde Fayma.',
      );
    }

    final String content;
    try {
      content = await file.readAsString();
    } on FileSystemException catch (error) {
      throw BackupException(
        'Impossible de lire le fichier de sauvegarde.',
        cause: error,
      );
    } on FormatException catch (error) {
      throw BackupException(
        'Ce fichier n\'est pas une sauvegarde Fayma valide.',
        cause: error,
      );
    }
    return _inspectText(
      content,
      sourceName: p.basename(file.path),
      legacyRecoveryCode: legacyRecoveryCode,
    );
  }

  /// Variante pour un fichier choisi via le sélecteur Android, qui ne fournit
  /// pas toujours un chemin local.
  Future<BackupPreview> inspectBytes(
    Uint8List bytes, {
    required String sourceName,
    String? legacyRecoveryCode,
  }) async {
    if (bytes.isEmpty) {
      throw const BackupException('Le fichier de sauvegarde est vide.');
    }
    if (bytes.length > maxBackupBytes) {
      throw const BackupException(
        'Ce fichier est trop volumineux pour être une sauvegarde Fayma.',
      );
    }

    final String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException catch (error) {
      throw BackupException(
        'Ce fichier n\'est pas une sauvegarde Fayma valide.',
        cause: error,
      );
    }
    return _inspectText(
      content,
      sourceName: sourceName,
      legacyRecoveryCode: legacyRecoveryCode,
    );
  }

  Future<BackupPreview> _inspectText(
    String content, {
    required String sourceName,
    String? legacyRecoveryCode,
  }) async {
    final clear = await _crypto.decryptText(
      content,
      legacyRecoveryCode: legacyRecoveryCode,
    );
    final payload = _serializer.decode(clear);

    if (payload.schemaVersion > repository.schemaVersion) {
      throw BackupException(
        'Cette sauvegarde vient d\'une version plus récente de Fayma '
        '(données v${payload.schemaVersion}). Mettez l\'application à jour.',
      );
    }
    if (payload.schemaVersion < repository.schemaVersion) {
      throw BackupException(
        'Cette sauvegarde utilise une ancienne version des données '
        '(v${payload.schemaVersion}). Fayma doit d\'abord la convertir.',
      );
    }

    return BackupPreview(
      payload: payload,
      sourceName: sourceName,
    );
  }

  /// Remplace toutes les données par celles de [preview].
  Future<void> restore(BackupPreview preview) async {
    await repository.replaceAll(preview.payload.snapshot);
    try {
      await settings.setShopId(preview.payload.shopId);

      // Le nom de la boutique fait partie de la sauvegarde. Une sauvegarde
      // ancienne (nom vide) ne doit pas effacer celui déjà saisi.
      final shopName = preview.payload.shopName.trim();
      if (shopName.isNotEmpty) {
        await shopSettings?.saveShopName(shopName);
      }
    } catch (_) {
      // Les données sont déjà restaurées ; l'identifiant de boutique et le
      // nom ne sont que des informations de continuité.
    }
  }

  Future<String> _readShopName() async {
    try {
      return (await shopSettings?.readShopName())?.trim() ?? '';
    } catch (error) {
      debugPrint('Lecture du nom de la boutique pour la sauvegarde : $error');
      return '';
    }
  }

  static Future<String> _defaultAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber.trim();
      return build.isEmpty ? info.version : '${info.version}+$build';
    } catch (_) {
      return 'inconnue';
    }
  }

  String _fileName(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'fayma-${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}'
        '.$backupFileExtension';
  }
}
