import '../core/db/mysql_connection_service.dart';
import '../models/tariff.dart';

class TariffsRepository {
  final MySqlConnectionService db;
  TariffsRepository(this.db);

  Future<List<Tariff>> forYear(int schoolYearId) async {
    final rows = await db.select(
      'SELECT id, school_year_id, niveau, poste, montant, date_limite FROM tariffs '
      "WHERE school_year_id = ? ORDER BY niveau DESC, FIELD(poste,'INSCRIPTION','TRANCHE1','TRANCHE2','TRANCHE3')",
      [schoolYearId],
    );
    return rows.map(Tariff.fromRow).toList();
  }

  Future<void> update({
    required int id,
    required int montant,
    required DateTime? dateLimite,
  }) async {
    await db.execute(
      'UPDATE tariffs SET montant = ?, date_limite = ? WHERE id = ?',
      [montant, dateLimite == null ? null : toDbDate(dateLimite), id],
    );
  }
}
