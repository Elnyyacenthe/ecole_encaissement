import 'cancellation.dart';
import 'tariff.dart';

class Payment {
  final int id;
  final int invoiceNumber;
  final int studentId;
  final Poste poste;
  final int montantPaye;

  /// Date entered by the cashier (defaults to today).
  final DateTime datePaiement;

  /// Server-side timestamp of the insert; used for the time printed on the receipt.
  final DateTime createdAt;
  final String operateur;
  final Cancellation? cancellation;

  const Payment({
    required this.id,
    required this.invoiceNumber,
    required this.studentId,
    required this.poste,
    required this.montantPaye,
    required this.datePaiement,
    required this.createdAt,
    required this.operateur,
    this.cancellation,
  });

  bool get isCancelled => cancellation != null;

  factory Payment.fromRow(Map<String, dynamic> row) => Payment(
    id: row['id'] as int,
    invoiceNumber: row['invoice_number'] as int,
    studentId: row['student_id'] as int,
    poste: Poste.fromDb(row['poste'] as String),
    montantPaye: row['montant_paye'] as int,
    datePaiement: row['date_paiement'] as DateTime,
    createdAt: row['created_at'] as DateTime,
    operateur: row['operateur'] as String,
    cancellation: Cancellation.fromRow(row),
  );
}

/// One invoice: a single deposit, possibly spread over several postes (each
/// poste is one [Payment] row sharing the invoice number). All lines of an
/// invoice are cancelled together, so [isCancelled] just looks at the first.
class Invoice {
  final int invoiceNumber;
  final List<Payment> lines;

  const Invoice({required this.invoiceNumber, required this.lines});

  /// Id of any row of the invoice; opens the receipt.
  int get firstPaymentId => lines.first.id;
  DateTime get datePaiement => lines.first.datePaiement;
  String get operateur => lines.first.operateur;
  int get total => lines.fold(0, (s, p) => s + p.montantPaye);
  bool get isCancelled => lines.first.isCancelled;
  Cancellation? get cancellation => lines.first.cancellation;

  /// Groups payment rows by invoice number, keeping the input order of the
  /// first row of each invoice.
  static List<Invoice> group(Iterable<Payment> rows) {
    final byInvoice = <int, List<Payment>>{};
    for (final r in rows) {
      byInvoice.putIfAbsent(r.invoiceNumber, () => []).add(r);
    }
    return [
      for (final e in byInvoice.entries)
        Invoice(
          invoiceNumber: e.key,
          lines: [...e.value]..sort((a, b) => a.poste.index - b.poste.index),
        ),
    ];
  }
}
