import '../../models/classe.dart';
import '../../models/tariff.dart';
import '../../repositories/users_repository.dart';
import 'mysql_connection_service.dart';
import 'sequence_service.dart';

/// Last invoice number already used on the paper receipts; the first invoice
/// issued by the app is this value + 1. Only applied when the counter does
/// not exist yet.
const int kInvoiceSeed = 29993;

const List<String> _schemaStatements = [
  '''
CREATE TABLE IF NOT EXISTS school_years (
  id INT AUTO_INCREMENT PRIMARY KEY,
  label VARCHAR(9) NOT NULL UNIQUE,
  is_active TINYINT(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''',
  '''
CREATE TABLE IF NOT EXISTS classes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  section ENUM('FRANCOPHONE','ANGLOPHONE') NOT NULL,
  level ENUM('MATERNELLE','PRIMAIRE') NOT NULL,
  display_order INT NOT NULL,
  UNIQUE KEY uq_classes_section_name (section, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''',
  '''
CREATE TABLE IF NOT EXISTS students (
  id INT AUTO_INCREMENT PRIMARY KEY,
  matricule VARCHAR(12) NOT NULL UNIQUE,
  full_name VARCHAR(150) NOT NULL,
  classe_id INT NOT NULL,
  school_year_id INT NOT NULL,
  date_inscription DATE NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  annule TINYINT(1) NOT NULL DEFAULT 0,
  annule_par VARCHAR(100) NULL,
  annule_le DATETIME NULL,
  motif_annulation VARCHAR(255) NULL,
  full_name_active VARCHAR(150) GENERATED ALWAYS AS (IF(annule = 0, full_name, NULL)) STORED,
  CONSTRAINT fk_students_classe FOREIGN KEY (classe_id) REFERENCES classes(id),
  CONSTRAINT fk_students_year FOREIGN KEY (school_year_id) REFERENCES school_years(id),
  INDEX idx_students_classe (classe_id),
  INDEX idx_students_name (full_name),
  UNIQUE KEY uq_students_name_classe_year (school_year_id, classe_id, full_name_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''',
  '''
CREATE TABLE IF NOT EXISTS tariffs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  school_year_id INT NOT NULL,
  niveau ENUM('MATERNELLE','PRIMAIRE') NOT NULL,
  poste ENUM('INSCRIPTION','TRANCHE1','TRANCHE2','TRANCHE3') NOT NULL,
  montant INT NOT NULL,
  date_limite DATE NULL,
  CONSTRAINT fk_tariffs_year FOREIGN KEY (school_year_id) REFERENCES school_years(id),
  UNIQUE KEY uq_tariff (school_year_id, niveau, poste)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''',
  '''
CREATE TABLE IF NOT EXISTS payments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  invoice_number INT NOT NULL,
  student_id INT NOT NULL,
  poste ENUM('INSCRIPTION','TRANCHE1','TRANCHE2','TRANCHE3') NOT NULL,
  montant_paye INT NOT NULL,
  date_paiement DATE NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  operateur VARCHAR(100) NOT NULL,
  annule TINYINT(1) NOT NULL DEFAULT 0,
  annule_par VARCHAR(100) NULL,
  annule_le DATETIME NULL,
  motif_annulation VARCHAR(255) NULL,
  CONSTRAINT fk_payments_student FOREIGN KEY (student_id) REFERENCES students(id),
  UNIQUE KEY uq_payments_invoice_poste (invoice_number, poste),
  INDEX idx_payments_student (student_id),
  INDEX idx_payments_date (date_paiement)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''',
  '''
CREATE TABLE IF NOT EXISTS app_settings (
  setting_key VARCHAR(50) NOT NULL PRIMARY KEY,
  setting_value LONGBLOB NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''',
  '''
CREATE TABLE IF NOT EXISTS backup_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  file_name VARCHAR(255) NOT NULL,
  size_bytes BIGINT NOT NULL DEFAULT 0,
  status ENUM('OK','ERREUR') NOT NULL,
  message VARCHAR(500) NULL,
  copied_to VARCHAR(500) NULL,
  source VARCHAR(30) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''',
  '''
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) NOT NULL UNIQUE,
  full_name VARCHAR(100) NOT NULL,
  role ENUM('SUPER_ADMIN','ADMIN','CAISSIER') NOT NULL,
  password_hash CHAR(64) NOT NULL,
  salt CHAR(32) NOT NULL,
  iterations INT NOT NULL,
  must_change_password TINYINT(1) NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''',
  '''
CREATE TABLE IF NOT EXISTS counters (
  counter_key VARCHAR(40) NOT NULL PRIMARY KEY,
  current_value INT NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''',
];

