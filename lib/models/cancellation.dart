/// Audit trail of a cancelled payment or student registration. Records are
/// never deleted, only marked cancelled — this is what makes that visible
/// everywhere the record is shown.
class Cancellation {
  final String cancelledBy;
  final DateTime cancelledAt;
  final String reason;

  const Cancellation({
    required this.cancelledBy,
    required this.cancelledAt,
    required this.reason,
  });

  /// Reads the four `annule*` columns a row carries; null when not cancelled.
  static Cancellation? fromRow(Map<String, dynamic> row) {
    final flag = row['annule'];
    final cancelled = flag == 1 || flag == true;
    if (!cancelled) return null;
    return Cancellation(
      cancelledBy: row['annule_par'] as String? ?? '',
      cancelledAt: row['annule_le'] as DateTime? ?? DateTime.now(),
      reason: row['motif_annulation'] as String? ?? '',
    );
  }
}
