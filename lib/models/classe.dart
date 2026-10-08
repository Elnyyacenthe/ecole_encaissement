enum Section {
  francophone,
  anglophone;

  String get dbValue => name.toUpperCase();

  static Section fromDb(String value) =>
      Section.values.firstWhere((s) => s.dbValue == value);

  String get label => switch (this) {
    Section.francophone => 'Francophone',
    Section.anglophone => 'Anglophone',
  };
}

enum Niveau {
  maternelle,
  primaire;

  String get dbValue => name.toUpperCase();

  static Niveau fromDb(String value) =>
      Niveau.values.firstWhere((n) => n.dbValue == value);

  String get label => switch (this) {
    Niveau.maternelle => 'Maternelle',
    Niveau.primaire => 'Primaire',
  };
}

/// A classe with how many non-cancelled students it has for a given year —
/// shown on the Classes screen.
class ClasseHeadcount {
  final Classe classe;
  final int total;
  const ClasseHeadcount({required this.classe, required this.total});
}

class Classe {
  final int id;
  final String name;
  final Section section;
  final Niveau niveau;
  final int displayOrder;

  const Classe({
    required this.id,
    required this.name,
    required this.section,
    required this.niveau,
    required this.displayOrder,
  });

  factory Classe.fromRow(Map<String, dynamic> row) => Classe(
    id: row['id'] as int,
    name: row['name'] as String,
    section: Section.fromDb(row['section'] as String),
    niveau: Niveau.fromDb(row['level'] as String),
    displayOrder: row['display_order'] as int,
  );

  /// COSBIMP's own 19 classes — offered as an editable starting template by
  /// the first-launch setup assistant, not auto-seeded for every school
  /// anymore (see [bootstrapDatabase]). Classes are otherwise a normal,
  /// per-installation table managed via [ClassesRepository].
  static const List<({String name, Section section, Niveau niveau})>
  seedData = [
    // Francophone — Maternelle
    (
      name: 'Pré-Maternelle',
      section: Section.francophone,
      niveau: Niveau.maternelle,
    ),
    (
      name: 'Petite Section',
      section: Section.francophone,
      niveau: Niveau.maternelle,
    ),
    (
      name: 'Moyenne Section',
      section: Section.francophone,
      niveau: Niveau.maternelle,
    ),
    (
      name: 'Grande Section',
      section: Section.francophone,
      niveau: Niveau.maternelle,
    ),
    // Francophone — Primaire
    (name: 'SIL', section: Section.francophone, niveau: Niveau.primaire),
    (
      name: 'Cours Préparatoire',
      section: Section.francophone,
      niveau: Niveau.primaire,
    ),
    (
      name: 'Cours Élémentaire Un',
      section: Section.francophone,
      niveau: Niveau.primaire,
    ),
    (
      name: 'Cours Élémentaire Deux',
      section: Section.francophone,
      niveau: Niveau.primaire,
    ),
    (
      name: 'Cours Moyen Un',
      section: Section.francophone,
      niveau: Niveau.primaire,
    ),
    (
      name: 'Cours Moyen Deux',
      section: Section.francophone,
      niveau: Niveau.primaire,
    ),
    // Anglophone — Nursery
    (
      name: 'Pre Nursery',
      section: Section.anglophone,
      niveau: Niveau.maternelle,
    ),
    (
      name: 'Nursery One',
      section: Section.anglophone,
      niveau: Niveau.maternelle,
    ),
    (
      name: 'Nursery Two',
      section: Section.anglophone,
      niveau: Niveau.maternelle,
    ),
    // Anglophone — Primary
    (name: 'Class One', section: Section.anglophone, niveau: Niveau.primaire),
    (name: 'Class Two', section: Section.anglophone, niveau: Niveau.primaire),
    (name: 'Class Three', section: Section.anglophone, niveau: Niveau.primaire),
    (name: 'Class Four', section: Section.anglophone, niveau: Niveau.primaire),
    (name: 'Class Five', section: Section.anglophone, niveau: Niveau.primaire),
    (name: 'Class Six', section: Section.anglophone, niveau: Niveau.primaire),
  ];
}
