import 'cancellation.dart';
import 'payment_situation.dart';

/// One invoice as listed in the payment history: who paid, when, how much and
/// how it was spread over the postes.
class InvoiceSummary {
  final int invoiceNumber;

  /// Id of any row of the invoice; opens its receipt.
  final int firstPaymentId;
  final int studentId;
  final String matricule;
  final String fullName;
  final String classeName;
  final DateTime datePaiement;
  final DateTime createdAt;
  final String operateur;
  final List<PosteAllocation> lines;
  final Cancellation? cancellation;

  const InvoiceSummary({
    required this.invoiceNumber,
    required this.firstPaymentId,
    required this.studentId,
    required this.matricule,
    required this.fullName,
    required this.classeName,
    required this.datePaiement,
    required this.createdAt,
    required this.operateur,
    required this.lines,
    this.cancellation,
  });

  bool get isCancelled => cancellation != null;
  int get total => lines.fold(0, (s, l) => s + l.montant);
}
