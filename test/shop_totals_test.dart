import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/models/operation.dart';
import 'package:fayma/providers.dart';

void main() {
  test('ShopTotals additionne les dépôts de tous les clients', () async {
    final repository = InMemoryCreditRepository.withDemoData();
    final container = ProviderContainer(
      overrides: [
        creditRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    // Démarre les flux de données avant de lire les agrégats.
    await container.read(clientsProvider.future);
    await container.read(allOperationsProvider.future);
    await pumpEventQueue();

    var totals = container.read(shopTotalsProvider).value!;
    expect(totals.totalDue, 33500);
    expect(totals.totalOriginal, 38500);
    expect(totals.clientsWithDebt, 2);
    expect(totals.totalDeposits, 12000);

    // Un nouveau dépôt chez un client sans dette augmente le total.
    await repository.addOperation(
      Operation(
        id: 'test-deposit',
        clientId: 'c3',
        type: OperationType.deposit,
        amount: 3000,
        date: DateTime(2026, 10, 20),
      ),
    );
    await pumpEventQueue();

    totals = container.read(shopTotalsProvider).value!;
    expect(totals.totalDeposits, 15000);
    expect(totals.totalDue, 33500);
  });
}
