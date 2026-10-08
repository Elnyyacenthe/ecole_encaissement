import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/utils/formatters.dart';
import '../models/classe.dart';
import '../models/payment_situation.dart';
import '../models/school_identity.dart';
import '../models/tariff.dart';
import '../repositories/reports_repository.dart';
import 'pdf_widgets.dart';
import 'receipt_labels.dart';

/// Everything needed to print one student's individual notice: which poste
/// it is about (usually the one the unpaid report was filtered on) and their
/// full-year situation, so the family sees the whole picture, not just that
/// one line.
class NoticeData {
  final UnpaidRow row;
  final Poste subjectPoste;
  final StudentSituation situation;

  const NoticeData({
    required this.row,
    required this.subjectPoste,
    required this.situation,
  });
}

class _NoticeLabels {
  final String title;
  final String subject;
  final String overdue;
  final String signature;
  final String issuedOn;

  const _NoticeLabels({
    required this.title,
    required this.subject,
    required this.overdue,
    required this.signature,
    required this.issuedOn,
  });

  static const fr = _NoticeLabels(
    title: 'NOTE DE SUIVI DES PAIEMENTS',
    subject: 'Concerne',
    overdue: 'EN RETARD',
    signature: "Signature du chef d'établissement",
    issuedOn: 'Édité le',
  );

  static const en = _NoticeLabels(
    title: 'PAYMENT FOLLOW-UP NOTICE',
    subject: 'Subject',
    overdue: 'OVERDUE',
    signature: 'Head of school signature',
    issuedOn: 'Issued on',
  );
}

/// One page per student, each in French or English following that student's
/// section — pass a single-item list to print just one.
Future<Uint8List> buildIndividualNoticesPdf({
  required List<NoticeData> notices,
  Uint8List? logo,
  SchoolIdentity? identity,
}) async {
  final doc = pw.Document(
    title: notices.length == 1
        ? 'Note - ${notices.first.row.fullName}'
        : 'Notes individuelles',
  );
  final now = DateTime.now();

  for (final notice in notices) {
    final section = Section.fromDb(notice.row.section);
    final niveau = Niveau.fromDb(notice.row.niveau);
    final labels = ReceiptLabels.forSection(
      section,
      schoolName: identity?.name,
      schoolBox: identity?.box,
      schoolPhone: identity?.phone,
    );
    final n = section == Section.francophone
        ? _NoticeLabels.fr
        : _NoticeLabels.en;
    final subject = notice.situation.forPoste(notice.subjectPoste);
    final overdue =
        subject.dateLimite != null &&
        !subject.estSolde &&
        subject.dateLimite!.isBefore(now);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pdfDocumentHeader(labels, logo),
            pw.SizedBox(height: 14),
            pw.Divider(thickness: 1.2),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                n.title,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pdfKv(labels.student, notice.row.fullName, bold: true),
                      pdfKv(labels.matricule, notice.row.matricule),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pdfKv(labels.classe, notice.row.classeName),
                      pdfKv(labels.niveau, labels.niveauLabel(niveau)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: pw.BoxDecoration(
                color: overdue ? PdfColors.red100 : PdfColors.grey200,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${n.subject} : ${labels.posteLabel(notice.subjectPoste)}',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  if (overdue)
                    pw.Text(
                      n.overdue,
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.red800,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.6),
                1: pw.FixedColumnWidth(90),
                2: pw.FixedColumnWidth(90),
                3: pw.FixedColumnWidth(90),
                4: pw.FixedColumnWidth(85),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pdfCell(labels.item, bold: true, left: true),
                    pdfCell(labels.netAPayer, bold: true),
                    pdfCell(labels.montantPaye, bold: true),
                    pdfCell(labels.difference, bold: true),
                    pdfCell(labels.dueDate, bold: true),
                  ],
                ),
                for (final p in notice.situation.postes)
                  pw.TableRow(
                    decoration: p.poste == notice.subjectPoste
                        ? const pw.BoxDecoration(color: PdfColors.grey100)
                        : null,
                    children: [
                      pdfCell(
                        labels.posteLabel(p.poste),
                        left: true,
                        bold: p.poste == notice.subjectPoste,
                      ),
                      pdfCell(formatMontant(p.montantDu)),
                      pdfCell(formatMontant(p.montantPaye)),
                      pdfCell(p.estSolde ? '-' : formatMontant(p.resteAPayer)),
                      pdfCell(
                        p.dateLimite == null ? '-' : formatDate(p.dateLimite!),
                      ),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                '${labels.resteSurAnnee} : ${formatMontant(notice.situation.totalReste)}',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Spacer(),
            pw.Text(
              '${n.issuedOn} ${formatDate(now)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 32),
            pw.Container(
              width: 220,
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey600)),
              ),
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                n.signature,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}
