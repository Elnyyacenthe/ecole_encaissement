/// One line of the backup journal (table backup_log).
class BackupEntry {
  final int id;

  /// Server clock; only the calendar fields are meaningful (see formatDateTime).
  final DateTime createdAt;
  final String fileName;
  final int sizeBytes;
  final bool ok;
  final String? message;
  final String? copiedTo;

  /// planifiee, manuelle, rattrapage, avant-restauration.
  final String source;

  const BackupEntry({
    required this.id,
    required this.createdAt,
    required this.fileName,
    required this.sizeBytes,
    required this.ok,
    required this.source,
    this.message,
    this.copiedTo,
  });

  factory BackupEntry.fromRow(Map<String, dynamic> row) => BackupEntry(
    id: row['id'] as int,
    createdAt: row['created_at'] as DateTime,
    fileName: row['file_name'] as String,
    sizeBytes: (row['size_bytes'] as num).toInt(),
    ok: row['status'] == 'OK',
    message: row['message']?.toString(),
    copiedTo: row['copied_to']?.toString(),
    source: row['source'] as String,
  );

  String get sourceLabel => switch (source) {
    'planifiee' => 'Automatique',
    'manuelle' => 'Manuelle',
    'rattrapage' => 'Rattrapage',
    'avant-restauration' => 'Avant restauration',
    _ => source,
  };
}
