import 'package:flutter_test/flutter_test.dart';

import 'package:fayma/models/balance.dart';
import 'package:fayma/models/operation.dart';

Operation _op(String id, OperationType type, int amount, int day) => Operation(
      id: id,
      clientId: 'c1',
      type: type,
      amount: amount,
      date: DateTime(2026, 10, day),
    );

Operation _credit(String id, int amount, int day) =>
    _op(id, OperationType.credit, amount, day);

Operation _repay(String id, int amount, int day) =>
    _op(id, OperationType.repayment, amount, day);

Operation _deposit(String id, int amount, int day) =>
    _op(id, OperationType.deposit, amount, day);

void main() {
  group('computeBalance', () {
    test('aucune opération : rien dû, aucun dépôt', () {
      final balance = computeBalance(const []);
      expect(balance.debt, 0);
      expect(balance.deposit, 0);
      expect(balance.openDebts, isEmpty);
      expect(balance.oldestDebtDate, isNull);
    });

    test('un achat à crédit crée une dette', () {
      final balance = computeBalance([_credit('a', 20000, 1)]);
      expect(balance.debt, 20000);
      expect(balance.originalTotal, 20000);
      expect(balance.deposit, 0);
    });

    test('remboursement partiel : la dette baisse', () {
      final balance = computeBalance([
        _credit('a', 20000, 1),
        _repay('r', 5000, 2),
      ]);
      expect(balance.debt, 15000);
      expect(balance.originalTotal, 20000);
      expect(balance.repaidShare, closeTo(0.25, 1e-9));
    });

    test('remboursement total : plus rien dû', () {
      final balance = computeBalance([
        _credit('a', 20000, 1),
        _repay('r', 20000, 2),
      ]);
      expect(balance.debt, 0);
      expect(balance.openDebts, isEmpty);
      expect(balance.deposit, 0);
    });

    test('un remboursement s\'impute d\'abord sur la dette la plus ancienne',
        () {
      final balance = computeBalance([
        _credit('a', 10000, 1),
        _credit('b', 20000, 2),
        _repay('r', 12000, 3),
      ]);
      // 'a' est soldée (10 000), 'b' perd 2 000.
      expect(balance.openDebts.map((d) => d.operationId), ['b']);
      expect(balance.debt, 18000);
      expect(balance.repaidShare, closeTo(0.1, 1e-9));
    });

    test('un trop-perçu devient un dépôt', () {
      final balance = computeBalance([
        _credit('a', 5000, 1),
        _repay('r', 8000, 2),
      ]);
      expect(balance.debt, 0);
      expect(balance.deposit, 3000);
    });

    test('un dépôt seul est conservé', () {
      final balance = computeBalance([_deposit('d', 12000, 1)]);
      expect(balance.debt, 0);
      expect(balance.deposit, 12000);
    });

    test('un achat consomme le dépôt avant de créer une dette', () {
      final balance = computeBalance([
        _deposit('d', 12000, 1),
        _credit('a', 5000, 2),
      ]);
      expect(balance.debt, 0);
      expect(balance.deposit, 7000);
    });

    test('un achat plus grand que le dépôt : le reste devient dette', () {
      final balance = computeBalance([
        _deposit('d', 3000, 1),
        _credit('a', 10000, 2),
      ]);
      expect(balance.deposit, 0);
      expect(balance.debt, 7000);
      expect(balance.originalTotal, 7000);
    });

    test('un dépôt s\'impute sur une dette déjà existante', () {
      final balance = computeBalance([
        _credit('a', 25000, 1),
        _deposit('d', 5000, 2),
      ]);
      expect(balance.debt, 20000);
      expect(balance.deposit, 0);
    });

    test('un dépôt plus grand que la dette : le surplus reste en dépôt', () {
      final balance = computeBalance([
        _credit('a', 5000, 1),
        _deposit('d', 8000, 2),
      ]);
      expect(balance.debt, 0);
      expect(balance.deposit, 3000);
    });

    test('un dépôt solde les dettes de la plus ancienne à la plus récente', () {
      final balance = computeBalance([
        _credit('a', 10000, 1),
        _credit('b', 20000, 2),
        _deposit('d', 12000, 3),
      ]);
      // 'a' est soldée (10 000), 'b' perd 2 000.
      expect(balance.openDebts.map((d) => d.operationId), ['b']);
      expect(balance.debt, 18000);
      expect(balance.deposit, 0);
    });

    test('la dette la plus ancienne est connue', () {
      final balance = computeBalance([
        _credit('b', 3000, 3),
        _credit('a', 1000, 1),
      ]);
      expect(balance.oldestDebtDate, DateTime(2026, 10, 1));
    });
  });

  group('computeBalance : ordre des opérations', () {
    test('les opérations sont rejouées par date, pas par ordre d\'ajout', () {
      // Le dépôt du 1er est antérieur à l'achat du 5.
      final balance = computeBalance([
        _credit('a', 10000, 5),
        _deposit('d', 10000, 1),
      ]);
      expect(balance.debt, 0);
      expect(balance.deposit, 0);
    });

    test('à date égale, l\'ordre départage les dettes de même date', () {
      final aFirst = computeBalance([
        _credit('a', 5000, 1),
        _credit('b', 5000, 1),
        _deposit('d', 5000, 1),
      ]);
      // 'a', enregistrée en premier, est soldée ; 'b' reste due.
      expect(aFirst.openDebts.map((d) => d.operationId), ['b']);

      final bFirst = computeBalance([
        _credit('b', 5000, 1),
        _credit('a', 5000, 1),
        _deposit('d', 5000, 1),
      ]);
      expect(bFirst.openDebts.map((d) => d.operationId), ['a']);
    });
  });

  group('computeBalance : annulations', () {
    test('un achat annulé est ignoré', () {
      final purchase = _credit('a', 10000, 1);
      final balance = computeBalance([
        purchase,
        Operation.reversing(
          purchase,
          id: 'x',
          date: DateTime(2026, 10, 2),
        ),
      ]);
      expect(balance.debt, 0);
      expect(balance.openDebts, isEmpty);
    });

    test('un remboursement annulé : la dette revient', () {
      final repayment = _repay('r', 5000, 2);
      final balance = computeBalance([
        _credit('a', 20000, 1),
        repayment,
        Operation.reversing(
          repayment,
          id: 'x',
          date: DateTime(2026, 10, 3),
        ),
      ]);
      expect(balance.debt, 20000);
    });

    test('un dépôt annulé est retiré', () {
      final deposit = _deposit('d', 8000, 1);
      final balance = computeBalance([
        deposit,
        Operation.reversing(
          deposit,
          id: 'x',
          date: DateTime(2026, 10, 2),
        ),
      ]);
      expect(balance.deposit, 0);
    });
  });

  group('Operation', () {
    test('Operation.purchase additionne les lignes', () {
      final op = Operation.purchase(
        id: 'a',
        clientId: 'c1',
        items: const [
          PurchaseItem(name: 'Sac de riz 25kg', price: 15000),
          PurchaseItem(name: 'Huile 5L', price: 5000),
        ],
        date: DateTime(2026, 10, 1),
      );
      expect(op.type, OperationType.credit);
      expect(op.amount, 20000);
      expect(op.items, hasLength(2));
    });

    test('Operation.reversing pointe vers l\'original', () {
      final original = _credit('a', 10000, 1);
      final reversal = Operation.reversing(
        original,
        id: 'x',
        date: DateTime(2026, 10, 2),
      );
      expect(reversal.isReversal, isTrue);
      expect(reversal.reversalOf, 'a');
      expect(reversal.sign, -1);
      expect(reversal.amount, 10000);
      expect(original.sign, 1);
    });
  });
}
