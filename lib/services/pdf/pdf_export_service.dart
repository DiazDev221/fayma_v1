import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/balance.dart';
import '../../models/client.dart';
import '../../models/operation.dart';
import 'general_report_pdf.dart';
import 'invoice_pdf.dart';

/// Génère les PDF et ouvre le partage du téléphone.
///
/// Les fichiers sont écrits dans le dossier temporaire de l'application :
/// l'utilisateur choisit ensuite de les envoyer, les imprimer ou les
/// enregistrer via la feuille de partage Android.
class PdfExportService {
  const PdfExportService();

  Future<void> shareOperationInvoice({
    required Client client,
    required Operation operation,
    required Balance currentBalance,
    required bool isCancelled,
    Rect? sharePositionOrigin,
  }) async {
    final bytes = await buildInvoicePdf(
      InvoicePdfData(
        client: client,
        operation: operation,
        currentBalance: currentBalance,
        generatedAt: DateTime.now(),
        isCancelled: isCancelled,
      ),
    );

    final baseTitle = switch (operation.type) {
      OperationType.credit => 'Facture d’achat à crédit',
      OperationType.repayment => 'Reçu de remboursement',
      OperationType.deposit => 'Reçu de dépôt',
    };
    final title = operation.isReversal ? 'Annulation · $baseTitle' : baseTitle;

    await _share(
      bytes: bytes,
      fileName: invoiceFileName(client, operation),
      subject: '$title · ${client.fullName}',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  Future<void> shareGeneralReport({
    required List<Client> clients,
    required List<Operation> operations,
    Rect? sharePositionOrigin,
  }) async {
    final generatedAt = DateTime.now();
    final bytes = await buildGeneralReportPdf(
      GeneralReportData(
        clients: clients,
        operations: operations,
        generatedAt: generatedAt,
      ),
    );

    await _share(
      bytes: bytes,
      fileName: generalReportFileName(generatedAt),
      subject: 'Rapport général · Fayma',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  Future<void> _share({
    required Uint8List bytes,
    required String fileName,
    required String subject,
    Rect? sharePositionOrigin,
  }) async {
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'fayma_pdf'),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        title: subject,
        subject: subject,
        files: [
          XFile(file.path, mimeType: 'application/pdf'),
        ],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}

/// Nom de fichier lisible et unique pour une facture.
String invoiceFileName(Client client, Operation operation) {
  final prefix = operation.isReversal
      ? 'annulation'
      : switch (operation.type) {
          OperationType.credit => 'facture_credit',
          OperationType.repayment => 'recu_remboursement',
          OperationType.deposit => 'recu_depot',
        };
  return '${prefix}_${_fileSlug(client.fullName)}_'
      '${_fileStamp(operation.date)}.pdf';
}

String generalReportFileName(DateTime generatedAt) =>
    'rapport_general_fayma_${_fileStamp(generatedAt)}.pdf';

String _fileSlug(String value) {
  final cleaned = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '')
      .replaceAll(RegExp(r'\s+'), '_');
  return cleaned.isEmpty ? 'client' : cleaned;
}

String _fileStamp(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}${two(date.month)}${two(date.day)}'
      '_${two(date.hour)}${two(date.minute)}';
}
