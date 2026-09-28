import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/utils/formatters.dart';
import '../models/tariff.dart';
import '../repositories/reports_repository.dart';
import 'receipt_labels.dart';

/// Internal report (French only): every student who has not fully paid [poste].
Future<Uint8List> buildUnpaidReportPdf({
  required List<UnpaidRow> rows,
  required Poste poste,
  required String schoolYearLabel,
  DateTime? asOf,
  Uint8List? logo,
}) async {
  final doc = pw.Document(title: 'Impayés - ${poste.labelFr}');
  final now = DateTime.now();
  final totalReste = rows.fold<int>(0, (s, r) => s + r.reste);
  final totalPaye = rows.fold<int>(0, (s, r) => s + r.montantPaye);
  final overdueCount = rows.where((r) => r.isOverdue(now)).length;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              if (logo != null) ...[
                pw.Image(
                  pw.MemoryImage(logo),
                  width: 48,
                  height: 48,
                  fit: pw.BoxFit.contain,
                ),
                pw.SizedBox(width: 10),
              ],
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    ReceiptLabels.fr.schoolName,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '${ReceiptLabels.fr.address} - ${ReceiptLabels.fr.phone}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.Text(
            'Rapport des impayés - ${poste.labelFr}',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            "Année scolaire $schoolYearLabel - "
            "${asOf == null ? 'tous paiements' : 'paiements au ${formatDate(asOf)}'} - "
            'édité le ${formatDate(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 10),
        ],
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${ctx.pageNumber}/${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: [
            'N°',
            'Matricule',
            'Nom',
            'Classe',
            'Déjà payé',
            'Reste dû',
            'Date limite',
          ],
          data: [
            for (var i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                rows[i].matricule,
                rows[i].fullName,
                rows[i].classeName,
                formatMontant(rows[i].montantPaye),
                formatMontant(rows[i].reste),
                rows[i].dateLimite == null
                    ? '-'
                    : '${formatDate(rows[i].dateLimite!)}'
                          '${rows[i].isOverdue(now) ? ' (en retard)' : ''}',
              ],
          ],
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          textStyleBuilder: (index, data, rowNum) =>
              rows[rowNum - 1].isOverdue(now)
              ? pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.red800,
                  fontWeight: pw.FontWeight.bold,
                )
              : null,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignments: {
            0: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FixedColumnWidth(28),
            1: const pw.FixedColumnWidth(60),
            2: const pw.FlexColumnWidth(3),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FixedColumnWidth(72),
            5: const pw.FixedColumnWidth(72),
            6: const pw.FixedColumnWidth(78),
          },
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${rows.length} élève(s) - déjà payé : ${formatMontant(totalPaye)} - '
            'total restant dû : ${formatMontant(totalReste)}'
            '${overdueCount == 0 ? '' : ' - dont $overdueCount en retard'}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  return doc.save();
}
