import 'dart:typed_data';

import 'package:mysql1/mysql1.dart';

import '../core/db/mysql_connection_service.dart';

class SettingsException implements Exception {
  final String message;
  SettingsException(this.message);
  @override
  String toString() => message;
}

/// School-wide settings stored in the database, so a change made on one PC
/// (e.g. the logo) shows up on every PC and on every printed document.
class SettingsRepository {
  static const _logoKey = 'logo';
  static const maxLogoBytes = 3 * 1024 * 1024;

  static const keySchoolName = 'school_name';
  static const keySchoolBox = 'school_box';
  static const keySchoolPhone = 'school_phone';
  static const keyMatriculePrefix = 'matricule_prefix';
  static const keySetupCompleted = 'setup_completed';

  /// Used whenever a school hasn't set its own matricule prefix yet — keeps
  /// the format ("26MP001") unchanged for installs created before this was
  /// configurable.
  static const defaultMatriculePrefix = 'MP';

  final MySqlConnectionService db;
  SettingsRepository(this.db);

  Future<bool> isSetupCompleted() async =>
      (await getText(keySetupCompleted)) == '1';

  Future<void> markSetupCompleted() => setText(keySetupCompleted, '1');

  Future<String> matriculePrefix() async =>
      (await getText(keyMatriculePrefix)) ?? defaultMatriculePrefix;

  /// A short text setting (e.g. the extra backup folder), or null when unset.
  Future<String?> getText(String key) async {
    final rows = await db.select(
      'SELECT setting_value FROM app_settings WHERE setting_key = ?',
      [key],
    );
    if (rows.isEmpty) return null;
    final value = rows.first['setting_value']?.toString().trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> setText(String key, String? value) async {
    if (value == null || value.trim().isEmpty) {
      await db.execute('DELETE FROM app_settings WHERE setting_key = ?', [key]);
      return;
    }
    await db.execute(
      'INSERT INTO app_settings (setting_key, setting_value) VALUES (?, ?) '
      'ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)',
      [key, value.trim()],
    );
  }

  Future<Uint8List?> loadLogo() async {
    final rows = await db.run(
      (c) => c.query(
        'SELECT setting_value FROM app_settings WHERE setting_key = ?',
        [_logoKey],
      ),
    );
    if (rows.isEmpty) return null;
    final value = rows.first[0];
    if (value is! Blob) return null;
    final bytes = Uint8List.fromList(value.toBytes());
    return bytes.isEmpty ? null : bytes;
  }

  Future<void> saveLogo(Uint8List bytes) async {
    final isPng =
        bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final isJpeg =
        bytes.length > 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
    if (!isPng && !isJpeg) {
      throw SettingsException(
        'Format non pris en charge : choisissez une image PNG ou JPG.',
      );
    }
    if (bytes.length > maxLogoBytes) {
      throw SettingsException('Image trop lourde (3 Mo maximum).');
    }
    await db.run(
      (c) => c.query(
        'INSERT INTO app_settings (setting_key, setting_value) VALUES (?, ?) '
        'ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)',
        [_logoKey, bytes],
      ),
    );
  }
}
