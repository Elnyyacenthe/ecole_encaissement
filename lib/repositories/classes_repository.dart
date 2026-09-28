import '../core/db/mysql_connection_service.dart';
import '../models/classe.dart';

class ClassesRepository {
  final MySqlConnectionService db;
  ClassesRepository(this.db);

  Future<List<Classe>> all() async {
    final rows = await db.select(
      'SELECT id, name, section, level, display_order FROM classes ORDER BY display_order',
    );
    return rows.map(Classe.fromRow).toList();
  }
}
