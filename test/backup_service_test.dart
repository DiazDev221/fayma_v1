import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/data/repository_snapshot.dart';
import 'package:fayma/models/client.dart';
import 'package:fayma/models/operation.dart';
import 'package:fayma/models/payment_method.dart';
import 'package:fayma/services/backup/backup_crypto.dart';
import 'package:fayma/services/backup/backup_exception.dart';
import 'package:fayma/services/backup/backup_serializer.dart';
import 'package:fayma/services/backup/backup_service.dart';
import 'package:fayma/services/backup/backup_settings.dart';
import 'package:fayma/services/shop_settings.dart';

class _FakeSettings implements BackupSettingsStore {
  _FakeSettings({required this.shop});

  String shop;
  DateTime? last;

  @override
  Future<String> deviceId() async => 'appareil-test';

  @override
  Future<String> shopId() async => shop;

  @override
  Future<void> setShopId(String shopId) async => shop = shopId;

  @override
  Future<DateTime?> lastBackupAt() async => last;

  @override
  Future<void> setLastBackupAt(DateTime at) async => last = at;
}

class _FakeShopSettings implements ShopSettingsStore {
  _FakeShopSettings({this.name = ''});

  String name;

  @override
  Future<String> readShopName() async => name;

  @override
  Future<void> saveShopName(String value) async => name = value;
}

Client _client() => Client(
      id: 'client-1',
      nom: 'Diop',
      prenom: 'Moussa',
      telephone: '77 123 45 67',
      createdAt: DateTime(2026, 9, 20),
    );

Operation _credit() => Operation.purchase(
      id: 'operation-1',
      clientId: 'client-1',
      items: const [PurchaseItem(name: 'Riz', price: 12000)],
      date: DateTime(2026, 10, 1),
    );

Operation _repayment() => Operation(
      id: 'operation-2',
      clientId: 'client-1',
      type: OperationType.repayment,
      amount: 5000,
      date: DateTime(2026, 10, 2),
      paymentMethod: PaymentMethod.orangeMoney,
    );

Operation _deposit() => Operation(
      id: 'operation-3',
      clientId: 'client-1',
      type: OperationType.deposit,
      amount: 12000,
      date: DateTime(2026, 10, 3),
      paymentMethod: PaymentMethod.wave,
    );

/// Supprime le marqueur des nouvelles sauvegardes pour simuler un fichier
/// créé avant la suppression du code de récupération.
Future<void> _removeKeySource(File file) async {
  final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  json.remove('key_source');
  await file.writeAsString(jsonEncode(json));
}

