import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'db_config.dart';

/// Connection settings for this PC, resolved in this order (last wins):
/// built-in defaults < saved preferences (incl. the last server found) <
/// optional `cosbimp_db.json` next to the executable.
///
/// Nothing needs to be configured for a standard installation: the app
/// finds the MySQL server on the LAN by itself. The file lets an
/// administrator pin a host/user/password when auto-detection is not wanted.
class DbSettingsRepository {
  static const _keyHost = 'db_host';
  static const fileName = 'cosbimp_db.json';

  Future<DbConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    var config = DbConfig.defaults.copyWith(host: prefs.getString(_keyHost));
    final fromFile = _readFile();
    if (fromFile != null) {
      config = config.copyWith(
        host: fromFile['host'] as String?,
        port: (fromFile['port'] as num?)?.toInt(),
        user: fromFile['user'] as String?,
        password: fromFile['password'] as String?,
        dbName: fromFile['db'] as String?,
      );
    }
    return config;
  }

  /// True when an administrator's config file pins the connection settings.
  bool get hasConfigFile => _readFile() != null;

  Map<String, dynamic>? _readFile() {
    final candidates = [
      File(
        '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}$fileName',
      ),
      File(fileName),
    ];
    for (final f in candidates) {
      try {
        if (f.existsSync()) {
          return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        }
      } catch (_) {
        // A malformed file is ignored rather than blocking startup.
      }
    }
    return null;
  }

  Future<void> saveHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHost, host);
  }
}
