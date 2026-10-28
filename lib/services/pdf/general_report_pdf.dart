import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/balance.dart';
import '../../models/client.dart';
import '../../models/operation.dart';
import '../../utils/format.dart';
import '../../utils/operation_order.dart';
import 'pdf_style.dart';

/// Données du rapport général de la boutique.
class GeneralReportData {
  const GeneralReportData({
    required this.clients,
    required this.operations,
    required this.generatedAt,
  });

  final List<Client> clients;
  final List<Operation> operations;
  final DateTime generatedAt;
}

/// Construit un rapport complet : synthèse, situation de chaque client et
/// journal des opérations. Le document est généré hors connexion.
Future<Uint8List> buildGeneralReportPdf(GeneralReportData data) async {
  final regular = await PdfFonts.regular();
  final bold = await PdfFonts.bold();

  final clients = [...data.clients]
    ..sort((a, b) => a.fullName.toLowerCase().compareTo(
          b.fullName.toLowerCase(),
        ));
  final operations = data.operations;

  final operationsByClient = <String, List<Operation>>{};
  for (final operation in operations) {
    operationsByClient.putIfAbsent(operation.clientId, () => []).add(operation);
  }

  final balances = <String, Balance>{
    for (final client in clients)
      client.id: computeBalance(operationsByClient[client.id] ?? const []),
  };

  final reversedIds = <String>{
    for (final operation in operations)
      if (operation.reversalOf != null) operation.reversalOf!,
  };

  var totalDue = 0;
  var totalDeposit = 0;
  var clientsWithDebt = 0;
  var clientsWithDeposit = 0;
  for (final client in clients) {
    final balance = balances[client.id] ?? Balance.empty;
    totalDue += balance.debt;
    totalDeposit += balance.deposit;
    if (balance.debt > 0) clientsWithDebt++;
    if (balance.deposit > 0) clientsWithDeposit++;
  }

  var totalPurchases = 0;
  var totalRepayments = 0;
  var totalDepositsReceived = 0;
  for (final operation in operations) {
    if (operation.isReversal || reversedIds.contains(operation.id)) {
      continue;
    }
    switch (operation.type) {
      case OperationType.credit:
        totalPurchases += operation.amount;
      case OperationType.repayment:
        totalRepayments += operation.amount;
      case OperationType.deposit:
        totalDepositsReceived += operation.amount;
    }
  }

  final sortedOperations = sortOperationsByMostRecent(operations);

  final clientNames = <String, String>{
    for (final client in clients) client.id: client.fullName,
  };

  final document = pw.Document(
    title: 'Rapport général · Fayma',
    author: 'Fayma',
    creator: 'Fayma',
    subject: 'Situation de la boutique et journal des opérations',
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 34, 36, 30),
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: regular,
        boldItalic: bold,
      ),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pdfContinuationHeader('Rapport général · Fayma'),
      footer: (context) => pdfPageFooter(context, data.generatedAt),
      build: (context) => [
        pdfBrandHeader(
          title: 'RAPPORT GÉNÉRAL',
          subtitle: 'Situation de la boutique',
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Généré le ${pdfDateTime(data.generatedAt)}',
              style: const pw.TextStyle(
                color: PdfStyle.textSecondary,
                fontSize: 8.5,
              ),
            ),
            pw.Text(
              '${clients.length} client${clients.length > 1 ? 's' : ''} · '
              '${operations.length} opération'
              '${operations.length > 1 ? 's' : ''}',
              style: const pw.TextStyle(
                color: PdfStyle.textSecondary,
                fontSize: 8.5,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            pw.Expanded(
              child: _metricCard(
                'Clients',
                '${clients.length}',
                PdfStyle.indigo,
                PdfStyle.indigoSoft,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricCard(
                'Total à recevoir',
                pdfFcfa(totalDue),
                PdfStyle.coral,
                PdfStyle.coralSoft,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricCard(
                'Dépôts disponibles',
                pdfFcfa(totalDeposit),
                PdfStyle.mintDark,
                PdfStyle.mintSoft,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            pw.Expanded(
              child: _metricCard(
                'Clients à crédit',
                '$clientsWithDebt',
                PdfStyle.coral,
                PdfStyle.coralSoft,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricCard(
                'Achats cumulés',
                pdfFcfa(totalPurchases),
                PdfStyle.indigo,
                PdfStyle.indigoSoft,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricCard(
                'Encaissements cumulés',
                pdfFcfa(totalRepayments + totalDepositsReceived),
                PdfStyle.mintDark,
                PdfStyle.mintSoft,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 22),
        pdfSectionTitle(
          'Situation des clients',
          subtitle: clientsWithDeposit > 0
              ? '$clientsWithDebt à crédit · $clientsWithDeposit avec un dépôt'
              : '$clientsWithDebt client${clientsWithDebt > 1 ? 's' : ''} '
                  'à crédit',
        ),
        pw.SizedBox(height: 9),
        if (clients.isEmpty)
          _emptyMessage('Aucun client enregistré dans la boutique.')
        else
          _clientsTable(
            clients: clients,
            balances: balances,
            totalDue: totalDue,
            totalDeposit: totalDeposit,
          ),
        pw.SizedBox(height: 24),
        pdfSectionTitle(
          'Journal des opérations',
          subtitle: operations.isEmpty
              ? 'Aucune opération enregistrée'
              : '${operations.length} opération'
                  '${operations.length > 1 ? 's' : ''}, de la plus récente '
                  'à la plus ancienne',
        ),
        pw.SizedBox(height: 9),
        if (operations.isEmpty)
          _emptyMessage('Aucune opération enregistrée dans la boutique.')
        else
          _operationsTable(
            operations: sortedOperations,
            clientNames: clientNames,
            reversedIds: reversedIds,
          ),
        pw.SizedBox(height: 18),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(top: 9),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfStyle.border, width: 0.6),
            ),
          ),
          child: pw.Text(
            'Rapport généré automatiquement par Fayma. Les montants sont '
            'exprimés en francs CFA. Les opérations annulées restent visibles '
            'dans le journal pour conserver l’historique du compte.',
            style: const pw.TextStyle(
              color: PdfStyle.textSecondary,
              fontSize: 8,
              lineSpacing: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  return document.save();
}

pw.Widget _metricCard(
  String label,
  String value,
  PdfColor color,
  PdfColor background,
) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    decoration: pw.BoxDecoration(
      color: background,
      borderRadius: pw.BorderRadius.circular(9),
      border: pw.Border.all(color: color, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(
            color: PdfStyle.textSecondary,
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _clientsTable({
  required List<Client> clients,
  required Map<String, Balance> balances,
  required int totalDue,
  required int totalDeposit,
}) {
  return pw.Table(
    border: const pw.TableBorder(
      top: pw.BorderSide(color: PdfStyle.border, width: 0.7),
      bottom: pw.BorderSide(color: PdfStyle.border, width: 0.7),
      horizontalInside: pw.BorderSide(color: PdfStyle.border, width: 0.5),
    ),
    columnWidths: {
      0: const pw.FlexColumnWidth(3),
      1: const pw.FlexColumnWidth(1.7),
      2: const pw.FlexColumnWidth(1.2),
      3: const pw.FlexColumnWidth(1.2),
      4: const pw.FlexColumnWidth(1.2),
    },
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfStyle.surfaceMuted),
        children: [
          pdfCell('Client', bold: true),
          pdfCell('Téléphone', bold: true),
          pdfCell('Dette', bold: true, align: pw.TextAlign.right),
          pdfCell('Dépôt', bold: true, align: pw.TextAlign.right),
          pdfCell('Statut', bold: true, align: pw.TextAlign.right),
        ],
      ),
      for (final client in clients)
        _clientRow(client, balances[client.id] ?? Balance.empty),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfStyle.surfaceMuted),
        children: [
          pdfCell(
            'TOTAL · ${clients.length} client${clients.length > 1 ? 's' : ''}',
            bold: true,
          ),
          pdfCell(''),
          pdfCell(
            pdfFcfa(totalDue),
            bold: true,
            align: pw.TextAlign.right,
            color: totalDue > 0 ? PdfStyle.coral : PdfStyle.mintDark,
          ),
          pdfCell(
            pdfFcfa(totalDeposit),
            bold: true,
            align: pw.TextAlign.right,
            color:
                totalDeposit > 0 ? PdfStyle.mintDark : PdfStyle.textSecondary,
          ),
          pdfCell(''),
        ],
      ),
    ],
  );
}

pw.TableRow _clientRow(Client client, Balance balance) {
  final String status;
  final PdfColor statusColor;
  if (balance.debt > 0) {
    status = 'À crédit';
    statusColor = PdfStyle.coral;
  } else if (balance.deposit > 0) {
    status = 'Dépôt';
    statusColor = PdfStyle.mintDark;
  } else {
    status = 'À jour';
    statusColor = PdfStyle.textSecondary;
  }

  return pw.TableRow(
    children: [
      pdfCell(client.fullName, bold: true),
      pdfCell(formatPhone(client.telephone)),
      pdfCell(
        pdfFcfa(balance.debt),
        align: pw.TextAlign.right,
        color: balance.debt > 0 ? PdfStyle.coral : PdfStyle.textSecondary,
      ),
      pdfCell(
        pdfFcfa(balance.deposit),
        align: pw.TextAlign.right,
        color: balance.deposit > 0 ? PdfStyle.mintDark : PdfStyle.textSecondary,
      ),
      pdfCell(
        status,
        align: pw.TextAlign.right,
        bold: true,
        color: statusColor,
      ),
    ],
  );
}

pw.Widget _operationsTable({
  required List<Operation> operations,
  required Map<String, String> clientNames,
  required Set<String> reversedIds,
}) {
  return pw.Table(
    border: const pw.TableBorder(
      top: pw.BorderSide(color: PdfStyle.border, width: 0.7),
      bottom: pw.BorderSide(color: PdfStyle.border, width: 0.7),
      horizontalInside: pw.BorderSide(color: PdfStyle.border, width: 0.5),
    ),
    columnWidths: {
      0: const pw.FlexColumnWidth(1),
      1: const pw.FlexColumnWidth(2.3),
      2: const pw.FlexColumnWidth(2.2),
      3: const pw.FlexColumnWidth(1.35),
      4: const pw.FlexColumnWidth(1),
    },
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfStyle.surfaceMuted),
        children: [
          pdfCell('Date', bold: true),
          pdfCell('Client', bold: true),
          pdfCell('Opération', bold: true),
          pdfCell('Montant', bold: true, align: pw.TextAlign.right),
          pdfCell('Statut', bold: true, align: pw.TextAlign.right),
        ],
      ),
      for (final operation in operations)
        _operationRow(
          operation,
          clientNames[operation.clientId] ?? 'Client inconnu',
          reversedIds,
        ),
    ],
  );
}

pw.TableRow _operationRow(
  Operation operation,
  String clientName,
  Set<String> reversedIds,
) {
  final isCancelled = reversedIds.contains(operation.id);
  final effect = switch (operation.type) {
    OperationType.credit => operation.sign,
    OperationType.repayment => -operation.sign,
    OperationType.deposit => operation.sign,
  };
  final amount = effect * operation.amount;

  final status = operation.isReversal
      ? 'Annulation'
      : isCancelled
          ? 'Annulée'
          : 'Validée';
  final statusColor =
      operation.isReversal || isCancelled ? PdfStyle.coral : PdfStyle.mintDark;

  return pw.TableRow(
    children: [
      pdfCell(pdfDate(operation.date)),
      pdfCell(clientName),
      pdfCell(operationLabel(operation)),
      pdfCell(
        pdfSignedFcfa(amount),
        align: pw.TextAlign.right,
        bold: true,
        color: amount < 0 ? PdfStyle.coral : PdfStyle.mintDark,
      ),
      pdfCell(
        status,
        align: pw.TextAlign.right,
        color: statusColor,
      ),
    ],
  );
}

pw.Widget _emptyMessage(String message) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: pw.BoxDecoration(
      color: PdfStyle.surfaceMuted,
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Text(
      message,
      style: const pw.TextStyle(
        color: PdfStyle.textSecondary,
        fontSize: 9,
      ),
    ),
  );
}
