import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/balance.dart';
import '../../models/client.dart';
import '../../models/operation.dart';
import '../../utils/format.dart';
import 'pdf_style.dart';

/// Données nécessaires à une facture ou à un reçu.
class InvoicePdfData {
  const InvoicePdfData({
    required this.client,
    required this.operation,
    required this.currentBalance,
    required this.generatedAt,
    this.isCancelled = false,
  });

  final Client client;
  final Operation operation;

  /// Situation actuelle du client, affichée en bas du document.
  final Balance currentBalance;

  final DateTime generatedAt;

  /// Vrai si l'opération a été annulée par une opération inverse.
  final bool isCancelled;
}

/// Construit la facture d'un achat à crédit, ou le reçu d'un dépôt ou d'un
/// remboursement. Le document est généré entièrement hors connexion.
Future<Uint8List> buildInvoicePdf(InvoicePdfData data) async {
  final regular = await PdfFonts.regular();
  final bold = await PdfFonts.bold();
  final operation = data.operation;

  final title = _documentTitle(operation);
  final subtitle = _documentSubtitle(operation);
  final reference = _reference(operation);

  final document = pw.Document(
    title: '$title $reference · ${data.client.fullName}',
    author: 'Fayma',
    creator: 'Fayma',
    subject: subtitle,
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
          : pdfContinuationHeader(
              '$title $reference · ${data.client.fullName}'),
      footer: (context) => pdfPageFooter(context, data.generatedAt),
      build: (context) => [
        pdfBrandHeader(title: title, subtitle: subtitle),
        if (data.isCancelled || operation.isReversal) ...[
          pw.SizedBox(height: 12),
          if (data.isCancelled)
            pdfNotice(
              title: 'Opération annulée',
              message: 'Cette opération a été annulée dans l’application. '
                  'Le document reste conservé pour l’historique.',
              color: PdfStyle.coral,
              background: PdfStyle.coralSoft,
            )
          else
            pdfNotice(
              title: 'Document d’annulation',
              message: 'Ce document annule une opération enregistrée '
                  'précédemment. Le montant est présenté à titre de correction.',
              color: PdfStyle.coral,
              background: PdfStyle.coralSoft,
            ),
        ],
        pw.SizedBox(height: 18),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pdfInfoBlock(
                label: 'Client',
                lines: [
                  data.client.fullName,
                  formatPhone(data.client.telephone),
                ],
              ),
            ),
            pw.SizedBox(width: 18),
            pw.Expanded(
              flex: 2,
              child: pdfInfoBlock(
                label: 'Document',
                alignment: pw.CrossAxisAlignment.end,
                lines: [
                  'N° $reference',
                  pdfDateTime(operation.date),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pdfSectionTitle(
          _detailTitle(operation),
          subtitle: operation.isReversal
              ? 'Annulation de l’opération d’origine'
              : 'Détail de l’opération enregistrée',
        ),
        pw.SizedBox(height: 9),
        if (operation.type == OperationType.credit)
          _creditTable(operation)
        else
          _amountPanel(operation),
        if ((operation.note ?? '').trim().isNotEmpty) ...[
          pw.SizedBox(height: 12),
          _noteBox(operation.note!.trim()),
        ],
        pw.SizedBox(height: 20),
        _situationCard(data),
        pw.SizedBox(height: 18),
        _thanks(operation),
      ],
    ),
  );

  return document.save();
}

String _documentTitle(Operation operation) {
  if (operation.isReversal) return 'ANNULATION';
  return operation.type == OperationType.credit ? 'FACTURE' : 'REÇU';
}

String _documentSubtitle(Operation operation) {
  if (operation.isReversal) {
    return 'Annulation · ${operationTypeLabel(operation.type)}';
  }
  return operationTypeLabel(operation.type);
}

String _detailTitle(Operation operation) {
  if (operation.isReversal) return 'Opération annulée';
  return switch (operation.type) {
    OperationType.credit => 'Détail de l’achat',
    OperationType.repayment => 'Remboursement',
    OperationType.deposit => 'Dépôt',
  };
}

String _reference(Operation operation) {
  final prefix = operation.isReversal
      ? 'ANN'
      : switch (operation.type) {
          OperationType.credit => 'FAC',
          OperationType.deposit => 'DEP',
          OperationType.repayment => 'REM',
        };
  String two(int value) => value.toString().padLeft(2, '0');
  final date = operation.date;
  final stamp = '${date.year}${two(date.month)}${two(date.day)}'
      '-${two(date.hour)}${two(date.minute)}${two(date.second)}';
  return '$prefix-$stamp';
}

pw.Widget _creditTable(Operation operation) {
  final items = operation.items;
  return pw.Table(
    border: const pw.TableBorder(
      top: pw.BorderSide(color: PdfStyle.border, width: 0.7),
      bottom: pw.BorderSide(color: PdfStyle.border, width: 0.7),
      horizontalInside: pw.BorderSide(color: PdfStyle.border, width: 0.5),
    ),
    columnWidths: {
      0: const pw.FlexColumnWidth(),
      1: const pw.IntrinsicColumnWidth(),
    },
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfStyle.surfaceMuted),
        children: [
          pdfCell('Désignation', bold: true),
          pdfCell('Montant', align: pw.TextAlign.right, bold: true),
        ],
      ),
      if (items.isEmpty)
        pw.TableRow(
          children: [
            pdfCell(
              operation.isReversal
                  ? 'Annulation de l’achat à crédit'
                  : 'Achat à crédit',
            ),
            pdfCell(
              pdfFcfa(operation.amount),
              align: pw.TextAlign.right,
            ),
          ],
        )
      else
        for (final item in items)
          pw.TableRow(
            children: [
              pdfCell(item.name),
              pdfCell(
                pdfFcfa(item.price),
                align: pw.TextAlign.right,
              ),
            ],
          ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfStyle.mintSoft),
        children: [
          pdfCell(
            'Total',
            bold: true,
            color: PdfStyle.mintDark,
            fontSize: 10,
          ),
          pdfCell(
            pdfFcfa(operation.amount),
            align: pw.TextAlign.right,
            bold: true,
            color: PdfStyle.mintDark,
            fontSize: 10.5,
          ),
        ],
      ),
    ],
  );
}

