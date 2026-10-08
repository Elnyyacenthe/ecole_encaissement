import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/utils/formatters.dart';
import '../models/classe.dart';
import '../models/receipt_data.dart';
import '../models/school_identity.dart';
import 'pdf_widgets.dart';
import 'receipt_labels.dart';

/// A5-width page sized just tall enough for this receipt's actual content
/// (1 to 4 fee lines, optional due dates, optional ANNULÉ banner) — instead
/// of a fixed A4/A5 height that leaves most of the sheet blank. Generous
/// per-element estimates are used so nothing gets clipped; the numbers are
/// derived from the exact widgets/paddings in [buildReceiptPdf] below.
PdfPageFormat receiptPageFormat(ReceiptData data) {
  const width = 420.0; // A5 width
  var height = 300.0; // margins + header + divider + title + spacers
  height += 65; // two-column info block (up to 4 kv rows on one side)
  height += 30; // table header row + spacing before/after
  height += data.lines.length * 24; // one row per poste
  height += data.lines
          .where((l) => l.dateLimite != null && l.difference > 0)
          .length *
      14; // one due-date line per unpaid poste
  height += 45; // "reste sur l'année" + "total payé ce jour" block
  if (data.isCancelled) height += 60; // ANNULÉ banner
  return PdfPageFormat(width, height);
}

/// One-page receipt whose language follows the student's section.
Future<Uint8List> buildReceiptPdf(
  ReceiptData data, {
  Uint8List? logo,
  PdfPageFormat? format,
  SchoolIdentity? identity,
}) async {
  format ??= receiptPageFormat(data);
  final labels = ReceiptLabels.forSection(
    Section.fromDb(data.student.section),
    schoolName: identity?.name,
    schoolBox: identity?.box,
    schoolPhone: identity?.phone,
  );
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
