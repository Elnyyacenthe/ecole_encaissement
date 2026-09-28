import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/utils/formatters.dart';
import '../models/classe.dart';
import '../models/receipt_data.dart';
import 'pdf_widgets.dart';
import 'receipt_labels.dart';

/// One-page receipt whose language follows the student's section.
Future<Uint8List> buildReceiptPdf(
  ReceiptData data, {
  Uint8List? logo,
  PdfPageFormat format = PdfPageFormat.a5,
}) async {
  final labels = ReceiptLabels.forSection(Section.fromDb(data.student.section));
  final niveau = Niveau.fromDb(data.student.niveau);
  final doc = pw.Document(title: '${labels.title} ${data.invoiceNumber}');
  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pdfDocumentHeader(labels, logo),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1.2),
          pw.SizedBox(height: 6),
          if (data.isCancelled) ...[
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.red50,
                border: pw.Border.all(color: PdfColors.red700, width: 1.2),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    labels.cancelledBanner,
                    style: pw.TextStyle(
                      color: PdfColors.red700,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '${labels.cancelledReason} : ${data.cancellation!.reason} '
                    '(${formatDate(data.cancellation!.cancelledAt)})',
                    style: pw.TextStyle(color: PdfColors.red700, fontSize: 9),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
          ],
          pw.Center(
            child: pw.Text(
              labels.title,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pdfKv(
                      labels.invoiceNumber,
                      '${data.invoiceNumber}',
                      bold: true,
                    ),
                    pdfKv(
                      labels.dateTime,
                      '${formatDate(data.datePaiement)} ${formatTime(data.createdAt)}',
                    ),
                    pdfKv(labels.operator, data.operateur),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pdfKv(
                      labels.student,
                      data.student.student.fullName,
                      bold: true,
                    ),
                    pdfKv(labels.matricule, data.student.student.matricule),
                    pdfKv(labels.classe, data.student.classeName),
                    pdfKv(labels.niveau, labels.niveauLabel(niveau)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.6),
              1: const pw.FlexColumnWidth(1.3),
              2: const pw.FlexColumnWidth(1.3),
              3: const pw.FlexColumnWidth(1.3),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  pdfCell(labels.item, bold: true),
                  pdfCell(labels.netAPayer, bold: true),
                  pdfCell(labels.montantPaye, bold: true),
                  pdfCell(labels.difference, bold: true),
                ],
              ),
              for (final line in data.lines)
                pw.TableRow(
                  children: [
                    pdfCell(labels.posteLabel(line.poste), left: true),
                    pdfCell(formatMontant(line.netAPayer)),
                    pdfCell(formatMontant(line.montantPaye), bold: true),
                    pdfCell(formatMontant(line.difference)),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 8),
          for (final line in data.lines)
            if (line.dateLimite != null && line.difference > 0)
              pw.Text(
                '${labels.posteLabel(line.poste)} - ${labels.dueDate} : '
                '${formatDate(line.dateLimite!)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${labels.resteSurAnnee} : ${formatMontant(data.resteSurAnnee)}',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${labels.totalPaidToday} : ${formatMontant(data.totalPayeCeJour)}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
