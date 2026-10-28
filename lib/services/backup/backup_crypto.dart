import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'backup_exception.dart';
import 'backup_format.dart';
import 'legacy_recovery_code.dart';

/// Chiffre et déchiffre le contenu d'une sauvegarde.
///
/// Les nouvelles sauvegardes utilisent une clé interne à l'application : aucun
/// code n'est demandé au commerçant. Le fichier produit est un JSON contenant
/// les paramètres Argon2id, le sel, le nonce, le texte chiffré AES-256-GCM et
/// son code d'authentification.
///
/// Les sauvegardes créées avant cette simplification étaient chiffrées avec un
/// code de récupération. Elles restent lisibles en fournissant ce code.
class BackupCrypto {
  const BackupCrypto({
    this.memoryKib = 65536,
    this.iterations = 3,
    this.parallelism = 1,
    this.keyMaterial = defaultKeyMaterial,
  })  : assert(memoryKib >= 8 * parallelism),
        assert(iterations >= 1),
        assert(parallelism >= 1);

  /// Matériau de clé des nouvelles sauvegardes.
  ///
  /// Il est embarqué dans l'application : il empêche la lecture directe d'un
  /// fichier `.fayma`, sans remplacer un mot de passe utilisateur.
  static const String defaultKeyMaterial =
      'bb787c7b911a2b1fabb5f4d5d6da3c3b04163026fe6b4f33d4503bd5153cc3c9';

  /// Mémoire Argon2id, en blocs de 1 Kio. 65 536 = 64 Mio.
  final int memoryKib;
  final int iterations;
  final int parallelism;

  /// Secret utilisé pour les nouvelles sauvegardes. Les tests de compatibilité
  /// le remplacent par un ancien code de récupération.
  final String keyMaterial;

  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _maxMemoryKib = 131072;
  static const int _maxIterations = 10;
  static const int _maxParallelism = 4;
  static const String _appKeySource = 'app';

  static final List<int> _additionalData =
      utf8.encode('$backupFormat:v$backupFormatVersion');

  Future<String> encryptText(String plainText) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = await _deriveKey(keyMaterial, salt);
    final compressed = GZipCodec().encode(utf8.encode(plainText));

    final box = await AesGcm.with256bits().encrypt(
      compressed,
      secretKey: key,
      nonce: nonce,
      aad: _additionalData,
    );

