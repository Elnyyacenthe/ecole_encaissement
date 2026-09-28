import '../core/db/mysql_connection_service.dart';
import '../models/backup_entry.dart';
import 'settings_repository.dart';

/// Reads the backup journal written by Sauvegarde.ps1 and the backup settings.
class BackupRepository {
  static const copyDirKey = 'backup_copy_dir';

  final MySqlConnectionService db;
  final SettingsRepository settings;
  BackupRepository(this.db, this.settings);

  Future<List<BackupEntry>> recent({int limit = 12}) async {
    final rows = await db.select(
      'SELECT id, created_at, file_name, size_bytes, status, message, copied_to, source '
      'FROM backup_log ORDER BY id DESC LIMIT $limit',
    );
    return rows.map(BackupEntry.fromRow).toList();
  }

  /// Hours since the last successful backup (server clock), or null if none.
  Future<int?> hoursSinceLastSuccess() async {
    final rows = await db.select(
      "SELECT TIMESTAMPDIFF(HOUR, MAX(created_at), NOW()) AS h FROM backup_log WHERE status = 'OK'",
    );
    final h = rows.first['h'];
    return h == null ? null : (h as num).toInt();
  }

  Future<String?> copyDir() => settings.getText(copyDirKey);
  Future<void> setCopyDir(String? path) => settings.setText(copyDirKey, path);
}
