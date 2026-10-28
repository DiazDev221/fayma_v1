import '../models/operation.dart';

/// Trie les opérations de la plus récente à la plus ancienne.
///
/// À date égale, la dernière opération de [operations] est affichée en premier.
List<Operation> sortOperationsByMostRecent(Iterable<Operation> operations) {
  final list = operations.toList();
  final indexed = [
    for (var i = 0; i < list.length; i++) MapEntry(i, list[i]),
  ]..sort((a, b) {
      final byDate = b.value.date.compareTo(a.value.date);
      return byDate != 0 ? byDate : b.key.compareTo(a.key);
    });
  return [for (final entry in indexed) entry.value];
}
