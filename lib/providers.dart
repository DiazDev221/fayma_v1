import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/credit_repository.dart';
import 'models/balance.dart';
import 'models/client.dart';
import 'models/operation.dart';
import 'services/backup/backup_file_saver.dart';
import 'services/backup/backup_service.dart';
import 'services/backup/backup_settings.dart';
import 'services/pdf/pdf_export_service.dart';
import 'services/shop_settings.dart';
import 'services/sms_sender.dart';

/// Source de données de l'application.
///
/// Fournie au démarrage dans `main.dart` (SQLite). Les tests la remplacent
/// par la version en mémoire.
final creditRepositoryProvider = Provider<CreditRepository>((ref) {
  throw UnimplementedError(
    'creditRepositoryProvider doit être remplacé dans le ProviderScope.',
  );
});

/// SMS aux clients : ouvre l'application SMS du téléphone, message pré-rempli.
final smsSenderProvider = Provider<SmsSender>((ref) {
  return createPlatformSmsSender();
});

/// Identifiants et date de la dernière sauvegarde.
final backupSettingsProvider = Provider<BackupSettingsStore>((ref) {
  return BackupSettings();
});

/// Paramètres de la boutique (nom utilisé dans les SMS).
final shopSettingsProvider = Provider<ShopSettingsStore>((ref) {
  return ShopSettings();
});

/// Nom de la boutique, chargé depuis les préférences locales.
///
/// Une erreur de stockage ne doit pas empêcher l'application de fonctionner :
/// on retombe alors sur un nom vide, et les SMS sont envoyés sans signature.
final shopNameProvider = FutureProvider<String>((ref) async {
  try {
    return await ref.watch(shopSettingsProvider).readShopName();
  } catch (error) {
    debugPrint('Lecture du nom de la boutique : $error');
    return '';
  }
});

/// Export et restauration des données de la boutique.
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    repository: ref.watch(creditRepositoryProvider),
    settings: ref.watch(backupSettingsProvider),
    shopSettings: ref.watch(shopSettingsProvider),
  );
});

/// Enregistrement direct d'une sauvegarde dans le gestionnaire de fichiers.
final backupFileSaverProvider = Provider<BackupFileSaver>((ref) {
  return const BackupFileSaver();
});

/// Factures et rapport général au format PDF.
final pdfExportServiceProvider = Provider<PdfExportService>((ref) {
  return const PdfExportService();
});

/// Tous les clients de la boutique, triés par nom.
final clientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(creditRepositoryProvider).watchClients();
});

/// Toutes les opérations de la boutique.
final allOperationsProvider = StreamProvider<List<Operation>>((ref) {
  return ref.watch(creditRepositoryProvider).watchOperations();
});

/// Opérations d'un seul client (historique de la fiche client).
final clientOperationsProvider =
    StreamProvider.family<List<Operation>, String>((ref, clientId) {
  return ref
      .watch(creditRepositoryProvider)
      .watchOperations(clientId: clientId);
});

/// Un client avec sa situation calculée (dette, dépôt).
class ClientSummary {
  const ClientSummary({required this.client, required this.balance});

  final Client client;
  final Balance balance;

  bool get hasDebt => balance.debt > 0;
}

/// Clients avec leur solde, pour la liste de l'accueil.
final clientSummariesProvider =
    Provider<AsyncValue<List<ClientSummary>>>((ref) {
  final clients = ref.watch(clientsProvider);
  final operations = ref.watch(allOperationsProvider);

  if (clients.hasError) {
    return AsyncError(clients.error!, clients.stackTrace ?? StackTrace.current);
  }
  if (operations.hasError) {
    return AsyncError(
      operations.error!,
      operations.stackTrace ?? StackTrace.current,
    );
  }

  final clientList = clients.valueOrNull;
  final operationList = operations.valueOrNull;
  if (clientList == null || operationList == null) {
    return const AsyncLoading();
  }

  final byClient = <String, List<Operation>>{};
  for (final op in operationList) {
    byClient.putIfAbsent(op.clientId, () => []).add(op);
  }

  return AsyncData([
    for (final client in clientList)
      ClientSummary(
        client: client,
        balance: computeBalance(byClient[client.id] ?? const []),
      ),
  ]);
});

/// Un client précis avec son solde. Null si le client n'existe pas.
final clientSummaryProvider =
    Provider.family<AsyncValue<ClientSummary?>, String>((ref, clientId) {
  return ref.watch(clientSummariesProvider).whenData((summaries) {
    for (final summary in summaries) {
      if (summary.client.id == clientId) return summary;
    }
    return null;
  });
});

/// Chiffres de la jauge de l'accueil.
class ShopTotals {
  const ShopTotals({
    required this.totalDue,
    required this.totalOriginal,
    required this.clientsWithDebt,
    required this.totalDeposits,
  });

  /// Total à recevoir, en FCFA.
  final int totalDue;

  /// Montant d'origine des dettes encore ouvertes, en FCFA.
  final int totalOriginal;

  /// Nombre de clients qui doivent encore de l'argent.
  final int clientsWithDebt;

  /// Total des avances disponibles chez les clients, en FCFA.
  final int totalDeposits;

  /// Part restant à encaisser, entre 0 et 1 (pour la jauge).
  double get dueShare => totalOriginal == 0 ? 0 : totalDue / totalOriginal;
}

final shopTotalsProvider = Provider<AsyncValue<ShopTotals>>((ref) {
  return ref.watch(clientSummariesProvider).whenData((summaries) {
    var due = 0;
    var original = 0;
    var count = 0;
    var deposits = 0;
    for (final summary in summaries) {
      deposits += summary.balance.deposit;
      if (summary.hasDebt) {
        due += summary.balance.debt;
        original += summary.balance.originalTotal;
        count++;
      }
    }
    return ShopTotals(
      totalDue: due,
      totalOriginal: original,
      clientsWithDebt: count,
      totalDeposits: deposits,
    );
  });
});
