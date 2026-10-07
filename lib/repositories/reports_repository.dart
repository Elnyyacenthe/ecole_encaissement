import '../core/db/mysql_connection_service.dart';
import '../models/tariff.dart';

class UnpaidRow {
  final int studentId;
  final String matricule;
  final String fullName;
  final String classeName;
  final String section;
  final String niveau;
  final int montantDu;
  final int montantPaye;
  final DateTime? dateLimite;

  const UnpaidRow({
    required this.studentId,
    required this.matricule,
    required this.fullName,
    required this.classeName,
    required this.section,
    required this.niveau,
    required this.montantDu,
    required this.montantPaye,
    this.dateLimite,
  });

  int get reste => montantDu - montantPaye;

  /// True once the due date has passed and something is still owed — the
  /// automatic flag the school uses to see who is actually late.
  bool isOverdue(DateTime asOf) =>
      dateLimite != null && reste > 0 && dateLimite!.isBefore(asOf);
}

int _int(Object? v) => (v as num).toInt();

class DashboardStats {
  final int studentCount;
  final int paymentsToday;
  final int totalToday;
  final int cancellationsToday;
  const DashboardStats({
    required this.studentCount,
    required this.paymentsToday,
    required this.totalToday,
    required this.cancellationsToday,
  });
}

class ReportsRepository {
  final MySqlConnectionService db;
  ReportsRepository(this.db);

  Future<DashboardStats> dashboard(int schoolYearId) async {
    final rows = await db.select(
      '''
SELECT
  (SELECT COUNT(*) FROM students WHERE school_year_id = ? AND annule = 0) AS students,
  (SELECT COUNT(DISTINCT invoice_number) FROM payments WHERE date_paiement = CURDATE() AND annule = 0) AS pay_count,
  CAST((SELECT COALESCE(SUM(montant_paye), 0) FROM payments WHERE date_paiement = CURDATE() AND annule = 0) AS SIGNED) AS pay_total,
  ((SELECT COUNT(*) FROM students WHERE annule = 1 AND DATE(annule_le) = CURDATE()) +
   (SELECT COUNT(DISTINCT invoice_number) FROM payments WHERE annule = 1 AND DATE(annule_le) = CURDATE())) AS cancellations
''',
      [schoolYearId],
    );
    final r = rows.first;
    return DashboardStats(
      studentCount: _int(r['students']),
      paymentsToday: _int(r['pay_count']),
      totalToday: _int(r['pay_total']),
      cancellationsToday: _int(r['cancellations']),
    );
  }

  /// Students of [schoolYearId] who have not fully paid [poste], counting
  /// only payments dated on or before [asOf] (all payments when null).
  /// Narrowed to one classe with [classeId] — "par classe" — or left as the
  /// whole school when null — "pour tout le monde".
  Future<List<UnpaidRow>> unpaid({
    required int schoolYearId,
    required Poste poste,
    DateTime? asOf,
    int? classeId,
  }) async {
    final asOfDb = asOf == null ? null : toDbDate(asOf);
    final rows = await db.select(
      '''
SELECT s.id AS student_id, s.matricule, s.full_name, c.name AS classe_name, c.section,
  c.level AS niveau, t.montant, t.date_limite,
  CAST(COALESCE((SELECT SUM(p.montant_paye) FROM payments p
                 WHERE p.student_id = s.id AND p.poste = t.poste AND p.annule = 0
                 ${asOf == null ? '' : 'AND p.date_paiement <= ?'}), 0) AS SIGNED) AS paid
FROM students s
JOIN classes c ON c.id = s.classe_id
JOIN tariffs t ON t.school_year_id = s.school_year_id AND t.niveau = c.level AND t.poste = ?
WHERE s.school_year_id = ? AND s.annule = 0 AND s.confirme = 1
${classeId == null ? '' : 'AND s.classe_id = ? '}
HAVING paid < t.montant
ORDER BY c.display_order, s.full_name
''',
      [?asOfDb, poste.dbValue, schoolYearId, ?classeId],
    );
    return [
      for (final r in rows)
        UnpaidRow(
          studentId: _int(r['student_id']),
          matricule: r['matricule'] as String,
          fullName: r['full_name'] as String,
          classeName: r['classe_name'] as String,
          section: r['section'] as String,
          niveau: r['niveau'] as String,
          montantDu: _int(r['montant']),
          montantPaye: _int(r['paid']),
          dateLimite: r['date_limite'] as DateTime?,
        ),
    ];
  }
}
