import 'package:mysql1/mysql1.dart';

import '../core/db/mysql_connection_service.dart';
import '../models/classe.dart';

class ClasseException implements Exception {
  final String message;
  ClasseException(this.message);
  @override
  String toString() => message;
}

const _duplicateKeyErrno = 1062;

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

  static final _duplicateNameError = ClasseException(
    'Une classe portant ce nom existe déjà dans cette section.',
  );

  /// Appends a new classe at the end of its curriculum order (displayed
  /// order can be refined afterwards with [reorder]).
  Future<int> create({
    required String name,
    required Section section,
    required Niveau niveau,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ClasseException('Le nom de la classe est obligatoire.');
    }
    try {
      return await db.transaction((ctx) async {
        final max = await ctx.query(
          'SELECT COALESCE(MAX(display_order), 0) AS m FROM classes',
        );
        final order = (max.first['m'] as num).toInt() + 1;
        final res = await ctx.query(
          'INSERT INTO classes (name, section, level, display_order) '
          'VALUES (?, ?, ?, ?)',
          [trimmed, section.dbValue, niveau.dbValue, order],
        );
        return res.insertId!;
      });
    } on MySqlException catch (e) {
      if (e.errorNumber == _duplicateKeyErrno) throw _duplicateNameError;
      rethrow;
    }
  }

  Future<void> rename(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ClasseException('Le nom de la classe est obligatoire.');
    }
    try {
      await db.execute('UPDATE classes SET name = ? WHERE id = ?', [
        trimmed,
        id,
      ]);
    } on MySqlException catch (e) {
      if (e.errorNumber == _duplicateKeyErrno) throw _duplicateNameError;
      rethrow;
    }
  }

  /// New relative order for [classeIds], top to bottom (1, 2, 3…) — used
  /// when the Direction reorders the list.
  Future<void> reorder(List<int> classeIds) => db.transaction((ctx) async {
    for (var i = 0; i < classeIds.length; i++) {
      await ctx.query('UPDATE classes SET display_order = ? WHERE id = ?', [
        i + 1,
        classeIds[i],
      ]);
    }
  });

  /// Refused if any student row, any year — even a cancelled one, kept for
  /// history — still points to this classe: the foreign key enforces it, so
  /// this never silently orphans data.
  Future<void> delete(int id) async {
    try {
      await db.execute('DELETE FROM classes WHERE id = ?', [id]);
    } on MySqlException catch (e) {
      if (e.errorNumber == 1451) {
        throw ClasseException(
          "Impossible de supprimer : des élèves (actuels ou passés) sont "
          'encore rattachés à cette classe.',
        );
      }
      rethrow;
    }
  }
}
