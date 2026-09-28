import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:mysql1/mysql1.dart';
import 'package:synchronized/synchronized.dart';

import 'db_config.dart';

typedef Row = Map<String, dynamic>;

/// `mysql1` only accepts UTC DateTime parameters. For DATE columns, keep the
/// calendar day the user picked by re-expressing it as a UTC date.
DateTime toDbDate(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Single long-lived MySQL connection for this app instance.
///
/// `mysql1` has no pool, and one desktop client only issues one user action
/// at a time, so all queries are serialized through a [Lock] on one socket.
/// Cross-machine safety (matricules, invoice numbers) comes from InnoDB row
/// locks taken inside [transaction], not from this lock.
class MySqlConnectionService {
  MySqlConnection? _conn;
  DbConfig? _config;
  final _lock = Lock();

  bool get isConnected => _conn != null;

  /// Host of the server this instance is currently connected to.
  String? get connectedHost => _conn == null ? null : _config?.host;

  Future<void> connect(DbConfig config) => _lock.synchronized(() async {
    await _closeQuietly();
    _config = config;
    _conn = await _openShared(config);
  });

  /// The long-lived connection. READ COMMITTED makes every locking read see
  /// the latest committed row, so a PC that waited for a lock never works on
  /// a stale snapshot (MariaDB 11.6+ would otherwise fail the write with
  /// "Record has changed since last read" when two PCs write together).
  Future<MySqlConnection> _openShared(DbConfig config) async {
    final conn = await _open(config);
    await conn.query('SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED');
    return conn;
  }

  Future<void> disconnect() => _lock.synchronized(_closeQuietly);

  /// Opens a throwaway connection to verify settings; never touches the
  /// shared connection. Throws on failure.
  Future<void> testConnection(DbConfig config) async {
    final conn = await _open(config, timeout: const Duration(seconds: 5));
    try {
      await conn.query('SELECT 1');
    } finally {
      await conn.close();
    }
  }

  /// Checks that the server answers and accepts the credentials, without
  /// requiring the database to exist yet.
  Future<void> probe(DbConfig config) =>
      testConnection(config.copyWith(dbName: ''));

  /// Creates the database if it does not exist. Silently does nothing when
  /// the user lacks the privilege (the database is then expected to exist).
  Future<void> ensureDatabase(DbConfig config) async {
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(config.dbName)) {
      throw ArgumentError('Nom de base invalide : ${config.dbName}');
    }
    final conn = await _open(
      config.copyWith(dbName: ''),
      timeout: const Duration(seconds: 5),
    );
    try {
      await conn.query(
        'CREATE DATABASE IF NOT EXISTS `${config.dbName}` '
        'CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } on MySqlException {
      // No CREATE privilege: fall through, connecting will reveal a missing db.
    } finally {
      await conn.close();
    }
  }

  Future<MySqlConnection> _open(
    DbConfig c, {
    Duration timeout = const Duration(seconds: 10),
  }) => MySqlConnection.connect(
    ConnectionSettings(
      host: c.host,
      port: c.port,
      user: c.user,
      password: c.password.isEmpty ? null : c.password,
      db: c.dbName.isEmpty ? null : c.dbName,
      timeout: timeout,
    ),
  );

  Future<void> _closeQuietly() async {
    final conn = _conn;
    _conn = null;
    if (conn != null) await conn.close();
  }

  Future<MySqlConnection> _ensure() async {
    final existing = _conn;
    if (existing != null) return existing;
    final cfg = _config;
    if (cfg == null) {
      throw StateError('Base de données non configurée.');
    }
    return _conn = await _openShared(cfg);
  }

  bool _isConnectionLost(Object e) =>
      e is SocketException || e is TimeoutException;

  /// Runs [action] on the shared connection. If the socket dropped, the
  /// connection is reopened and [action] is retried once.
  Future<T> run<T>(Future<T> Function(MySqlConnection conn) action) =>
      _lock.synchronized(() async {
        try {
          return await action(await _ensure());
        } catch (e) {
          if (!_isConnectionLost(e)) rethrow;
          await _closeQuietly();
          return await action(await _ensure());
        }
      });

  /// Runs [action] inside `START TRANSACTION` ... `COMMIT`. Any exception
  /// rolls back. When two PCs write at the same instant the server may pick
  /// one as a deadlock victim (or time out a lock wait): that transaction has
  /// already been rolled back and is simply run again, up to 4 times. A
  /// dropped socket is not retried: the caller decides whether to redo it.
  Future<T> transaction<T>(
    Future<T> Function(TransactionContext ctx) action,
  ) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _lock.synchronized(() async {
          final conn = await _ensure();
          try {
            final result = await conn.transaction<T>(action);
            return result as T;
          } catch (e) {
            if (_isConnectionLost(e)) await _closeQuietly();
            rethrow;
          }
        });
      } on MySqlException catch (e) {
        // 1213 deadlock, 1205 lock wait timeout, 1020 record changed since read.
        final retryable = const {1213, 1205, 1020}.contains(e.errorNumber);
        if (!retryable || attempt >= 4) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 40 * attempt + Random().nextInt(80)),
        );
      }
    }
  }

  /// SELECT helper returning plain maps (BLOB/TEXT values decoded to String).
  Future<List<Row>> select(String sql, [List<Object?>? params]) =>
      run((conn) async => _toMaps(await conn.query(sql, params)));

  /// INSERT/UPDATE/DELETE helper; returns affected rows.
  Future<int> execute(String sql, [List<Object?>? params]) =>
      run((conn) async => (await conn.query(sql, params)).affectedRows ?? 0);

  static List<Row> _toMaps(Results rs) =>
      rs.map((r) => decodeRow(r.fields)).toList();

  static Row decodeRow(Map<String, dynamic> fields) => {
    for (final e in fields.entries)
      e.key: e.value is Blob ? e.value.toString() : e.value,
  };
}
