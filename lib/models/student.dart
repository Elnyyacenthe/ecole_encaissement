import 'cancellation.dart';

class Student {
  final int id;
  final String matricule;
  final String fullName;
  final int classeId;
  final int schoolYearId;
  final DateTime dateInscription;
  final Cancellation? cancellation;

  // État civil et informations parentales — reprises de la fiche
  // d'inscription papier ; tous facultatifs (une fiche peut être créée sans
  // les avoir sous la main et complétée plus tard).
  final DateTime? dateNaissance;
  final String? lieuNaissance;
  final String? nomPere;
  final String? professionPere;
  final String? nomMere;
  final String? professionMere;
  final String? adresseParents;
  final String? contactUrgence1;
  final String? contactUrgence2;

  /// False for a row created in bulk by the Promotion tool: the school
  /// doesn't yet know for certain that this student is actually coming
  /// back, so it stays out of the unpaid report until either the first
  /// real payment confirms them, or a staff member confirms manually.
  final bool confirme;

  const Student({
    required this.id,
    required this.matricule,
    required this.fullName,
    required this.classeId,
    required this.schoolYearId,
    required this.dateInscription,
    this.cancellation,
    this.dateNaissance,
    this.lieuNaissance,
    this.nomPere,
    this.professionPere,
    this.nomMere,
    this.professionMere,
    this.adresseParents,
    this.contactUrgence1,
    this.contactUrgence2,
    this.confirme = true,
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
    dateNaissance: row['date_naissance'] as DateTime?,
    lieuNaissance: row['lieu_naissance'] as String?,
    nomPere: row['nom_pere'] as String?,
    professionPere: row['profession_pere'] as String?,
    nomMere: row['nom_mere'] as String?,
    professionMere: row['profession_mere'] as String?,
    adresseParents: row['adresse_parents'] as String?,
    contactUrgence1: row['contact_urgence_1'] as String?,
    contactUrgence2: row['contact_urgence_2'] as String?,
    confirme: (row['confirme'] as int? ?? 1) == 1,
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
