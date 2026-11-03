import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Vérifie la configuration Android qui permet de retrouver les données
/// après une désinstallation, même sans export manuel.
void main() {
  group('sauvegarde automatique Android', () {
    late String manifest;
    late String backupRules;
    late String dataExtractionRules;

    setUpAll(() {
      manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      backupRules =
          File('android/app/src/main/res/xml/backup_rules.xml')
              .readAsStringSync();
      dataExtractionRules =
          File('android/app/src/main/res/xml/data_extraction_rules.xml')
              .readAsStringSync();
    });

    test('la sauvegarde système est activée et déclarée', () {
      expect(manifest, contains('android:allowBackup="true"'));
      expect(manifest, isNot(contains('android:allowBackup="false"')));
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      expect(manifest, contains('android:hasFragileUserData="true"'));
    });

    test('la base SQLite et les préférences sont sauvegardées', () {
      for (final rules in [backupRules, dataExtractionRules]) {
        expect(rules, contains('domain="file"'));
        expect(rules, contains('domain="sharedpref"'));
        expect(rules, contains('domain="database"'));
      }
      expect(dataExtractionRules, contains('<cloud-backup>'));
      expect(dataExtractionRules, contains('<device-transfer>'));
    });
  });
}
