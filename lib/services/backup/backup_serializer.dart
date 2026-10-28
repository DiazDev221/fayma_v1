import 'dart:convert';

import '../../data/repository_snapshot.dart';
import '../../models/client.dart';
import '../../models/operation.dart';
import '../../models/payment_method.dart';
import 'backup_exception.dart';
import 'backup_format.dart';

/// Contenu d'une sauvegarde, une fois déchiffré et validé.
class BackupPayload {
  const BackupPayload({
    required this.createdAt,
    required this.appVersion,
    required this.schemaVersion,
    required this.deviceId,
    required this.shopId,
    this.shopName = '',
    required this.clients,
    required this.operations,
  });

  final DateTime createdAt;
  final String appVersion;
  final int schemaVersion;
  final String deviceId;
  final String shopId;

  /// Nom de la boutique au moment de la sauvegarde.
  ///
  /// Vide pour les sauvegardes créées avant que ce champ n'existe.
  final String shopName;

  final List<Client> clients;
  final List<Operation> operations;

  int get clientCount => clients.length;
  int get operationCount => operations.length;

  RepositorySnapshot get snapshot => RepositorySnapshot(
        clients: clients,
        operations: operations,
      );
}

/// Convertit les données de la boutique en JSON versionné, et inversement.
///
/// Ce code ne chiffre rien : voir `BackupCrypto` pour le conteneur sécurisé.
class BackupSerializer {
  const BackupSerializer();

  String encode({
    required RepositorySnapshot snapshot,
    required String appVersion,
    required int schemaVersion,
    required String deviceId,
    required String shopId,
    String shopName = '',
    DateTime? createdAt,
  }) {
    final created = (createdAt ?? DateTime.now()).toUtc();
    final data = <String, Object?>{
      'format': backupFormat,
      'format_version': backupFormatVersion,
      'schema_version': schemaVersion,
      'app_version': appVersion,
      'created_at': created.toIso8601String(),
      'device_id': deviceId,
      'shop_id': shopId,
      'shop_name': shopName.trim(),
      'counts': {
        'clients': snapshot.clientCount,
        'operations': snapshot.operationCount,
      },
      'clients': [
        for (final client in snapshot.clients) _clientToJson(client),
      ],
      'operations': [
        for (final operation in snapshot.operations)
          _operationToJson(operation),
      ],
    };
    return jsonEncode(data);
  }

