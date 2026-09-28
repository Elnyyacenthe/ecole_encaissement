import 'dart:async';
import 'dart:io';

import 'package:mysql1/mysql1.dart';

import 'db_config.dart';
import 'db_settings_repository.dart';
import 'mysql_connection_service.dart';

class DbConnectionException implements Exception {
  final String message;
  DbConnectionException(this.message);
  @override
  String toString() => message;
}

/// Connects to the school's MySQL server without any user input.
///
/// Hosts are tried in this order, stopping at the first that accepts the
/// credentials: the host pinned by settings / config file / last success,
/// this PC (127.0.0.1), then every machine answering on the MySQL port in
/// this PC's local subnets.
class DbAutoConnector {
  final MySqlConnectionService db;
  final DbSettingsRepository settings;
  final void Function(String status) onStatus;

  DbAutoConnector({
    required this.db,
    required this.settings,
    required this.onStatus,
  });

  Future<DbConfig> connect() async {
    final base = await settings.load();
    final tried = <String>[];
    String? authFailure;

    Future<DbConfig?> attempt(String host) async {
      if (tried.contains(host)) return null;
      tried.add(host);
      final config = base.copyWith(host: host);
      try {
        await db.probe(config);
        return config;
      } on MySqlException catch (e) {
        // The server answered but refused us: remember why, keep looking.
        authFailure ??=
            'Serveur trouvé à $host mais connexion refusée '
            '(${e.message}). Exécutez database/setup_mysql.sql sur le serveur.';
      } catch (_) {
        // Unreachable or not a MySQL server.
      }
      return null;
    }

    DbConfig? found;
    if (base.hasHost) {
      onStatus('Connexion au serveur ${base.host}…');
      found = await attempt(base.host);
    }
    if (found == null) {
      onStatus('Connexion au serveur local…');
      found = await attempt('127.0.0.1');
    }
    if (found == null) {
      onStatus('Recherche du serveur sur le réseau…');
      for (final host in await scanLan(base.port)) {
        found = await attempt(host);
        if (found != null) break;
      }
    }

    if (found == null) {
      throw DbConnectionException(
        authFailure ??
            'Aucun serveur MySQL trouvé sur le réseau. Vérifiez que le serveur '
                "est allumé, que MySQL est démarré et que ce poste est sur le même réseau.",
      );
    }

    onStatus('Préparation de la base de données…');
    await db.ensureDatabase(found);
    await db.connect(found);
    if (found.host != base.host) await settings.saveHost(found.host);
    return found;
  }

  /// Hosts of this PC's private /24 subnets that accept a TCP connection on [port].
  Future<List<String>> scanLan(int port) async {
    final prefixes = <String>{};
    final own = <String>{};
    for (final ni in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final a in ni.addresses) {
        if (a.isLoopback || a.isLinkLocal) continue;
        own.add(a.address);
        prefixes.add(a.address.split('.').take(3).join('.'));
      }
    }
    final candidates = [
      for (final p in prefixes)
        for (var i = 1; i <= 254; i++) '$p.$i',
    ];

    final found = <String>[];
    Future<void> check(String host) async {
      try {
        final s = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 400),
        );
        s.destroy();
        found.add(host);
      } catch (_) {}
    }

    const batch = 128;
    for (var i = 0; i < candidates.length; i += batch) {
      await Future.wait(candidates.skip(i).take(batch).map(check));
    }
    // This PC's own addresses last: it was already tried through 127.0.0.1.
    found.sort(
      (a, b) => own.contains(a) == own.contains(b)
          ? a.compareTo(b)
          : own.contains(a)
          ? 1
          : -1,
    );
    return found;
  }
}
