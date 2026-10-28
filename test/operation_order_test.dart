import 'package:flutter_test/flutter_test.dart';

import 'package:fayma/models/operation.dart';
import 'package:fayma/utils/operation_order.dart';

Operation _operation(String id, DateTime date, {String clientId = 'c1'}) {
  return Operation(
    id: id,
    clientId: clientId,
    type: OperationType.credit,
    amount: 1000,
    date: date,
  );
}

void main() {
  test('trie les opérations de la plus récente à la plus ancienne', () {
    final sorted = sortOperationsByMostRecent([
      _operation('oldest', DateTime(2026, 10, 1)),
      _operation('newest', DateTime(2026, 10, 12)),
      _operation('middle', DateTime(2026, 10, 8)),
    ]);

    expect(
      sorted.map((operation) => operation.id),
      ['newest', 'middle', 'oldest'],
    );
  });

  test('à date égale, la dernière enregistrée passe en tête', () {
    final date = DateTime(2026, 10, 12);
    final sorted = sortOperationsByMostRecent([
      _operation('first', date),
      _operation('second', date),
      _operation('third', date),
    ]);

    expect(
      sorted.map((operation) => operation.id),
      ['third', 'second', 'first'],
    );
  });

  test('une liste vide reste vide', () {
    expect(sortOperationsByMostRecent(const []), isEmpty);
  });
}
