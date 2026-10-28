import 'package:flutter_test/flutter_test.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/data/repository_snapshot.dart';
import 'package:fayma/data/sqlite_credit_repository.dart';
import 'package:fayma/models/client.dart';
import 'package:fayma/models/operation.dart';
import 'package:fayma/models/payment_method.dart';

Client _client() => Client(
      id: 'client-1',
      nom: 'Diop',
      prenom: 'Moussa',
      telephone: '77 123 45 67',
      createdAt: DateTime(2026, 9, 20),
    );

Operation _credit() => Operation(
      id: 'credit-1',
      clientId: 'client-1',
      type: OperationType.credit,
      amount: 10000,
      date: DateTime(2026, 10, 1),
    );

void main() {
  group('InMemoryCreditRepository', () {
    test('snapshot puis replaceAll remplace toutes les données', () async {
      final repo = InMemoryCreditRepository();
      await repo.addClient(_client());
      await repo.addOperation(_credit());

      final snapshot = await repo.snapshot();
      expect(snapshot.clientCount, 1);
      expect(snapshot.operationCount, 1);

      final newRepo = InMemoryCreditRepository();
      await newRepo.replaceAll(snapshot);

      expect(await newRepo.getClient('client-1'), _client());
      expect((await newRepo.snapshot()).operations, [_credit()]);
    });
  });

  group('SqliteCreditRepository', () {
    late SqliteCreditRepository repo;

    setUp(() {
      repo = SqliteCreditRepository.inMemory();
    });

    tearDown(() {
      repo.close();
    });

    test('exporte et restaure clients, opérations et lignes d\'achat',
        () async {
      await repo.addClient(_client());
      final purchase = Operation.purchase(
        id: 'purchase-1',
        clientId: 'client-1',
        items: const [
          PurchaseItem(name: 'Riz', price: 5000),
          PurchaseItem(name: 'Savon', price: 1500),
        ],
        date: DateTime(2026, 10, 2),
        note: 'Crédit du jour',
      );
      await repo.addOperation(purchase);
      await repo.addOperation(
        Operation(
          id: 'repay-1',
          clientId: 'client-1',
          type: OperationType.repayment,
          amount: 2000,
          date: DateTime(2026, 10, 3),
          paymentMethod: PaymentMethod.orangeMoney,
        ),
      );

      final snapshot = await repo.snapshot();
      expect(
        snapshot.operations
            .firstWhere((operation) => operation.id == 'repay-1')
            .paymentMethod,
        PaymentMethod.orangeMoney,
      );
      final target = SqliteCreditRepository.inMemory();
      addTearDown(target.close);

      await target.replaceAll(snapshot);

      expect(await target.getClient('client-1'), _client());
      final restored = await target.snapshot();
      expect(restored.operations, snapshot.operations);
    });

    test('accepte une annulation insérée avant son opération d\'origine',
        () async {
      final reversal = Operation(
        id: 'reversal-1',
        clientId: 'client-1',
        type: OperationType.credit,
        amount: 10000,
        date: DateTime(2026, 10, 4),
        reversalOf: 'credit-1',
      );
      await repo.replaceAll(
        RepositorySnapshot(
          clients: [_client()],
          operations: [reversal, _credit()],
        ),
      );

      final snapshot = await repo.snapshot();
      expect(snapshot.operationCount, 2);
      expect(snapshot.operations.first.reversalOf, 'credit-1');
    });

    test('une restauration invalide ne supprime pas les données existantes',
        () async {
      await repo.addClient(_client());
      await repo.addOperation(_credit());

      await expectLater(
        repo.replaceAll(
          RepositorySnapshot(
            clients: const [],
            operations: [_credit()],
          ),
        ),
        throwsA(anything),
      );

      final snapshot = await repo.snapshot();
      expect(snapshot.clients, [_client()]);
      expect(snapshot.operations, [_credit()]);
    });
  });
}
