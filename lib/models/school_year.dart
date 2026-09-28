class SchoolYear {
  final int id;
  final String label; // e.g. "2026-2027"
  final bool isActive;

  const SchoolYear({
    required this.id,
    required this.label,
    required this.isActive,
  });

  /// Last two digits of the starting year, used in the matricule format.
  String get yearSuffix => label.substring(2, 4);

  factory SchoolYear.fromRow(Map<String, dynamic> row) => SchoolYear(
    id: row['id'] as int,
    label: row['label'] as String,
    isActive: (row['is_active'] as int) == 1,
  );
}