/// Inserts the default fee schedule for a school year. Idempotent
/// (INSERT IGNORE on the unique key), so existing edited amounts are kept.
/// [startYear] is the first calendar year of the school year (2026 for
/// "2026-2027"); the 3rd installment falls in the following January.
Future<void> seedTariffsForYear(
  MySqlConnectionService db, {
  required int schoolYearId,
  required int startYear,
}) async {
  for (final t in Tariff.seedData) {
    final due = t.dueMonth == null
        ? null
        : DateTime.utc(
            t.dueMonth! < 8 ? startYear + 1 : startYear,
            t.dueMonth!,
            t.dueDay!,
          );
    await db.execute(
      'INSERT IGNORE INTO tariffs (school_year_id, niveau, poste, montant, date_limite) '
      'VALUES (?, ?, ?, ?, ?)',
      [schoolYearId, t.niveau.dbValue, t.poste.dbValue, t.montant, due],
    );
  }
}

/// Adds [column] to [table] if it is missing (existing installs created
/// before that column existed). No-op, not a crash, if it already exists.
Future<void> _ensureColumn(
  MySqlConnectionService db,
  String table,
  String column,
  String definition,
) async {
  final exists = await db.select(
    'SELECT 1 FROM information_schema.columns WHERE table_schema = DATABASE() '
    'AND table_name = ? AND column_name = ?',
    [table, column],
  );
  if (exists.isEmpty) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}

/// Every table with a "cancel, never delete" record (students, payments)
/// gets the same four audit columns.
Future<void> _ensureCancellationColumns(
  MySqlConnectionService db,
  String table,
) async {
  await _ensureColumn(db, table, 'annule', 'TINYINT(1) NOT NULL DEFAULT 0');
  await _ensureColumn(db, table, 'annule_par', 'VARCHAR(100) NULL');
  await _ensureColumn(db, table, 'annule_le', 'DATETIME NULL');
  await _ensureColumn(db, table, 'motif_annulation', 'VARCHAR(255) NULL');
}