  BackupPayload decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw BackupException(
        'Le contenu de la sauvegarde est illisible.',
        cause: error,
      );
    }

    final root = _asMap(decoded, 'racine');
    final format = _asString(root['format'], 'format');
    if (format != backupFormat) {
      throw const BackupException(
        'Ce fichier n\'est pas une sauvegarde Fayma.',
      );
    }

    final formatVersion = _asInt(root['format_version'], 'format_version');
    if (formatVersion != backupFormatVersion) {
      throw BackupException(
        'Cette sauvegarde utilise une version de format non prise en charge '
        '($formatVersion). Mettez Fayma à jour.',
      );
    }

    final schemaVersion = _asInt(root['schema_version'], 'schema_version');
    if (schemaVersion < 1) {
      throw const BackupException('La version des données est invalide.');
    }

    final createdAt = _asDate(root['created_at'], 'created_at');
    final appVersion = _asString(root['app_version'], 'app_version');
    final deviceId = _asString(root['device_id'], 'device_id');
    final shopId = _asString(root['shop_id'], 'shop_id');
    final shopName = _asOptionalString(root['shop_name'], 'shop_name');

    final clientJson = _asList(root['clients'], 'clients');
    final operationJson = _asList(root['operations'], 'operations');

    final clients = <Client>[];
    final clientIds = <String>{};
    for (var i = 0; i < clientJson.length; i++) {
      final client = _clientFromJson(
        _asMap(clientJson[i], 'clients[$i]'),
        'clients[$i]',
      );
      if (!clientIds.add(client.id)) {
        throw BackupException('Client en double dans la sauvegarde : '
            '${client.id}.');
      }
      clients.add(client);
    }

    final operations = <Operation>[];
    final operationIds = <String>{};
    for (var i = 0; i < operationJson.length; i++) {
      final operation = _operationFromJson(
        _asMap(operationJson[i], 'operations[$i]'),
        'operations[$i]',
      );
      if (!operationIds.add(operation.id)) {
        throw BackupException('Opération en double dans la sauvegarde : '
            '${operation.id}.');
      }
      operations.add(operation);
    }

    for (final operation in operations) {
      if (!clientIds.contains(operation.clientId)) {
        throw BackupException(
          'Une opération référence un client absent de la sauvegarde '
          '(${operation.clientId}).',
        );
      }
    }

    final operationsById = {
      for (final operation in operations) operation.id: operation,
    };
    final reversedIds = <String>{};
    for (final operation in operations) {
      final reversedId = operation.reversalOf;
      if (reversedId == null) continue;
      final reversed = operationsById[reversedId];
      if (reversed == null) {
        throw BackupException(
          'Une annulation référence une opération absente ($reversedId).',
        );
      }
      if (reversed.isReversal) {
        throw const BackupException(
          'Une annulation ne peut pas annuler une autre annulation.',
        );
      }
      if (!reversedIds.add(reversedId)) {
        throw BackupException(
          'Une opération est annulée plusieurs fois ($reversedId).',
        );
      }
      if (reversed.clientId != operation.clientId ||
          reversed.type != operation.type ||
          reversed.amount != operation.amount) {
        throw const BackupException(
          'Une annulation ne correspond pas à l\'opération annulée.',
        );
      }
    }

    final counts = root['counts'];
    if (counts != null) {
      final countsMap = _asMap(counts, 'counts');
      final expectedClients = _asInt(countsMap['clients'], 'counts.clients');
      final expectedOperations =
          _asInt(countsMap['operations'], 'counts.operations');
      if (expectedClients != clients.length ||
          expectedOperations != operations.length) {
        throw const BackupException(
          'Le nombre d\'éléments ne correspond pas à la sauvegarde. '
          'Le fichier est peut-être endommagé.',
        );
      }
    }

    return BackupPayload(
      createdAt: createdAt,
      appVersion: appVersion,
      schemaVersion: schemaVersion,
      deviceId: deviceId,
      shopId: shopId,
      shopName: shopName,
      clients: List.unmodifiable(clients),
      operations: List.unmodifiable(operations),
    );
  }

  Map<String, Object?> _clientToJson(Client client) => {
        'id': client.id,
        'nom': client.nom,
        'prenom': client.prenom,
        'telephone': client.telephone,
        'created_at': client.createdAt.toUtc().toIso8601String(),
      };

  Map<String, Object?> _operationToJson(Operation operation) => {
        'id': operation.id,
        'client_id': operation.clientId,
        'type': operation.type.name,
        'amount': operation.amount,
        'date': operation.date.toUtc().toIso8601String(),
        if (operation.note != null) 'note': operation.note,
        if (operation.reversalOf != null) 'reversal_of': operation.reversalOf,
        if (operation.paymentMethod != null)
          'payment_method': operation.paymentMethod!.name,
        if (operation.items.isNotEmpty)
          'items': [
            for (final item in operation.items)
              {'name': item.name, 'price': item.price},
          ],
      };

  Client _clientFromJson(Map<String, Object?> json, String path) {
    // Le champ `credit_limit` des anciennes sauvegardes est ignoré : le
    // crédit n'est plus plafonné.
    return Client(
      id: _asString(json['id'], '$path.id'),
      nom: _asString(json['nom'], '$path.nom'),
      prenom: _asString(json['prenom'], '$path.prenom'),
      telephone: _asString(json['telephone'], '$path.telephone'),
      createdAt: _asDate(json['created_at'], '$path.created_at'),
    );
  }

  Operation _operationFromJson(Map<String, Object?> json, String path) {
    final typeName = _asString(json['type'], '$path.type');
    final OperationType type;
    try {
      type = OperationType.values.byName(typeName);
    } on ArgumentError catch (error) {
      throw BackupException(
        'Type d\'opération inconnu ($typeName).',
        cause: error,
      );
    }

    final amount = _asInt(json['amount'], '$path.amount');
    if (amount <= 0) {
      throw BackupException('Montant invalide pour $path.');
    }

    final itemsJson = json['items'];
    final items = <PurchaseItem>[];
    if (itemsJson != null) {
      final list = _asList(itemsJson, '$path.items');
      for (var i = 0; i < list.length; i++) {
        final item = _asMap(list[i], '$path.items[$i]');
        final price = _asInt(item['price'], '$path.items[$i].price');
        if (price <= 0) {
          throw BackupException('Prix invalide pour $path.items[$i].');
        }
        items.add(
          PurchaseItem(
            name: _asString(item['name'], '$path.items[$i].name'),
            price: price,
          ),
        );
      }
    }

    final note = json['note'];
    final reversalOf = json['reversal_of'];
    final paymentMethodName = json['payment_method'];
    if (note != null && note is! String) {
      throw BackupException('Note invalide pour $path.');
    }
    if (reversalOf != null && reversalOf is! String) {
      throw BackupException('Référence d\'annulation invalide pour $path.');
    }
    if (paymentMethodName != null && paymentMethodName is! String) {
      throw BackupException('Moyen de paiement invalide pour $path.');
    }

    return Operation(
      id: _asString(json['id'], '$path.id'),
      clientId: _asString(json['client_id'], '$path.client_id'),
      type: type,
      amount: amount,
      date: _asDate(json['date'], '$path.date'),
      note: note as String?,
      items: List.unmodifiable(items),
      reversalOf: reversalOf as String?,
      paymentMethod: PaymentMethod.fromName(paymentMethodName as String?),
    );
  }

  Map<String, Object?> _asMap(Object? value, String field) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw BackupException('Champ manquant ou invalide : $field.');
  }

  List<Object?> _asList(Object? value, String field) {
    if (value is List) return value;
    throw BackupException('Champ manquant ou invalide : $field.');
  }

  String _asString(Object? value, String field) {
    if (value is String) return value;
    throw BackupException('Champ manquant ou invalide : $field.');
  }

  /// Chaîne facultative : absente ou nulle devient une chaîne vide.
  String _asOptionalString(Object? value, String field) {
    if (value == null) return '';
    if (value is String) return value;
    throw BackupException('Champ invalide : $field.');
  }

  int _asInt(Object? value, String field) {
    if (value is int) return value;
    throw BackupException('Champ manquant ou invalide : $field.');
  }

  DateTime _asDate(Object? value, String field) {
    final raw = _asString(value, field);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw BackupException('Date invalide : $field.');
    }
    return parsed.toLocal();
  }
}
