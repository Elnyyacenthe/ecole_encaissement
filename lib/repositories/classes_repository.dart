import '../core/db/mysql_connection_service.dart';
import '../models/classe.dart';

class ClassesRepository {
  final MySqlConnectionService db;
  ClassesRepository(this.db);

  Future<List<Classe>> all() async {
    final rows = await db.select(
      'SELECT id, name, section, level, display_order FROM classes ORDER BY display_order',
    );
    return rows.map(Classe.fromRow).toList();
  }

  /// Every classe with its non-cancelled headcount for [schoolYearId] —
  /// includes "provisoire" (promoted-but-unconfirmed) students, since they
  /// are registered in the class even if their enrolment isn't confirmed yet.
  Future<List<ClasseHeadcount>> headcounts(int schoolYearId) async {
    final rows = await db.select(
      '''
SELECT c.id, c.name, c.section, c.level, c.display_order,
  (SELECT COUNT(*) FROM students s WHERE s.classe_id = c.id
    AND s.school_year_id = ? AND s.annule = 0) AS total
FROM classes c
ORDER BY c.display_order
''',
      [schoolYearId],
    );
    return [
      for (final r in rows)
        ClasseHeadcount(
          classe: Classe.fromRow(r),
          total: (r['total'] as num).toInt(),
        ),
    ];
  }
}