    return jsonEncode({
      'format': backupFormat,
      'format_version': backupFormatVersion,
      'kdf': 'argon2id',
      'key_source': _appKeySource,
      'kdf_memory_kib': memoryKib,
      'kdf_iterations': iterations,
      'kdf_parallelism': parallelism,
      'salt': base64Encode(salt),
      'cipher': 'aes-256-gcm',
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  Future<String> decryptText(
    String envelope, {
    String? legacyRecoveryCode,
  }) async {
    final Map<String, Object?> root;
    try {
      final decoded = jsonDecode(envelope);
      if (decoded is! Map) {
        throw const FormatException('Objet JSON attendu.');
      }
      root = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } on FormatException catch (error) {
      throw BackupException(
        'Ce fichier n\'est pas une sauvegarde Fayma valide.',
        cause: error,
      );
    }

    if (root['format'] != backupFormat) {
      throw const BackupException(
        'Ce fichier n\'est pas une sauvegarde Fayma.',
      );
    }
    if (root['format_version'] != backupFormatVersion) {
      throw const BackupException(
        'Cette sauvegarde utilise une version de format non prise en charge.',
      );
    }
    if (root['kdf'] != 'argon2id' || root['cipher'] != 'aes-256-gcm') {
      throw const BackupException(
        'Cette sauvegarde utilise un chiffrement non pris en charge.',
      );
    }

    final memory = _intField(root, 'kdf_memory_kib');
    final rounds = _intField(root, 'kdf_iterations');
    final parallel = _intField(root, 'kdf_parallelism');
    if (memory < 8 * parallel ||
        memory > _maxMemoryKib ||
        rounds < 1 ||
        rounds > _maxIterations ||
        parallel < 1 ||
        parallel > _maxParallelism) {
      throw const BackupException(
        'Les paramètres de chiffrement de cette sauvegarde sont invalides.',
      );
    }

    final salt = _bytesField(root, 'salt', expectedLength: _saltLength);
    final nonce = _bytesField(
      root,
      'nonce',
      expectedLength: _nonceLength,
    );
    final mac = _bytesField(root, 'mac', expectedLength: _macLength);
    final cipherText = _bytesField(root, 'ciphertext');
    if (cipherText.isEmpty) {
      throw const BackupException('Le fichier de sauvegarde est vide.');
    }

    final keySource = root['key_source'];
    final bool legacy;
    final String secret;
    if (keySource == _appKeySource) {
      legacy = false;
      secret = keyMaterial;
    } else if (keySource == null) {
      legacy = true;
      final code = normalizeLegacyRecoveryCode(legacyRecoveryCode ?? '');
      if (code.isEmpty) {
        throw const BackupException(
          'Cette sauvegarde a été créée par une ancienne version. '
          'Saisissez son code de récupération.',
          legacyCodeRequired: true,
        );
      }
      secret = code;
    } else {
      throw const BackupException(
        'Cette sauvegarde utilise un chiffrement non pris en charge.',
      );
    }

    final key = await _deriveKey(
      secret,
      salt,
      memory: memory,
      rounds: rounds,
      parallel: parallel,
    );

    final List<int> compressed;
    try {
      compressed = await AesGcm.with256bits().decrypt(
        SecretBox(
          cipherText,
          nonce: nonce,
          mac: Mac(mac),
        ),
        secretKey: key,
        aad: _additionalData,
      );
    } on SecretBoxAuthenticationError catch (error) {
      if (legacy) {
        throw BackupException(
          'Code de récupération incorrect, ou fichier de sauvegarde '
          'endommagé.',
          cause: error,
          legacyCodeRequired: true,
          wrongLegacyCode: true,
        );
      }
      throw BackupException(
        'Le fichier de sauvegarde est endommagé.',
        cause: error,
      );
    } on FormatException catch (error) {
      throw BackupException(
        'Le fichier de sauvegarde est endommagé.',
        cause: error,
      );
    }

    try {
      final clearBytes = GZipCodec().decode(compressed);
      return utf8.decode(clearBytes);
    } on FormatException catch (error) {
      throw BackupException(
        'Le contenu de la sauvegarde est endommagé.',
        cause: error,
      );
    }
  }

  Future<SecretKey> _deriveKey(
    String secret,
    List<int> salt, {
    int? memory,
    int? rounds,
    int? parallel,
  }) {
    final algorithm = Argon2id(
      parallelism: parallel ?? parallelism,
      memory: memory ?? memoryKib,
      iterations: rounds ?? iterations,
      hashLength: 32,
    );
    return algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: salt,
    );
  }

  int _intField(Map<String, Object?> root, String field) {
    final value = root[field];
    if (value is int) return value;
    throw BackupException(
      'Champ de chiffrement manquant ou invalide : $field.',
    );
  }

  List<int> _bytesField(
    Map<String, Object?> root,
    String field, {
    int? expectedLength,
  }) {
    final value = root[field];
    if (value is! String) {
      throw BackupException(
        'Champ de chiffrement manquant ou invalide : $field.',
      );
    }
    try {
      final bytes = base64Decode(value);
      if (expectedLength != null && bytes.length != expectedLength) {
        throw BackupException(
          'Champ de chiffrement invalide : $field.',
        );
      }
      return bytes;
    } on FormatException catch (error) {
      throw BackupException(
        'Champ de chiffrement invalide : $field.',
        cause: error,
      );
    }
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
