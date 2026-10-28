import 'dart:async';

import 'package:sqlite3/sqlite3.dart';

import '../models/client.dart';
import '../models/operation.dart';
import '../models/payment_method.dart';
import 'credit_repository.dart';
import 'repository_snapshot.dart';

/// Stockage SQLite : les données survivent à la fermeture de l'application.
///
/// Les montants sont des entiers (FCFA) et les dates des millisecondes
/// depuis 1970. Les opérations ne sont jamais supprimées ni modifiées :
/// une correction passe par une opération d'annulation (F07).
class SqliteCreditRepository implements CreditRepository {
  SqliteCreditRepository._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    _migrate();
  }

  /// Ouvre (ou crée) la base dans le fichier [path].
  factory SqliteCreditRepository.open(String path) =>
      SqliteCreditRepository._(sqlite3.open(path));

  /// Base en mémoire, pour les tests.
  factory SqliteCreditRepository.inMemory() =>
      SqliteCreditRepository._(sqlite3.openInMemory());

  static const int _databaseVersion = 2;

  /// Version du contenu d'une sauvegarde. Elle ne change pas quand seule la
  /// base locale évolue : un ajout de colonne facultative reste lisible par
  /// les anciennes sauvegardes comme par les nouvelles.
  static const int _schemaVersion = 1;

  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _counter = 0;

  void _migrate() {
    final current =
        _db.select('PRAGMA user_version').first['user_version'] as int;
    if (current >= _databaseVersion) return;

    _inTransaction(() {
      if (current < 1) {
        _db.execute('''
          CREATE TABLE clients (
            id           TEXT PRIMARY KEY,
            nom          TEXT NOT NULL,
            prenom       TEXT NOT NULL,
            telephone    TEXT NOT NULL,
            credit_limit INTEGER NOT NULL,
            created_at   INTEGER NOT NULL
          )
        ''');
        _db.execute('''
          CREATE TABLE operations (
            id          TEXT PRIMARY KEY,
            client_id   TEXT NOT NULL REFERENCES clients(id),
            type        TEXT NOT NULL,
            amount      INTEGER NOT NULL CHECK (amount > 0),
            date        INTEGER NOT NULL,
            note        TEXT,
            reversal_of TEXT REFERENCES operations(id)
          )
        ''');
        _db.execute(
          'CREATE INDEX idx_operations_client ON operations(client_id)',
        );
        _db.execute('''
          CREATE TABLE operation_items (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            operation_id TEXT NOT NULL REFERENCES operations(id),
            position     INTEGER NOT NULL,
            name         TEXT NOT NULL,
            price        INTEGER NOT NULL CHECK (price > 0)
          )
        ''');
        _db.execute(
          'CREATE INDEX idx_items_operation ON operation_items(operation_id)',
        );
      }
      if (current < 2) {
        // Moyen de paiement des dépôts et remboursements. Les opérations
        // existantes restent à NULL : aucun moyen n'était alors enregistré.
        _db.execute(
          'ALTER TABLE operations ADD COLUMN payment_method TEXT',
        );
      }
      // Version suivante : ajouter ici un bloc `if (current < 3) { ... }`.
      _db.execute('PRAGMA user_version = $_databaseVersion');
    });
  }

  /// Exécute [action] en transaction : tout réussit, ou rien n'est écrit.
  T _inTransaction<T>(T Function() action) {
    _db.execute('BEGIN');
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  String newId() {
    _counter++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_counter';
  }

  /// Flux qui émet la valeur courante dès l'écoute, puis à chaque changement.
  Stream<T> _watch<T>(T Function() current) {
    late final StreamController<T> controller;
    StreamSubscription<void>? subscription;
    controller = StreamController<T>(
      onListen: () {
        controller.add(current());
        subscription = _changes.stream.listen((_) => controller.add(current()));
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  Client _clientFromRow(Row row) => Client(
        id: row['id'] as String,
        nom: row['nom'] as String,
        prenom: row['prenom'] as String,
        telephone: row['telephone'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      );

  Operation _operationFromRow(Row row, List<PurchaseItem> items) => Operation(
        id: row['id'] as String,
        clientId: row['client_id'] as String,
        type: OperationType.values.byName(row['type'] as String),
        amount: row['amount'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int),
        note: row['note'] as String?,
        items: items,
        reversalOf: row['reversal_of'] as String?,
        paymentMethod: PaymentMethod.fromName(row['payment_method'] as String?),
      );

  List<Client> _readClients() {
    final rows = _db.select(
      'SELECT * FROM clients ORDER BY lower(prenom || \' \' || nom)',
    );
    return List.unmodifiable(rows.map(_clientFromRow));
  }

  List<Operation> _readOperations(String? clientId) {
    final ResultSet rows;
    final ResultSet itemRows;
    if (clientId == null) {
      rows = _db.select('SELECT * FROM operations ORDER BY rowid');
      itemRows = _db.select(
        'SELECT operation_id, name, price FROM operation_items '
        'ORDER BY operation_id, position',
      );
    } else {
      rows = _db.select(
        'SELECT * FROM operations WHERE client_id = ? ORDER BY rowid',
        [clientId],
      );
      itemRows = _db.select(
        'SELECT i.operation_id, i.name, i.price FROM operation_items i '
        'JOIN operations o ON o.id = i.operation_id '
        'WHERE o.client_id = ? ORDER BY i.operation_id, i.position',
        [clientId],
      );
    }

    final itemsByOperation = <String, List<PurchaseItem>>{};
    for (final row in itemRows) {
      itemsByOperation
          .putIfAbsent(row['operation_id'] as String, () => [])
          .add(PurchaseItem(
            name: row['name'] as String,
            price: row['price'] as int,
          ));
    }

    return List.unmodifiable([
      for (final row in rows)
        _operationFromRow(
          row,
          List.unmodifiable(itemsByOperation[row['id'] as String] ?? const []),
        ),
    ]);
  }

  void _insertClient(Client client) {
    _db.execute(
      'INSERT INTO clients (id, nom, prenom, telephone, credit_limit, '
      'created_at) VALUES (?, ?, ?, ?, ?, ?)',
      [
        client.id,
        client.nom,
        client.prenom,
        client.telephone,
        // Ancienne colonne conservée pour les bases existantes. Le plafond
        // de crédit n'est plus utilisé par l'application.
        0,
        client.createdAt.millisecondsSinceEpoch,
      ],
    );
  }

  void _insertOperation(Operation op) {
    _db.execute(
      'INSERT INTO operations (id, client_id, type, amount, date, note, '
      'reversal_of, payment_method) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        op.id,
        op.clientId,
        op.type.name,
        op.amount,
        op.date.millisecondsSinceEpoch,
        op.note,
        op.reversalOf,
        op.paymentMethod?.name,
      ],
    );
    for (var i = 0; i < op.items.length; i++) {
      _db.execute(
        'INSERT INTO operation_items (operation_id, position, name, price) '
        'VALUES (?, ?, ?, ?)',
        [op.id, i, op.items[i].name, op.items[i].price],
      );
    }
  }

  @override
  Stream<List<Client>> watchClients() => _watch(_readClients);

  @override
  Stream<List<Operation>> watchOperations({String? clientId}) =>
      _watch(() => _readOperations(clientId));

  @override
  Future<Client?> getClient(String id) async {
    final rows = _db.select('SELECT * FROM clients WHERE id = ?', [id]);
    return rows.isEmpty ? null : _clientFromRow(rows.first);
  }

  @override
  Future<void> addClient(Client client) async {
    _insertClient(client);
    _changes.add(null);
  }

  @override
  Future<void> updateClient(Client client) async {
    final exists = _db.select(
      'SELECT 1 FROM clients WHERE id = ?',
      [client.id],
    );
    if (exists.isEmpty) {
      throw StateError('Client introuvable : ${client.id}');
    }
    _db.execute(
      'UPDATE clients SET nom = ?, prenom = ?, telephone = ? WHERE id = ?',
      [
        client.nom,
        client.prenom,
        client.telephone,
        client.id,
      ],
    );
    _changes.add(null);
  }

  @override
  Future<void> addOperation(Operation operation) async {
    _inTransaction(() => _insertOperation(operation));
    _changes.add(null);
  }

  @override
  Future<void> reverseOperation(String operationId, {String? note}) async {
    _inTransaction(() {
      final rows = _db.select(
        'SELECT * FROM operations WHERE id = ?',
        [operationId],
      );
      if (rows.isEmpty) {
        throw StateError('Opération introuvable : $operationId');
      }
      final original = _operationFromRow(rows.first, const []);
      if (original.isReversal) {
        throw StateError('Une annulation ne peut pas être annulée.');
      }
      final already = _db.select(
        'SELECT 1 FROM operations WHERE reversal_of = ?',
        [operationId],
      );
      if (already.isNotEmpty) {
        throw StateError('Opération déjà annulée : $operationId');
      }
      _insertOperation(
        Operation.reversing(
          original,
          id: newId(),
          date: DateTime.now(),
          note: note,
        ),
      );
    });
    _changes.add(null);
  }

  @override
  int get schemaVersion => _schemaVersion;

  @override
  Future<RepositorySnapshot> snapshot() async {
    return RepositorySnapshot(
      clients: _readClients(),
      operations: _readOperations(null),
    );
  }

  @override
  Future<void> replaceAll(RepositorySnapshot snapshot) async {
    _inTransaction(() {
      // Les annulations peuvent référencer une opération insérée plus tard
      // dans la liste : on reporte la vérification des clés étrangères à la
      // fin de la transaction.
      _db.execute('PRAGMA defer_foreign_keys = ON');
      _db.execute('DELETE FROM operation_items');
      _db.execute('DELETE FROM operations');
      _db.execute('DELETE FROM clients');

      for (final client in snapshot.clients) {
        _insertClient(client);
      }
      for (final operation in snapshot.operations) {
        _insertOperation(operation);
      }
    });
    _changes.add(null);
  }

  /// Ferme la base. À appeler seulement à l'arrêt de l'application ou en test.
  void close() {
    _changes.close();
    _db.dispose();
  }
}
