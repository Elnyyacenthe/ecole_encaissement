import 'package:mysql1/mysql1.dart';

/// Concurrency-safe sequences backed by the `counters` table.
///
/// Every method must be called with the [TransactionContext] of the same
/// transaction that inserts the row using the number: the `FOR UPDATE` row
/// lock is held until commit, so a second client (another PC) blocks until
/// the first commits, and a failed insert rolls the increment back too —
/// no duplicates, no gaps.
class SequenceService {
  static const invoiceKey = 'invoice_global';

  /// Not a sequence for records: bumped by triggers on every data change so
  /// other PCs know when to refresh.
  static const dataVersionKey = 'data_version';

  static String matriculeKey(String schoolYearLabel) =>
      'matricule_$schoolYearLabel';

  static Future<int> next(TransactionContext ctx, String key) async {
    // Lock the counter row first. (Doing INSERT IGNORE before this would take
    // a shared lock on the existing row, and two PCs each holding one while
    // waiting to upgrade it deadlock each other.)
    var rs = await ctx.query(
      'SELECT current_value FROM counters WHERE counter_key = ? FOR UPDATE',
      [key],
    );
    if (rs.isEmpty) {
      // First use of this counter (e.g. a new school year); IGNORE makes a
      // concurrent creation by another PC harmless.
      await ctx.query(
        'INSERT IGNORE INTO counters (counter_key, current_value) VALUES (?, 0)',
        [key],
      );
      rs = await ctx.query(
        'SELECT current_value FROM counters WHERE counter_key = ? FOR UPDATE',
        [key],
      );
    }
    final next = (rs.first['current_value'] as int) + 1;
    await ctx.query(
      'UPDATE counters SET current_value = ? WHERE counter_key = ?',
      [next, key],
    );
    return next;
  }

  static Future<String> nextMatricule(
    TransactionContext ctx,
    String schoolYearLabel, {
    required String prefix,
  }) async {
    final seq = await next(ctx, matriculeKey(schoolYearLabel));
    final yearSuffix = schoolYearLabel.substring(2, 4);
    return '$yearSuffix$prefix${seq.toString().padLeft(3, '0')}';
  }

  static Future<int> nextInvoiceNumber(TransactionContext ctx) =>
      next(ctx, invoiceKey);
}
