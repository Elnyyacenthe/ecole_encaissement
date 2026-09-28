import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'receipt_labels.dart';

/// Shared building blocks for every printed document (receipt, unpaid
/// report, individual notice): school letterhead, a "label : value" line,
/// a table cell. Kept in one place so the look stays consistent everywhere.
pw.Widget pdfDocumentHeader(ReceiptLabels labels, Uint8List? logo) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.center,
  children: [
    if (logo != null) ...[
      pw.Image(
        pw.MemoryImage(logo),
        width: 74,
        height: 74,
        fit: pw.BoxFit.contain,
      ),
      pw.SizedBox(width: 14),
    ],
    pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            labels.schoolName,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(labels.address, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(labels.phone, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    ),
  ],
);

pw.Widget pdfKv(String label, String value, {bool bold = false}) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 3),
  child: pw.RichText(
    text: pw.TextSpan(
      children: [
        pw.TextSpan(text: '$label : ', style: const pw.TextStyle(fontSize: 9)),
        pw.TextSpan(
          text: value,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  ),
);

pw.Widget pdfCell(String text, {bool bold = false, bool left = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        textAlign: left ? pw.TextAlign.left : pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
