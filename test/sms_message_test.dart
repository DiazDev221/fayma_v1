import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fayma/models/balance.dart';
import 'package:fayma/models/operation.dart';
import 'package:fayma/services/sms_message.dart';

final _date = DateTime(2026, 10, 21);

Balance _owing(int amount) => Balance(
      openDebts: [
        OpenDebt(
          operationId: 'a',
          date: DateTime(2026, 10, 1),
          original: amount,
          remaining: amount,
        ),
      ],
    );

Operation _op(OperationType type, int amount) => Operation(
      id: 'o',
      clientId: 'c1',
      type: type,
      amount: amount,
      date: _date,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
  });

  test('achat à crédit : détail des produits et reste à payer', () {
    final message = buildSmsMessage(
      operation: Operation.purchase(
        id: 'o',
        clientId: 'c1',
        items: const [
          PurchaseItem(name: 'Sac de riz 25kg', price: 15000),
          PurchaseItem(name: 'Huile 5L', price: 5000),
        ],
        date: _date,
      ),
      balanceAfter: _owing(25000),
      clientPrenom: 'Moussa',
    );
    expect(
      message,
      'Bonjour Moussa,\n'
      'Votre achat à crédit du 21 oct. 2026 a bien été enregistré.\n'
      'Détail : Sac de riz 25kg (15 000), Huile 5L (5 000).\n'
      'Montant : 20 000 FCFA.\n'
      'Reste à payer : 25 000 FCFA.\n'
      'Merci de votre confiance.',
    );
  });

  test('remboursement : reste à payer', () {
    final message = buildSmsMessage(
      operation: _op(OperationType.repayment, 5000),
      balanceAfter: _owing(20000),
      clientPrenom: 'Moussa',
    );
    expect(
      message,
      'Bonjour Moussa,\n'
      'Votre remboursement de 5 000 FCFA a bien été reçu le 21 oct. 2026.\n'
      'Reste à payer : 20 000 FCFA.\n'
      'Merci de votre confiance.',
    );
  });

  test('remboursement qui solde la dette : compte à jour', () {
    final message = buildSmsMessage(
      operation: _op(OperationType.repayment, 20000),
      balanceAfter: Balance.empty,
      clientPrenom: 'Moussa',
    );
    expect(
      message,
      'Bonjour Moussa,\n'
      'Votre remboursement de 20 000 FCFA a bien été reçu le 21 oct. 2026.\n'
      'Compte à jour.\n'
      'Merci de votre confiance.',
    );
  });

  test('dépôt : solde disponible', () {
    final message = buildSmsMessage(
      operation: _op(OperationType.deposit, 5000),
      balanceAfter: const Balance(deposit: 17000),
      clientPrenom: 'Aissatou',
    );
    expect(
      message,
      'Bonjour Aissatou,\n'
      'Votre dépot de 5 000 FCFA a bien été reçu le 21 oct. 2026.\n'
      'Solde disponible : 17 000 FCFA.\n'
      'Merci de votre confiance.',
    );
  });

  test('dépôt imputé sur la dette : reste à payer', () {
    final message = buildSmsMessage(
      operation: _op(OperationType.deposit, 5000),
      balanceAfter: _owing(20000),
      clientPrenom: 'Moussa',
    );
    expect(
      message,
      'Bonjour Moussa,\n'
      'Votre dépot de 5 000 FCFA a bien été reçu le 21 oct. 2026.\n'
      'Reste à payer : 20 000 FCFA.\n'
      'Merci de votre confiance.',
    );
  });

  test('le nom de la boutique est ajouté en signature', () {
    final message = buildSmsMessage(
      operation: _op(OperationType.repayment, 5000),
      balanceAfter: _owing(20000),
      clientPrenom: 'Moussa',
      shopName: 'Boutique Awa',
    );
    expect(
      message,
      endsWith('Merci de votre confiance.\nBoutique Awa'),
    );
  });

  test('aucun caractère qui forcerait un SMS en Unicode', () {
    final message = buildSmsMessage(
      operation: Operation.purchase(
        id: 'o',
        clientId: 'c1',
        items: const [PurchaseItem(name: 'Pôle « test » – 1', price: 1000)],
        date: _date,
      ),
      balanceAfter: _owing(1000),
      clientPrenom: 'Chloé',
    );
    expect(message, isNot(contains('\u00A0')));
    expect(message, isNot(contains('ô')));
    expect(message, isNot(contains('«')));
    expect(message, isNot(contains('–')));
    expect(message, contains('Pole'));
    expect(message, contains('Chloé'));
  });

  test('rappel : reste à payer et dette la plus ancienne', () {
    final message = buildReminderSmsMessage(
      clientPrenom: 'Moussa',
      balance: _owing(25000),
      shopName: 'Boutique Awa',
    );
    expect(
      message,
      'Bonjour Moussa,\n'
      'Rappel : il vous reste 25 000 FCFA à payer.\n'
      'Dette la plus ancienne : 1 oct. 2026.\n'
      'Merci de penser à votre règlement.\n'
      'Boutique Awa',
    );
  });

  test('rappel sans nom de boutique : pas de signature', () {
    final message = buildReminderSmsMessage(
      clientPrenom: 'Aissatou',
      balance: _owing(8500),
    );
    expect(
      message,
      endsWith('Merci de penser à votre règlement.'),
    );
    expect(message, contains('8 500 FCFA'));
  });
}
