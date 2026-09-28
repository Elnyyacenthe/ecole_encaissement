import 'classe.dart';

enum Poste {
  inscription,
  tranche1,
  tranche2,
  tranche3;

  String get dbValue => switch (this) {
    Poste.inscription => 'INSCRIPTION',
    Poste.tranche1 => 'TRANCHE1',
    Poste.tranche2 => 'TRANCHE2',
    Poste.tranche3 => 'TRANCHE3',
  };

  static Poste fromDb(String value) =>
      Poste.values.firstWhere((p) => p.dbValue == value);

  String get labelFr => switch (this) {
    Poste.inscription => 'Inscription',
    Poste.tranche1 => '1ère tranche',
    Poste.tranche2 => '2ème tranche',
    Poste.tranche3 => '3ème tranche',
  };

  String get labelEn => switch (this) {
    Poste.inscription => 'Registration',
    Poste.tranche1 => '1st installment',
    Poste.tranche2 => '2nd installment',
    Poste.tranche3 => '3rd installment',
  };
}

class Tariff {
  final int id;
  final int schoolYearId;
  final Niveau niveau;
  final Poste poste;
  final int montant;
  final DateTime? dateLimite;

  const Tariff({
    required this.id,
    required this.schoolYearId,
    required this.niveau,
    required this.poste,
    required this.montant,
    this.dateLimite,
  });

  factory Tariff.fromRow(Map<String, dynamic> row) => Tariff(
    id: row['id'] as int,
    schoolYearId: row['school_year_id'] as int,
    niveau: Niveau.fromDb(row['niveau'] as String),
    poste: Poste.fromDb(row['poste'] as String),
    montant: row['montant'] as int,
    dateLimite: row['date_limite'] as DateTime?,
  );

  /// Default tariffs from the COSBIMP fee schedule, seeded for every new
  /// school year. Montants are editable afterwards via the Tarifs screen —
  /// in particular the Primaire inscription fee (17 500 FCFA) is unconfirmed
  /// by the school and must remain editable.
  static const List<
    ({Niveau niveau, Poste poste, int montant, int? dueMonth, int? dueDay})
  >
  seedData = [
    (
      niveau: Niveau.primaire,
      poste: Poste.inscription,
      montant: 17500,
      dueMonth: null,
      dueDay: null,
    ),
    (
      niveau: Niveau.maternelle,
      poste: Poste.inscription,
      montant: 34000,
      dueMonth: null,
      dueDay: null,
    ),
    (
      niveau: Niveau.primaire,
      poste: Poste.tranche1,
      montant: 40000,
      dueMonth: 9,
      dueDay: 30,
    ),
    (
      niveau: Niveau.maternelle,
      poste: Poste.tranche1,
      montant: 40000,
      dueMonth: 9,
      dueDay: 30,
    ),
    (
      niveau: Niveau.primaire,
      poste: Poste.tranche2,
      montant: 40000,
      dueMonth: 11,
      dueDay: 30,
    ),
    (
      niveau: Niveau.maternelle,
      poste: Poste.tranche2,
      montant: 40000,
      dueMonth: 11,
      dueDay: 30,
    ),
    (
      niveau: Niveau.primaire,
      poste: Poste.tranche3,
      montant: 20000,
      dueMonth: 1,
      dueDay: 31,
    ),
    (
      niveau: Niveau.maternelle,
      poste: Poste.tranche3,
      montant: 20000,
      dueMonth: 1,
      dueDay: 31,
    ),
  ];
}
