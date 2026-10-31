import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/providers.dart';
import 'package:fayma/screens/backup_screen.dart';
import 'package:fayma/services/backup/backup_file_saver.dart';
import 'package:fayma/services/backup/backup_service.dart';
import 'package:fayma/services/backup/backup_settings.dart';
import 'package:fayma/services/shop_settings.dart';
import 'package:fayma/theme/app_theme.dart';

class _FakeBackupSettings implements BackupSettingsStore {
  DateTime? last;

  @override
  Future<String> deviceId() async => 'appareil-test';

  @override
  Future<String> shopId() async => 'boutique-test';

  @override
  Future<void> setShopId(String shopId) async {}

  @override
  Future<DateTime?> lastBackupAt() async => last;

  @override
  Future<void> setLastBackupAt(DateTime at) async {
    last = at;
  }
}

class _FakeShopSettings implements ShopSettingsStore {
  @override
  Future<String> readShopName() async => 'Boutique test';

  @override
  Future<void> saveShopName(String value) async {}
}

class _FakeBackupService extends BackupService {
  _FakeBackupService(_FakeBackupSettings settings)
      : _settings = settings,
        super(
          repository: InMemoryCreditRepository.withDemoData(),
          settings: settings,
        );

  final _FakeBackupSettings _settings;
  DateTime? markedAt;

  static final createdAt = DateTime(2026, 10, 31, 8, 30);

  @override
  Future<BackupData> createData() async {
    return BackupData(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      fileName: 'fayma-20261031-083000.fayma',
      createdAt: createdAt,
      clientCount: 3,
      operationCount: 5,
    );
  }

  @override
  Future<void> markBackupDone(DateTime at) async {
    markedAt = at;
    _settings.last = at;
  }

  @override
  Future<DateTime?> lastBackupAt() async => _settings.last;
}

class _FakeFileSaver extends BackupFileSaver {
  _FakeFileSaver({this.cancelled = false});

  final bool cancelled;

  String? savedFileName;
  Uint8List? savedBytes;
  String? savedMimeType;

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    savedFileName = fileName;
    savedBytes = bytes;
    savedMimeType = mimeType;
    return !cancelled;
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
  });

  testWidgets('enregistre la sauvegarde dans le gestionnaire de fichiers',
      (tester) async {
    final settings = _FakeBackupSettings();
    final service = _FakeBackupService(settings);
    final saver = _FakeFileSaver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupServiceProvider.overrideWithValue(service),
          backupFileSaverProvider.overrideWithValue(saver),
          shopSettingsProvider.overrideWithValue(_FakeShopSettings()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const BackupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enregistrer la sauvegarde'));
    await tester.pumpAndSettle();

    expect(saver.savedFileName, 'fayma-20261031-083000.fayma');
    expect(saver.savedBytes, [1, 2, 3, 4]);
    expect(saver.savedMimeType, 'application/octet-stream');
    expect(service.markedAt, isNotNull);
    expect(settings.last, isNotNull);
    expect(
      find.text('Sauvegarde enregistrée dans vos fichiers.'),
      findsOneWidget,
    );
  });

  testWidgets('ne marque pas la sauvegarde si l’utilisateur annule',
      (tester) async {
    final settings = _FakeBackupSettings();
    final service = _FakeBackupService(settings);
    final saver = _FakeFileSaver(cancelled: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupServiceProvider.overrideWithValue(service),
          backupFileSaverProvider.overrideWithValue(saver),
          shopSettingsProvider.overrideWithValue(_FakeShopSettings()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const BackupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enregistrer la sauvegarde'));
    await tester.pumpAndSettle();

    expect(saver.savedFileName, isNotNull);
    expect(service.markedAt, isNull);
    expect(settings.last, isNull);
    expect(
      find.text('Sauvegarde enregistrée dans vos fichiers.'),
      findsNothing,
    );
  });
}
