import '../models/balance.dart';
import '../models/operation.dart';
import '../utils/format.dart';

/// Rédige le SMS envoyé au client après une opération.
///
/// - [operation] : l'achat, le remboursement ou le dépôt qui vient d'être
///   enregistré.
/// - [balanceAfter] : la situation du client une fois l'opération comptée.
/// - [shopName] : nom de la boutique, ajouté en signature s'il est connu.
///
/// Le texte évite les caractères hors alphabet GSM (espace insécable, accents
/// circonflexes, guillemets typographiques...). Un seul de ces caractères
/// ferait passer le SMS en Unicode : 70 caractères par SMS au lieu de 160,
/// donc un coût multiplié.
String buildSmsMessage({
  required Operation operation,
  required Balance balanceAfter,
  required String clientPrenom,
  String? shopName,
}) {
  final amount = _money(operation.amount);
  final date = formatDate(operation.date);
  final greeting = 'Bonjour ${clientPrenom.trim()},';

  final String body;
  switch (operation.type) {
    case OperationType.credit:
      final items = operation.items.isEmpty
          ? ''
          : '\nDétail : '
              '${operation.items.map((i) => '${i.name} (${_plain(i.price)})').join(', ')}.';
      body = '$greeting\n'
          'Votre achat à crédit du $date a bien été enregistré.$items\n'
          'Montant : $amount.\n'
          '${_balanceLine(balanceAfter)}';
    case OperationType.repayment:
      body = '$greeting\n'
          'Votre remboursement de $amount a bien été reçu le $date.\n'
          '${_balanceLine(balanceAfter)}';
    case OperationType.deposit:
      body = '$greeting\n'
          'Votre dépôt de $amount a bien été reçu le $date.\n'
          '${_balanceLine(balanceAfter)}';
  }

  final name = shopName?.trim();
  final signature = (name == null || name.isEmpty) ? '' : '\n$name';
  return _toGsm('$body\nMerci de votre confiance.$signature');
}

/// Rédige le SMS de rappel envoyé à un client qui doit encore de l'argent.
///
/// Le rappel indique le reste à payer et la date de la dette la plus ancienne.
/// Comme [buildSmsMessage], le texte reste dans l'alphabet GSM pour ne pas
/// faire basculer le SMS en Unicode.
String buildReminderSmsMessage({
  required String clientPrenom,
  required Balance balance,
  String? shopName,
}) {
  assert(balance.debt > 0, 'Un rappel ne se justifie que si le client doit.');

  final greeting = 'Bonjour ${clientPrenom.trim()},';
  final oldest = balance.oldestDebtDate;
  final dateLine =
      oldest == null ? '' : '\nDette la plus ancienne : ${formatDate(oldest)}.';

  final body = '$greeting\n'
      'Rappel : il vous reste ${_money(balance.debt)} à payer.'
      '$dateLine\n'
      'Merci de penser à votre règlement.';

  final name = shopName?.trim();
  final signature = (name == null || name.isEmpty) ? '' : '\n$name';
  return _toGsm('$body$signature');
}

/// Situation après l'opération : dette restante, dépôt disponible ou
/// « compte à jour ».
String _balanceLine(Balance balance) {
  if (balance.debt > 0) return 'Reste à payer : ${_money(balance.debt)}.';
  if (balance.deposit > 0) {
    return 'Solde disponible : ${_money(balance.deposit)}.';
  }
  return 'Compte à jour.';
}

/// Nombre avec espaces normaux, sans unité. Ex : "25 000".
String _plain(int amount) => formatAmount(amount).replaceAll('\u00A0', ' ');

/// Montant avec espaces normaux. Ex : "25 000 FCFA".
String _money(int amount) => '${_plain(amount)} FCFA';

/// Remplace les caractères absents de l'alphabet GSM courant par un
/// équivalent simple. Ne touche pas aux lettres déjà valides (é, è, à, ç...).
String _toGsm(String text) {
  const replacements = {
    '\u00A0': ' ',
    '\u202F': ' ',
    'â': 'a',
    'ä': 'a',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'û': 'u',
    'œ': 'oe',
    'æ': 'ae',
    'Â': 'A',
    'Ê': 'E',
    'Î': 'I',
    'Ô': 'O',
    'Û': 'U',
    'Ù': 'U',
    'À': 'A',
    'È': 'E',
    '’': "'",
    '‘': "'",
    '«': '"',
    '»': '"',
    '“': '"',
    '”': '"',
    '–': '-',
    '—': '-',
    '…': '...',
  };
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString();
}
