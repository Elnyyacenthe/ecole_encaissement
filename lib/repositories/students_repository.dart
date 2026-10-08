import 'package:mysql1/mysql1.dart';

import '../core/db/mysql_connection_service.dart';
import '../core/db/sequence_service.dart';
import '../models/student.dart';
import 'settings_repository.dart';

const _selectStudent = '''
SELECT s.id, s.matricule, s.full_name, s.classe_id, s.school_year_id, s.date_inscription,
       s.annule, s.annule_par, s.annule_le, s.motif_annulation,
       s.date_naissance, s.lieu_naissance, s.nom_pere, s.profession_pere,
       s.nom_mere, s.profession_mere, s.adresse_parents,
       s.contact_urgence_1, s.contact_urgence_2, s.confirme,
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
        'ORDER BY c.display_order, s.full_name LIMIT $limit';
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

  /// Exact name matches in a DIFFERENT, non-cancelled year — a soft warning
  /// while registering a brand-new student, in case this is really the same
  /// child and "C'est un ancien élève ?" should have been used instead.
  Future<List<StudentWithClasse>> findByExactNameOtherYears({
    required String fullName,
    required int schoolYearId,
    int? excludeId,
  }) async {
    final name = normalizeName(fullName);
    if (name.isEmpty) return const [];
    final sql =
        '$_selectStudent'
        'WHERE s.full_name = ? AND s.school_year_id <> ? AND s.annule = 0 '
        '${excludeId == null ? '' : 'AND s.id <> ? '}'
        'ORDER BY y.label DESC';
    final rows = await db.select(sql, [name, schoolYearId, ?excludeId]);
    return rows.map(StudentWithClasse.fromRow).toList();
  }

  /// Every row (any year, including cancelled) matching this exact name —
  /// the best-effort "historique des classes par année" shown on the
  /// read-only fiche. Name-matched, not a stable identity: two different
  /// children sharing the exact same name would appear merged here.
  Future<List<StudentWithClasse>> classHistoryFor(String fullName) async {
    final name = normalizeName(fullName);
    if (name.isEmpty) return const [];
    final rows = await db.select(
      '$_selectStudent WHERE s.full_name = ? ORDER BY y.label DESC',
      [name],
    );
    return rows.map(StudentWithClasse.fromRow).toList();
  }

  /// Candidates for the "ancien élève" flow — anyone not properly settled
  /// into the active year yet: a student with no row there at all (left
  /// without being promoted, possibly years ago), or one that Promotion
  /// created there but nobody has confirmed yet ("provisoire"). Either way,
  /// picking one re-enrols on their existing row instead of piling up a
  /// fresh one. Most recent year first, active year's provisional rows last.
  Future<List<StudentWithClasse>> searchFormerStudents({
    required int activeYearId,
    String query = '',
    int limit = 50,
  }) async {
    final q = query.trim();
    final where = <String>[
      's.annule = 0',
      '(s.school_year_id = ? AND s.confirme = 0 '
          'OR (s.school_year_id <> ? AND NOT EXISTS ('
          'SELECT 1 FROM students s2 WHERE s2.school_year_id = ? '
          'AND s2.full_name = s.full_name AND s2.annule = 0)))',
    ];
    final params = <Object?>[activeYearId, activeYearId, activeYearId];
    if (q.isNotEmpty) {
      where.add('(s.full_name LIKE ? OR s.matricule LIKE ?)');
      params
        ..add('%$q%')
        ..add('%$q%');
    }
    final sql =
        '$_selectStudent'
        'WHERE ${where.join(' AND ')} '
        'ORDER BY (s.school_year_id = ?) ASC, y.label DESC, s.full_name '
        'LIMIT $limit';
    params.add(activeYearId);
    final rows = await db.select(sql, params);
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
    DateTime? dateNaissance,
    String? lieuNaissance,
    String? nomPere,
    String? professionPere,
    String? nomMere,
    String? professionMere,
    String? adresseParents,
    String? contactUrgence1,
    String? contactUrgence2,
    /// False for a Promotion-created row: not yet counted in the unpaid
    /// report until confirmed (first payment, or [confirm]).
    bool confirme = true,
  }) {
    return db.transaction((ctx) async {
      final years = await ctx.query(
        'SELECT label FROM school_years WHERE id = ?',
        [schoolYearId],
      );
      final label = years.first['label'].toString();
      final prefixRow = await ctx.query(
        'SELECT setting_value FROM app_settings WHERE setting_key = ?',
        [SettingsRepository.keyMatriculePrefix],
      );
      final prefix = prefixRow.isEmpty
          ? SettingsRepository.defaultMatriculePrefix
          : prefixRow.first['setting_value'].toString();
      final matricule = await SequenceService.nextMatricule(
        ctx,
        label,
        prefix: prefix,
      );
      try {
        final res = await ctx.query(
          'INSERT INTO students (matricule, full_name, classe_id, school_year_id, '
          'date_inscription, date_naissance, lieu_naissance, nom_pere, '
          'profession_pere, nom_mere, profession_mere, adresse_parents, '
          'contact_urgence_1, contact_urgence_2, confirme) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            matricule,
            normalizeName(fullName),
            classeId,
            schoolYearId,
            toDbDate(dateInscription),
            dateNaissance == null ? null : toDbDate(dateNaissance),
            lieuNaissance?.trim(),
            nomPere?.trim(),
            professionPere?.trim(),
            nomMere?.trim(),
            professionMere?.trim(),
            adresseParents?.trim(),
            contactUrgence1?.trim(),
            contactUrgence2?.trim(),
            confirme ? 1 : 0,
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
    DateTime? dateNaissance,
    String? lieuNaissance,
    String? nomPere,
    String? professionPere,
    String? nomMere,
    String? professionMere,
    String? adresseParents,
    String? contactUrgence1,
    String? contactUrgence2,
  }) async {
    try {
      await db.execute(
        'UPDATE students SET full_name = ?, classe_id = ?, date_inscription = ?, '
        'date_naissance = ?, lieu_naissance = ?, nom_pere = ?, profession_pere = ?, '
        'nom_mere = ?, profession_mere = ?, adresse_parents = ?, '
        'contact_urgence_1 = ?, contact_urgence_2 = ? WHERE id = ?',
        [
          normalizeName(fullName),
          classeId,
          toDbDate(dateInscription),
          dateNaissance == null ? null : toDbDate(dateNaissance),
          lieuNaissance?.trim(),
          nomPere?.trim(),
          professionPere?.trim(),
          nomMere?.trim(),
          professionMere?.trim(),
          adresseParents?.trim(),
          contactUrgence1?.trim(),
          contactUrgence2?.trim(),
          id,
        ],
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

  /// Re-enrols a former student (found via [searchFormerStudents]) for
  /// [schoolYearId] by updating their existing row in place, instead of
  /// creating a new one — so the matricule stays exactly what it always
  /// was, even after several years away, and the row keeps its full
  /// original payment history (tied to the same student id).
  Future<void> reactivate({
    required int studentId,
    required int classeId,
    required int schoolYearId,
    required DateTime dateInscription,
    required String fullName,
    DateTime? dateNaissance,
    String? lieuNaissance,
    String? nomPere,
    String? professionPere,
    String? nomMere,
    String? professionMere,
    String? adresseParents,
    String? contactUrgence1,
    String? contactUrgence2,
  }) async {
    final rows = await db.select('SELECT annule FROM students WHERE id = ?', [
      studentId,
    ]);
    if (rows.isEmpty) throw StudentException('Élève introuvable.');
    if ((rows.first['annule'] as int) == 1) {
      throw StudentException(
        'Cette fiche est annulée ; elle ne peut pas être réactivée ainsi.',
      );
    }
    try {
      await db.execute(
        'UPDATE students SET full_name = ?, classe_id = ?, school_year_id = ?, '
        'date_inscription = ?, date_naissance = ?, lieu_naissance = ?, '
        'nom_pere = ?, profession_pere = ?, nom_mere = ?, profession_mere = ?, '
        'adresse_parents = ?, contact_urgence_1 = ?, contact_urgence_2 = ?, '
        'confirme = 1 '
        'WHERE id = ?',
        [
          normalizeName(fullName),
          classeId,
          schoolYearId,
          toDbDate(dateInscription),
          dateNaissance == null ? null : toDbDate(dateNaissance),
          lieuNaissance?.trim(),
          nomPere?.trim(),
          professionPere?.trim(),
          nomMere?.trim(),
          professionMere?.trim(),
          adresseParents?.trim(),
          contactUrgence1?.trim(),
          contactUrgence2?.trim(),
          studentId,
        ],
      );
    } on MySqlException catch (e) {
      if (e.errorNumber == _duplicateKeyErrno) throw _duplicateNameError;
      rethrow;
    }
  }

  /// Marks a provisionally-promoted student as confirmed — for a family
  /// that confirms in person before actually paying anything. Recording a
  /// payment for the student does this automatically ([PaymentsRepository]);
  /// this is only needed as a manual step ahead of that.
  Future<void> confirm(int studentId) =>
      db.execute('UPDATE students SET confirme = 1 WHERE id = ?', [studentId]);
}
