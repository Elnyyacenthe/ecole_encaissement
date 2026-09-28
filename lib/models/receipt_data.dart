import 'cancellation.dart';
import 'payment.dart';
import 'payment_situation.dart';
import 'student.dart';
import 'tariff.dart';

/// One poste settled (fully or partly) by an invoice.
class ReceiptLine {
  final Poste poste;
  final int netAPayer;
  final int montantPaye;

  /// What the poste still owes after this invoice.
  final int difference;
  final DateTime? dateLimite;

  const ReceiptLine({
    required this.poste,
    required this.netAPayer,
    required this.montantPaye,
    required this.difference,
    this.dateLimite,
  });
}

/// Everything needed to render one receipt. A single deposit can cover
/// several postes; all its rows share one invoice number. Figures are
/// computed "as of" the invoice (later payments are ignored) so reprinting
/// an old receipt gives the same numbers as the original.
class ReceiptData {
  final int invoiceNumber;
  final DateTime datePaiement;
  final DateTime createdAt;
  final String operateur;
  final StudentWithClasse student;
  final List<ReceiptLine> lines;
  final StudentSituation situation;

  /// Sum of everything this student paid on the invoice's date, up to and
  /// including this invoice.
  final int totalPayeCeJour;

  /// Set when this invoice was cancelled: the receipt then prints an
  /// unmistakable notice instead of pretending the payment still stands.
  final Cancellation? cancellation;

  const ReceiptData({
    required this.invoiceNumber,
    required this.datePaiement,
    required this.createdAt,
    required this.operateur,
    required this.student,
    required this.lines,
    required this.situation,
    required this.totalPayeCeJour,
    this.cancellation,
  });

  bool get isCancelled => cancellation != null;
  int get totalPayeFacture => lines.fold(0, (s, l) => s + l.montantPaye);
  int get resteSurAnnee => situation.totalReste;

  static List<ReceiptLine> buildLines(
    List<Payment> rows,
    StudentSituation situation,
  ) => [
    for (final r in rows)
      ReceiptLine(
        poste: r.poste,
        netAPayer: situation.forPoste(r.poste).montantDu,
        montantPaye: r.montantPaye,
        difference: situation.forPoste(r.poste).resteAPayer,
        dateLimite: situation.forPoste(r.poste).dateLimite,
      ),
  ];
}