void main() {
  const crypto = BackupCrypto(
    memoryKib: 128,
    iterations: 1,
    parallelism: 1,
  );

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fayma_backup_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('exporte puis restaure une sauvegarde sur une autre base', () async {
    final sourceRepo = InMemoryCreditRepository();
    await sourceRepo.addClient(_client());
    await sourceRepo.addOperation(_credit());
    await sourceRepo.addOperation(_repayment());
    await sourceRepo.addOperation(_deposit());

    final sourceSettings = _FakeSettings(shop: 'boutique-1');
    final sourceShop = _FakeShopSettings(name: 'Boutique Awa');
    final sourceService = BackupService(
      repository: sourceRepo,
      settings: sourceSettings,
      shopSettings: sourceShop,
      crypto: crypto,
      directoryProvider: () async => tempDir,
      appVersionProvider: () async => '1.0.0+1',
    );

    final export = await sourceService.export();
    expect(await export.file.exists(), isTrue);
    expect(export.file.path, endsWith('.fayma'));
    expect(export.clientCount, 1);
    expect(export.operationCount, 3);

    final targetRepo = InMemoryCreditRepository();
    await targetRepo.addClient(
      Client(
        id: 'ancien-client',
        nom: 'Ancien',
        prenom: 'Client',
        telephone: '70 000 00 00',
        createdAt: DateTime(2020),
      ),
    );
    final targetSettings = _FakeSettings(shop: 'boutique-2');
    final targetShop = _FakeShopSettings(name: 'Ancienne boutique');
    final targetService = BackupService(
      repository: targetRepo,
      settings: targetSettings,
      shopSettings: targetShop,
      crypto: crypto,
      directoryProvider: () async => tempDir,
      appVersionProvider: () async => '1.0.0+1',
    );

    final preview = await targetService.inspectFile(export.file);
    expect(preview.payload.clientCount, 1);
    expect(preview.payload.operationCount, 3);
    expect(preview.payload.shopId, 'boutique-1');
    expect(preview.payload.shopName, 'Boutique Awa');

    await targetService.restore(preview);

    final snapshot = await targetRepo.snapshot();
    expect(snapshot.clients, [_client()]);
    expect(snapshot.operations, [_credit(), _repayment(), _deposit()]);
    expect(
      snapshot.operations
          .firstWhere((operation) => operation.id == 'operation-2')
          .paymentMethod,
      PaymentMethod.orangeMoney,
    );
    expect(
      snapshot.operations
          .firstWhere((operation) => operation.id == 'operation-3')
          .paymentMethod,
      PaymentMethod.wave,
    );
    expect(targetSettings.shop, 'boutique-1');
    expect(targetShop.name, 'Boutique Awa');
  });

  test('une ancienne sauvegarde conserve le nom local', () async {
    final repo = InMemoryCreditRepository();
    final settings = _FakeSettings(shop: 'boutique-1');
    final shop = _FakeShopSettings(name: 'Boutique Awa');
    final service = BackupService(
      repository: repo,
      settings: settings,
      shopSettings: shop,
      crypto: crypto,
    );
    final preview = BackupPreview(
      payload: BackupPayload(
        createdAt: DateTime(2026, 10, 1),
        appVersion: '0.1.0',
        schemaVersion: 1,
        deviceId: 'appareil-test',
        shopId: 'boutique-1',
        shopName: '',
        clients: const [],
        operations: const [],
      ),
      sourceName: 'ancienne.fayma',
    );

    await service.restore(preview);

    expect(shop.name, 'Boutique Awa');
  });

  test('refuse un fichier modifié sans toucher aux données', () async {
    final repo = InMemoryCreditRepository();
    await repo.addClient(_client());
    final settings = _FakeSettings(shop: 'boutique-1');
    final service = BackupService(
      repository: repo,
      settings: settings,
      crypto: crypto,
      directoryProvider: () async => tempDir,
      appVersionProvider: () async => '1.0.0+1',
    );
    final export = await service.export();

    final json =
        jsonDecode(await export.file.readAsString()) as Map<String, dynamic>;
    final cipherText = base64Decode(json['ciphertext'] as String);
    cipherText[0] = cipherText[0] ^ 0x01;
    json['ciphertext'] = base64Encode(cipherText);
    await export.file.writeAsString(jsonEncode(json));

    await expectLater(
      service.inspectFile(export.file),
      throwsA(isA<BackupException>()),
    );

    final snapshot = await repo.snapshot();
    expect(snapshot.clientCount, 1);
  });

  test('lit aussi une sauvegarde fournie en mémoire', () async {
    final repo = InMemoryCreditRepository();
    await repo.addClient(_client());
    final settings = _FakeSettings(shop: 'boutique-1');
    final service = BackupService(
      repository: repo,
      settings: settings,
      crypto: crypto,
      directoryProvider: () async => tempDir,
      appVersionProvider: () async => '1.0.0+1',
    );
    final export = await service.export();
    final bytes = await export.file.readAsBytes();

    final preview = await service.inspectBytes(
      bytes,
      sourceName: 'sauvegarde.fayma',
    );

    expect(preview.payload.clientCount, 1);
    expect(preview.sourceName, 'sauvegarde.fayma');
  });

  test('mémorise la date de la dernière sauvegarde', () async {
    final repo = InMemoryCreditRepository();
    final settings = _FakeSettings(shop: 'boutique-1');
    final service = BackupService(
      repository: repo,
      settings: settings,
      crypto: crypto,
      directoryProvider: () async => tempDir,
      appVersionProvider: () async => '1.0.0+1',
    );
    final at = DateTime(2026, 10, 21, 14, 5);

    await service.markBackupDone(at);

    expect(await settings.lastBackupAt(), at);
  });

  test('la sauvegarde restaurée peut être réexportée', () async {
    final sourceRepo = InMemoryCreditRepository();
    await sourceRepo.addClient(_client());
    await sourceRepo.addOperation(_credit());

    final settings = _FakeSettings(shop: 'boutique-1');
    final service = BackupService(
      repository: sourceRepo,
      settings: settings,
      crypto: crypto,
      directoryProvider: () async => tempDir,
      appVersionProvider: () async => '1.0.0+1',
    );
    final first = await service.export();
    final preview = await service.inspectFile(first.file);

    final targetRepo = InMemoryCreditRepository();
    await targetRepo.replaceAll(
      RepositorySnapshot(
        clients: preview.payload.clients,
        operations: preview.payload.operations,
      ),
    );
    final targetService = BackupService(
      repository: targetRepo,
      settings: settings,
      crypto: crypto,
      directoryProvider: () async => tempDir,
      appVersionProvider: () async => '1.0.0+1',
    );
    final second = await targetService.export();

    expect(second.clientCount, first.clientCount);
    expect(second.operationCount, first.operationCount);
  });

  test('restaure une ancienne sauvegarde avec son code de récupération',
      () async {
    const legacyCode = 'ABCD2345EFGH6789JKMN2345';
    const legacyCrypto = BackupCrypto(
      memoryKib: 128,
      iterations: 1,
      parallelism: 1,
      keyMaterial: legacyCode,
    );

    final sourceRepo = InMemoryCreditRepository();
    await sourceRepo.addClient(_client());
    final sourceSettings = _FakeSettings(shop: 'boutique-1');
    final sourceService = BackupService(
      repository: sourceRepo,
      settings: sourceSettings,
      crypto: legacyCrypto,
      directoryProvider: () async => tempDir,
      appVersionProvider: () async => '1.0.0+1',
    );
    final export = await sourceService.export();
    await _removeKeySource(export.file);

    final targetRepo = InMemoryCreditRepository();
    final targetSettings = _FakeSettings(shop: 'boutique-2');
    final targetService = BackupService(
      repository: targetRepo,
      settings: targetSettings,
      crypto: crypto,
      directoryProvider: () async => tempDir,
      appVersionProvider: () async => '1.0.0+1',
    );

    await expectLater(
      targetService.inspectFile(export.file),
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

    await expectLater(
      targetService.inspectFile(
        export.file,
        legacyRecoveryCode: 'ZZZZ2345ZZZZ6789ZZZZ2345',
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

    final preview = await targetService.inspectFile(
      export.file,
      legacyRecoveryCode: legacyCode,
    );
    expect(preview.payload.clientCount, 1);

    await targetService.restore(preview);

    expect((await targetRepo.snapshot()).clients, [_client()]);
  });
}
