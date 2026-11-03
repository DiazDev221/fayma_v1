import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/models/client.dart';
import 'package:fayma/models/operation.dart';
import 'package:fayma/providers.dart';

void main() {
  test('les clients sont triés de l’activité la plus récente à la plus ancienne',
      () async {
    final repository = InMemoryCreditRepository.withDemoData();
    final container = ProviderContainer(
      overrides: [
        creditRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    // Démarre les flux de données avant de lire la liste triée.
    await container.read(clientsProvider.future);
    await container.read(allOperationsProvider.future);
    await pumpEventQueue();

    List<String> names() => [
          for (final summary
              in container.read(clientSummariesProvider).value!)
            summary.client.fullName,
        ];

    // Moussa : 12 oct. ; Fatou : 10 oct. ; Aissatou : 5 oct.
    expect(names(), ['Moussa Diop', 'Fatou Ndiaye', 'Aissatou Ba']);

    // Une opération plus récente fait remonter Aissatou en tête.
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

    expect(names(), ['Aissatou Ba', 'Moussa Diop', 'Fatou Ndiaye']);
  });

  test('les clients sans opération passent en fin de liste, par ordre de nom',
      () async {
    final repository = InMemoryCreditRepository();
    await repository.addClient(
      Client(
        id: 'c1',
        nom: 'Zola',
        prenom: 'Zoé',
        telephone: '77 000 00 01',
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    await repository.addClient(
      Client(
        id: 'c2',
        nom: 'Alpha',
        prenom: 'Ana',
        telephone: '77 000 00 02',
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    await repository.addOperation(
      Operation(
        id: 'o1',
        clientId: 'c2',
        type: OperationType.credit,
        amount: 1000,
        date: DateTime(2026, 10, 1),
      ),
    );

    final container = ProviderContainer(
      overrides: [
        creditRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(clientsProvider.future);
    await container.read(allOperationsProvider.future);
    await pumpEventQueue();

    final names = [
      for (final summary in container.read(clientSummariesProvider).value!)
        summary.client.fullName,
    ];
    expect(names, ['Ana Alpha', 'Zoé Zola']);
  });
}
