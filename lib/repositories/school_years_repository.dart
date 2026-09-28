import '../core/db/db_bootstrap.dart';
import '../core/db/mysql_connection_service.dart';
import '../models/school_year.dart';

class SchoolYearsRepository {
  final MySqlConnectionService db;
  SchoolYearsRepository(this.db);

  Future<List<SchoolYear>> all() async {
    final rows = await db.select(
      'SELECT id, label, is_active FROM school_years ORDER BY label DESC',
    );
    return rows.map(SchoolYear.fromRow).toList();
  }

  Future<SchoolYear?> active() async {
    final rows = await db.select(
      'SELECT id, label, is_active FROM school_years WHERE is_active = 1 LIMIT 1',
    );
    return rows.isEmpty ? null : SchoolYear.fromRow(rows.first);
  }

  /// Creates a school year ("2027-2028") with default tariffs and makes it
  /// the active one.
  Future<void> createAndActivate(String label) async {
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(label);
    if (match == null || int.parse(match[2]!) != int.parse(match[1]!) + 1) {
      throw ArgumentError('Format attendu : 2026-2027');
    }
    await db.execute(
      'INSERT IGNORE INTO school_years (label, is_active) VALUES (?, 0)',
      [label],
    );
    final rows = await db.select(
      'SELECT id FROM school_years WHERE label = ?',
      [label],
    );
    final id = rows.first['id'] as int;
    await seedTariffsForYear(
      db,
      schoolYearId: id,
      startYear: int.parse(match[1]!),
    );
    await setActive(id);
  }

  Future<void> setActive(int id) => db.transaction((ctx) async {
    await ctx.query('UPDATE school_years SET is_active = 0');
    await ctx.query('UPDATE school_years SET is_active = 1 WHERE id = ?', [id]);
  });
}
