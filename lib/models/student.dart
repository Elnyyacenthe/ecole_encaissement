import 'cancellation.dart';

class Student {
  final int id;
  final String matricule;
  final String fullName;
  final int classeId;
  final int schoolYearId;
  final DateTime dateInscription;
  final Cancellation? cancellation;

  const Student({
    required this.id,
    required this.matricule,
    required this.fullName,
    required this.classeId,
    required this.schoolYearId,
    required this.dateInscription,
    this.cancellation,
  });

  bool get isCancelled => cancellation != null;

  factory Student.fromRow(Map<String, dynamic> row) => Student(
    id: row['id'] as int,
    matricule: row['matricule'] as String,
    fullName: row['full_name'] as String,
    classeId: row['classe_id'] as int,
    schoolYearId: row['school_year_id'] as int,
    dateInscription: row['date_inscription'] as DateTime,
    cancellation: Cancellation.fromRow(row),
  );
}

/// A student row joined with its classe and school year, as returned by
/// list/search queries so the UI never has to do a second lookup.
class StudentWithClasse {
  final Student student;
  final String classeName;
  final String section; // DB enum value: FRANCOPHONE / ANGLOPHONE
  final String niveau; // DB enum value: MATERNELLE / PRIMAIRE
  final String schoolYearLabel;

  const StudentWithClasse({
    required this.student,
    required this.classeName,
    required this.section,
    required this.niveau,
    required this.schoolYearLabel,
  });

  factory StudentWithClasse.fromRow(Map<String, dynamic> row) =>
      StudentWithClasse(
        student: Student.fromRow(row),
        classeName: row['classe_name'] as String,
        section: row['section'] as String,
        niveau: row['level'] as String,
        schoolYearLabel: row['school_year_label'] as String,
      );
}
