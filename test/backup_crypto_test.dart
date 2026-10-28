import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fayma/services/backup/backup_crypto.dart';
import 'package:fayma/services/backup/backup_exception.dart';
import 'package:fayma/services/backup/legacy_recovery_code.dart';

void main() {
  // Paramètres réduits : les tests restent rapides tout en exerçant le vrai
  // chemin Argon2id + AES-GCM.
  const crypto = BackupCrypto(
    memoryKib: 128,
    iterations: 1,
    parallelism: 1,
  );
  const legacyCode = 'ABCD2345EFGH6789JKMN2345';

  test('chiffre puis déchiffre le contenu', () async {
    const clear = '{"clients":[],"operations":[]}';
    final envelope = await crypto.encryptText(clear);
    final decoded = await crypto.decryptText(envelope);

    expect(decoded, clear);
  });

  test('le conteneur indique la clé interne', () async {
    final envelope = await crypto.encryptText('secret');
    final json = jsonDecode(envelope) as Map<String, dynamic>;

    expect(json['format'], 'fayma-backup');
    expect(json['format_version'], 1);
    expect(json['key_source'], 'app');
    expect(json.containsKey('code'), isFalse);
  });

  test('refuse un contenu modifié', () async {
    final envelope = await crypto.encryptText('secret');
    final json = jsonDecode(envelope) as Map<String, dynamic>;
    final cipherText = base64Decode(json['ciphertext'] as String);
    cipherText[0] = cipherText[0] ^ 0x01;
    json['ciphertext'] = base64Encode(cipherText);

    await expectLater(
      crypto.decryptText(jsonEncode(json)),
      throwsA(isA<BackupException>()),
    );
  });

  test('refuse une version de conteneur plus récente', () async {
    final envelope = await crypto.encryptText('secret');
    final json = jsonDecode(envelope) as Map<String, dynamic>;
    json['format_version'] = 2;

    await expectLater(
      crypto.decryptText(jsonEncode(json)),
      throwsA(isA<BackupException>()),
    );
  });

  test('refuse des paramètres Argon2id déraisonnables', () async {
    final envelope = await crypto.encryptText('secret');
    final json = jsonDecode(envelope) as Map<String, dynamic>;
    json['kdf_memory_kib'] = 999999999;

    await expectLater(
      crypto.decryptText(jsonEncode(json)),
      throwsA(isA<BackupException>()),
    );
  });

  test('refuse une source de clé inconnue', () async {
    final envelope = await crypto.encryptText('secret');
    final json = jsonDecode(envelope) as Map<String, dynamic>;
    json['key_source'] = 'autre';

    await expectLater(
      crypto.decryptText(jsonEncode(json)),
      throwsA(isA<BackupException>()),
    );
  });

  test('ouvre une ancienne sauvegarde avec son code', () async {
    const clear = '{"clients":[]}';
    final legacyEnvelope = await _legacyEnvelope(clear, legacyCode);

    final decoded = await crypto.decryptText(
      legacyEnvelope,
      legacyRecoveryCode: legacyCode,
    );

    expect(decoded, clear);
  });

  test('une ancienne sauvegarde sans code demande le code', () async {
    final legacyEnvelope = await _legacyEnvelope('secret', legacyCode);

    await expectLater(
      crypto.decryptText(legacyEnvelope),
      throwsA(
        isA<BackupException>()
            .having(
              (e) => e.legacyCodeRequired,
              'legacyCodeRequired',
              isTrue,
            )
            .having((e) => e.wrongLegacyCode, 'wrongLegacyCode', isFalse),
      ),
    );
  });

  test('refuse un mauvais code pour une ancienne sauvegarde', () async {
    final legacyEnvelope = await _legacyEnvelope('secret', legacyCode);

    await expectLater(
      crypto.decryptText(
        legacyEnvelope,
        legacyRecoveryCode: 'ZZZZZZZZZZZZZZZZZZZZZZZZ',
      ),
      throwsA(
        isA<BackupException>()
            .having(
              (e) => e.legacyCodeRequired,
              'legacyCodeRequired',
              isTrue,
            )
            .having((e) => e.wrongLegacyCode, 'wrongLegacyCode', isTrue),
      ),
    );
  });

  test('normalise un ancien code', () {
    expect(normalizeLegacyRecoveryCode(' abcd-efgh ijkl '), 'ABCDEFGH1JK1');
  });
}

/// Produit un conteneur au format des sauvegardes antérieures : chiffré avec
/// un code, sans champ `key_source`.
Future<String> _legacyEnvelope(String clear, String code) async {
  final legacyCrypto = BackupCrypto(
    memoryKib: 128,
    iterations: 1,
    parallelism: 1,
    keyMaterial: code,
  );
  final envelope = await legacyCrypto.encryptText(clear);
  final json = jsonDecode(envelope) as Map<String, dynamic>;
  json.remove('key_source');
  return jsonEncode(json);
}
