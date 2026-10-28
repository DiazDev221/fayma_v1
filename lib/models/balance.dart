import 'dart:math' as math;

import 'operation.dart';

/// Dette encore ouverte, issue d'un achat à crédit.
class OpenDebt {
  const OpenDebt({
    required this.operationId,
    required this.date,
    required this.original,
    required this.remaining,
  });

  final String operationId;
  final DateTime date;

  /// Montant de la dette à l'origine (après déduction du dépôt), en FCFA.
  final int original;

  /// Reste à payer sur cet achat, en FCFA.
  final int remaining;
}

/// Situation d'un client à un instant donné.
class Balance {
  const Balance({this.openDebts = const [], this.deposit = 0});

  static const empty = Balance();

  /// Dettes ouvertes, de la plus ancienne à la plus récente.
  final List<OpenDebt> openDebts;

  /// Avance disponible versée par le client, en FCFA.
  final int deposit;

  /// Total dû, en FCFA.
  int get debt => openDebts.fold<int>(0, (sum, d) => sum + d.remaining);

  /// Montant d'origine des dettes encore ouvertes, en FCFA.
  int get originalTotal => openDebts.fold<int>(0, (sum, d) => sum + d.original);

  /// Part déjà remboursée des dettes ouvertes, entre 0 et 1.
  double get repaidShare {
    final total = originalTotal;
    return total == 0 ? 0 : (total - debt) / total;
  }

  /// Date de la dette la plus ancienne, ou null si rien n'est dû.
  DateTime? get oldestDebtDate =>
      openDebts.isEmpty ? null : openDebts.first.date;
}

class _MutableDebt {
  _MutableDebt(this.operationId, this.date, int amount)
      : original = amount,
        remaining = amount;

  final String operationId;
  final DateTime date;
  final int original;
  int remaining;
}

/// Calcule la situation d'un client en rejouant ses opérations par date.
///
/// Règles appliquées :
/// - un achat consomme d'abord le dépôt disponible, le reste devient dette ;
/// - un dépôt comme un remboursement s'impute d'abord sur la dette la plus
///   ancienne (règle de gestion n°5) ;
/// - ce qui dépasse la dette devient un dépôt (avance du client) ;
/// - une opération annulée est ignorée, ainsi que son annulation : le compte
///   est comme si elle n'avait jamais eu lieu (la trace reste dans l'historique).
Balance computeBalance(Iterable<Operation> operations) {
  final all = operations.toList();

  final reversedIds = <String>{
    for (final op in all)
      if (op.reversalOf != null) op.reversalOf!,
  };

  final effective = <MapEntry<int, Operation>>[
    for (var i = 0; i < all.length; i++)
      if (!all[i].isReversal && !reversedIds.contains(all[i].id))
        MapEntry(i, all[i]),
  ]..sort((a, b) {
      final byDate = a.value.date.compareTo(b.value.date);
      // À date égale, on garde l'ordre d'enregistrement.
      return byDate != 0 ? byDate : a.key.compareTo(b.key);
    });

  final debts = <_MutableDebt>[];
  var deposit = 0;

  for (final entry in effective) {
    final op = entry.value;
    switch (op.type) {
      case OperationType.credit:
        final fromDeposit = math.min(deposit, op.amount);
        deposit -= fromDeposit;
        final onCredit = op.amount - fromDeposit;
        if (onCredit > 0) {
          debts.add(_MutableDebt(op.id, op.date, onCredit));
        }
      // Un dépôt règle la dette existante, comme un remboursement.
      case OperationType.deposit:
      case OperationType.repayment:
        var left = op.amount;
        for (final debt in debts) {
          if (left == 0) break;
          final paid = math.min(left, debt.remaining);
          debt.remaining -= paid;
          left -= paid;
        }
        debts.removeWhere((d) => d.remaining == 0);
        // Trop-perçu : conservé comme avance du client.
        deposit += left;
    }
  }

  return Balance(
    openDebts: [
      for (final d in debts)
        OpenDebt(
          operationId: d.operationId,
          date: d.date,
          original: d.original,
          remaining: d.remaining,
        ),
    ],
    deposit: deposit,
  );
}