/// Creates missing tables and seeds reference data. Safe to run on every
/// startup and from several PCs at once (every statement is idempotent).
Future<void> bootstrapDatabase(MySqlConnectionService db) async {
  for (final sql in _schemaStatements) {
    await db.execute(sql);
  }
  await _ensureCancellationColumns(db, 'students');
  await _ensureCancellationColumns(db, 'payments');

  // A deposit spread over several postes is several rows sharing one invoice
  // number, so the invoice number can no longer be unique on its own.
  final oldUnique = await db.select(
    'SELECT 1 FROM information_schema.statistics WHERE table_schema = DATABASE() '
    "AND table_name = 'payments' AND index_name = 'invoice_number'",
  );
  if (oldUnique.isNotEmpty) {
    await db.execute(
      'ALTER TABLE payments DROP INDEX invoice_number, '
      'ADD UNIQUE KEY uq_payments_invoice_poste (invoice_number, poste)',
    );
  }

  // Existing installs: add the "no two identical names in the same class and
  // year" rule, keyed on a generated column that goes NULL once a student is
  // cancelled — so a cancelled registration frees its name for reuse instead
  // of blocking it forever. Skipped (not crashed) if it cannot be applied
  // (e.g. genuine duplicates already in the data); the school clears those
  // by hand and it applies on a later startup.
  await _ensureColumn(
    db,
    'students',
    'full_name_active',
    'VARCHAR(150) GENERATED ALWAYS AS (IF(annule = 0, full_name, NULL)) STORED',
  );
  final uniqueCols = await db.select(
    'SELECT GROUP_CONCAT(column_name ORDER BY seq_in_index) AS cols '
    'FROM information_schema.statistics WHERE table_schema = DATABASE() '
    "AND table_name = 'students' AND index_name = 'uq_students_name_classe_year' "
    'GROUP BY index_name',
  );
  final currentCols = uniqueCols.isEmpty
      ? null
      : uniqueCols.first['cols'] as String?;
  if (currentCols == null || !currentCols.contains('full_name_active')) {
    try {
      if (currentCols != null) {
        await db.execute(
          'ALTER TABLE students DROP INDEX uq_students_name_classe_year',
        );
      }
      await db.execute(
        'ALTER TABLE students ADD UNIQUE KEY uq_students_name_classe_year '
        '(school_year_id, classe_id, full_name_active)',
      );
    } catch (_) {
      // Likely existing duplicates; leave it for the school to clean up.
    }
  }

  var order = 0;
  for (final c in Classe.seedData) {
    order++;
    await db.execute(
      'INSERT IGNORE INTO classes (name, section, level, display_order) VALUES (?, ?, ?, ?)',
      [c.name, c.section.dbValue, c.niveau.dbValue, order],
    );
  }

  await db.execute(
    'INSERT IGNORE INTO counters (counter_key, current_value) VALUES (?, ?)',
    [SequenceService.invoiceKey, kInvoiceSeed],
  );

  // Every change to shared data bumps a version number, which the PCs poll
  // to refresh their screens (see dataSyncProvider). Done by triggers so no
  // write path can forget it. Without trigger support the app still works,
  // it just does not refresh other PCs' changes automatically.
  await db.execute(
    'INSERT IGNORE INTO counters (counter_key, current_value) VALUES (?, 0)',
    [SequenceService.dataVersionKey],
  );
  for (final table in const [
    'students',
    'payments',
    'tariffs',
    'school_years',
    'app_settings',
    'users',
    'backup_log',
  ]) {
    for (final (suffix, event) in const [
      ('ai', 'INSERT'),
      ('au', 'UPDATE'),
      ('ad', 'DELETE'),
    ]) {
      try {
        await db.execute(
          'CREATE TRIGGER IF NOT EXISTS trg_${table}_$suffix AFTER $event ON $table '
          'FOR EACH ROW UPDATE counters SET current_value = current_value + 1 '
          "WHERE counter_key = '${SequenceService.dataVersionKey}'",
        );
      } catch (_) {
        // Server without trigger support: keep going.
      }
    }
  }

  // Installations created before the Direction role existed: widen the column.
  final roleType = await db.select(
    "SELECT column_type FROM information_schema.columns WHERE table_schema = DATABASE() "
    "AND table_name = 'users' AND column_name = 'role'",
  );
  if (roleType.isNotEmpty &&
      !roleType.first['column_type'].toString().contains('SUPER_ADMIN')) {
    await db.execute(
      "ALTER TABLE users MODIFY role ENUM('SUPER_ADMIN','ADMIN','CAISSIER') NOT NULL",
    );
  }
  await UsersRepository.ensureDefaultAccounts(db);

  final anyYear = await db.select('SELECT id FROM school_years LIMIT 1');
  if (anyYear.isEmpty) {
    final now = DateTime.now();
    final startYear = now.month >= 8 ? now.year : now.year - 1;
    await db.execute(
      'INSERT IGNORE INTO school_years (label, is_active) VALUES (?, 1)',
      ['$startYear-${startYear + 1}'],
    );
  }

  // Completes the fee schedule of the active year if a previous start was
  // interrupted; existing (possibly edited) amounts are never overwritten.
  final active = await db.select(
    'SELECT id, label FROM school_years WHERE is_active = 1 LIMIT 1',
  );
  if (active.isNotEmpty) {
    final id = active.first['id'] as int;
    final count = await db.select(
      'SELECT COUNT(*) AS n FROM tariffs WHERE school_year_id = ?',
      [id],
    );
    if ((count.first['n'] as num).toInt() < Tariff.seedData.length) {
      await seedTariffsForYear(
        db,
        schoolYearId: id,
        startYear: int.parse(active.first['label'].toString().substring(0, 4)),
      );
    }
  }
}