pw.Widget _amountPanel(Operation operation) {
  final label = operation.isReversal
      ? 'Montant annulé'
      : switch (operation.type) {
          OperationType.credit => 'Montant de l’achat',
          OperationType.repayment => 'Montant remboursé',
          OperationType.deposit => 'Montant du dépôt',
        };

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    decoration: pw.BoxDecoration(
      color: PdfStyle.mintSoft,
      borderRadius: pw.BorderRadius.circular(10),
      border: pw.Border.all(color: PdfStyle.mint, width: 0.6),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: const pw.TextStyle(
                  color: PdfStyle.mintDark,
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                operation.isReversal
                    ? 'Correction enregistrée dans le compte du client'
                    : 'Paiement enregistré dans le compte du client'
                        '${operation.paymentMethod == null ? '' : ' · ${operation.paymentMethod!.label}'}',
                style: const pw.TextStyle(
                  color: PdfStyle.textSecondary,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Text(
          pdfFcfa(operation.amount),
          style: const pw.TextStyle(
            color: PdfStyle.mintDark,
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _noteBox(String note) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(11),
    decoration: pw.BoxDecoration(
      color: PdfStyle.surfaceMuted,
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Note',
          style: const pw.TextStyle(
            color: PdfStyle.textSecondary,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          note,
          style: const pw.TextStyle(
            color: PdfStyle.inkSoft,
            fontSize: 9,
            lineSpacing: 1.5,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _situationCard(InvoicePdfData data) {
  final balance = data.currentBalance;
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      color: PdfStyle.surfaceMuted,
      borderRadius: pw.BorderRadius.circular(10),
      border: pw.Border.all(color: PdfStyle.border, width: 0.6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'Situation du compte',
                style: const pw.TextStyle(
                  color: PdfStyle.ink,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Text(
              'Au ${pdfDateTime(data.generatedAt)}',
              style: const pw.TextStyle(
                color: PdfStyle.textSecondary,
                fontSize: 7.5,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            pw.Expanded(
              child: _situationValue(
                'Dette actuelle',
                pdfFcfa(balance.debt),
                balance.debt > 0 ? PdfStyle.coral : PdfStyle.mintDark,
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _situationValue(
                'Dépôt disponible',
                pdfFcfa(balance.deposit),
                balance.deposit > 0
                    ? PdfStyle.mintDark
                    : PdfStyle.textSecondary,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _situationValue(String label, String value, PdfColor color) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: const pw.TextStyle(
          color: PdfStyle.textSecondary,
          fontSize: 7.5,
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        value,
        style: pw.TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ],
  );
}

pw.Widget _thanks(Operation operation) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.only(top: 10),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfStyle.border, width: 0.6),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          operation.isReversal
              ? 'Document conservé pour l’historique du compte.'
              : 'Merci de votre confiance.',
          style: const pw.TextStyle(
            color: PdfStyle.ink,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Ce document est généré automatiquement par Fayma. '
          'Il récapitule une opération enregistrée dans votre boutique.',
          style: const pw.TextStyle(
            color: PdfStyle.textSecondary,
            fontSize: 8,
            lineSpacing: 1.4,
          ),
        ),
      ],
    ),
  );
}
