import '../core/db/mysql_connection_service.dart';
import '../models/classe.dart';
import '../models/promotion.dart';
import 'classes_repository.dart';
import 'students_repository.dart';

/// Bulk re-enrolment of a whole class list from one school year into the
/// next, instead of recreating every student by hand at the start of each
/// year — see [preview] and [commit].
class PromotionRepository {
  final MySqlConnectionService db;
  final StudentsRepository students;
  final ClassesRepository classes;
  PromotionRepository(this.db, this.students, this.classes);

  /// The classe that naturally follows [current] within the same section
  /// (Maternelle -> Primaire included), or null when [current] is the last
  /// classe of its section — a graduating level with nothing to suggest.
  static Classe? nextClasse(Classe current, List<Classe> all) {
    final sameSection =
        all.where((c) => c.section == current.section).toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final i = sameSection.indexWhere((c) => c.id == current.id);
    if (i < 0 || i + 1 >= sameSection.length) return null;
    return sameSection[i + 1];
  }

  /// Students of [fromYearId] not yet present (by exact name) in
  /// [toYearId], each with the classe they would move into by default.
  Future<List<PromotionCandidate>> preview({
    required int fromYearId,
    required int toYearId,
  }) async {
    final classeList = await classes.all();
    final byId = {for (final c in classeList) c.id: c};

    final rows = await db.select(
      'SELECT id, matricule, full_name, classe_id FROM students '
      'WHERE school_year_id = ? AND annule = 0 ORDER BY full_name',
      [fromYearId],
    );

    final existing = await db.select(
      'SELECT full_name FROM students WHERE school_year_id = ? AND annule = 0',
      [toYearId],
    );
    final existingNames = existing
        .map((r) => (r['full_name'] as String).toUpperCase())
        .toSet();

    return [
      for (final r in rows)
        if (!existingNames.contains((r['full_name'] as String).toUpperCase()))
          _toCandidate(r, byId, classeList),
    ];
  }

  PromotionCandidate _toCandidate(
    Map<String, dynamic> r,
    Map<int, Classe> byId,
    List<Classe> classeList,
  ) {
    final current = byId[r['classe_id'] as int]!;
    final next = nextClasse(current, classeList);
    return PromotionCandidate(
      studentId: r['id'] as int,
      matricule: r['matricule'] as String,
      fullName: r['full_name'] as String,
      currentClasseId: current.id,
      currentClasseName: current.name,
      section: current.section,
      niveau: current.niveau,
      suggestedClasseId: next?.id,
    );
  }

  /// Creates one new student row per selection that has a target classe, in
  /// [toYearId]. Each row is created independently (its own matricule and
  /// duplicate-name check), so one failure never blocks the rest — failures
  /// are reported and the run can simply be repeated for them.
  ///
  /// Rows start unconfirmed (`confirme = 0`): a bulk promotion is a guess at
  /// who is coming back, not a confirmed re-enrolment, so these students
  /// stay out of the unpaid report until their first real payment (or a
  /// manual confirmation) proves they actually returned.
  Future<PromotionResult> commit({
    required int toYearId,
    required List<PromotionSelection> selections,
    required DateTime dateInscription,
  }) async {
    var promoted = 0;
    final failures = <String>[];
    for (final sel in selections) {
      final classeId = sel.targetClasseId;
      if (classeId == null) continue;
      try {
        await students.create(
          fullName: sel.fullName,
          classeId: classeId,
          schoolYearId: toYearId,
          dateInscription: dateInscription,
          confirme: false,
        );
        promoted++;
      } catch (e) {
        failures.add('${sel.fullName} : $e');
      }
    }
    return PromotionResult(promoted: promoted, failures: failures);
  }
}
