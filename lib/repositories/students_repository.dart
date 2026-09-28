import 'package:mysql1/mysql1.dart';

import '../core/db/mysql_connection_service.dart';
import '../core/db/sequence_service.dart';
import '../models/student.dart';

const _selectStudent = '''
SELECT s.id, s.matricule, s.full_name, s.classe_id, s.school_year_id, s.date_inscription,
       s.annule, s.annule_par, s.annule_le, s.motif_annulation,
       c.name AS classe_name, c.section, c.level, y.label AS school_year_label
FROM students s
JOIN classes c ON c.id = s.classe_id
JOIN school_years y ON y.id = s.school_year_id
''';

class StudentException implements Exception {
  final String message;
  StudentException(this.message);
  @override
  String toString() => message;
}

/// Trims and collapses internal whitespace, so "Jean  Dupont" and "Jean
/// Dupont" are treated as the same name (the DB comparison is already
/// case-insensitive via the table's collation).
String normalizeName(String fullName) =>
    fullName.trim().replaceAll(RegExp(r'\s+'), ' ');

const _duplicateKeyErrno = 1062;

class StudentsRepository {
  final MySqlConnectionService db;
  StudentsRepository(this.db);

  Future<List<StudentWithClasse>> search({
    String query = '',
    int? classeId,
    int? schoolYearId,
    int limit = 500,
    bool includeCancelled = false,
  }) async {
    final where = <String>[];
    final params = <Object?>[];
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add('(s.full_name LIKE ? OR s.matricule LIKE ?)');
      params
        ..add('%$q%')
        ..add('%$q%');
    }
    if (classeId != null) {
      where.add('s.classe_id = ?');
      params.add(classeId);
    }
    if (schoolYearId != null) {
      where.add('s.school_year_id = ?');
      params.add(schoolYearId);
    }
    if (!includeCancelled) {
      where.add('s.annule = 0');
    }
    final sql =
        '$_selectStudent'
        '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}'
        'ORDER BY s.matricule DESC LIMIT $limit';
    final rows = await db.select(sql, params);
    return rows.map(StudentWithClasse.fromRow).toList();
  }

  Future<StudentWithClasse?> getById(int id) async {
    final rows = await db.select('$_selectStudent WHERE s.id = ?', [id]);
    return rows.isEmpty ? null : StudentWithClasse.fromRow(rows.first);
  }

  /// Exact (normalized, case-insensitive) name matches for this school year,
  /// wherever their class — used to warn about a possible duplicate before
  /// saving. [excludeId] leaves out the student being edited.
  Future<List<StudentWithClasse>> findByExactName({
    required String fullName,
    required int schoolYearId,
    int? excludeId,
  }) async {
    final name = normalizeName(fullName);
    if (name.isEmpty) return const [];
    final sql =
        '$_selectStudent'
        'WHERE s.school_year_id = ? AND s.full_name = ? AND s.annule = 0 '
        '${excludeId == null ? '' : 'AND s.id <> ? '}'
        'ORDER BY s.matricule';
    final rows = await db.select(sql, [schoolYearId, name, ?excludeId]);
    return rows.map(StudentWithClasse.fromRow).toList();
  }

  static final _duplicateNameError = StudentException(
    'Un élève portant exactement ce nom existe déjà dans cette classe pour '
    "cette année scolaire. Vérifiez qu'il ne s'agit pas d'un double enregistrement.",
  );

  /// Creates a student and returns its id. The matricule is generated inside
  /// the same transaction as the INSERT (see [SequenceService]). Rejected if
  /// the exact same name already exists in the same class and year (a
  /// database constraint, so it also catches two PCs saving at once).
  Future<int> create({
    required String fullName,
    required int classeId,
    required int schoolYearId,
    required DateTime dateInscription,
  }) {
    return db.transaction((ctx) async {
      final years = await ctx.query(
        'SELECT label FROM school_years WHERE id = ?',
        [schoolYearId],
      );
      final label = years.first['label'].toString();
      final matricule = await SequenceService.nextMatricule(ctx, label);
      try {
        final res = await ctx.query(
          'INSERT INTO students (matricule, full_name, classe_id, school_year_id, date_inscription) '
          'VALUES (?, ?, ?, ?, ?)',
          [
            matricule,
            normalizeName(fullName),
            classeId,
            schoolYearId,
            toDbDate(dateInscription),
          ],
        );
        return res.insertId!;
      } on MySqlException catch (e) {
        if (e.errorNumber == _duplicateKeyErrno) throw _duplicateNameError;
        rethrow;
      }
    });
  }

  /// The matricule is never editable. Rejected under the same duplicate rule
  /// as [create].
  Future<void> update({
    required int id,
    required String fullName,
    required int classeId,
    required DateTime dateInscription,
  }) async {
    try {
      await db.execute(
        'UPDATE students SET full_name = ?, classe_id = ?, date_inscription = ? WHERE id = ?',
        [normalizeName(fullName), classeId, toDbDate(dateInscription), id],
      );
    } on MySqlException catch (e) {
      if (e.errorNumber == _duplicateKeyErrno) throw _duplicateNameError;
      rethrow;
    }
  }

  /// Cancels a registration — the row is kept forever (matricule, payments,
  /// history all stay intact), only flagged, so the cancellation itself is
  /// always visible rather than a silent deletion. Existing payments are
  /// untouched; cancel those separately if the money must be reversed too.
  Future<void> cancel({
    required int studentId,
    required String cancelledBy,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw StudentException("Le motif d'annulation est obligatoire.");
    }
    final rows = await db.select(
      'SELECT annule FROM students WHERE id = ?',
      [studentId],
    );
    if (rows.isEmpty) throw StudentException('Élève introuvable.');
    if ((rows.first['annule'] as int) == 1) {
      throw StudentException('Cette inscription est déjà annulée.');
    }
    await db.execute(
      'UPDATE students SET annule = 1, annule_par = ?, annule_le = NOW(), '
      'motif_annulation = ? WHERE id = ?',
      [cancelledBy, reason.trim(), studentId],
    );
  }
}
