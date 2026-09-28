import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/db_auto_connector.dart';
import '../core/db/db_bootstrap.dart';
import '../core/db/db_settings_repository.dart';
import '../core/db/embedded_server.dart';
import '../core/db/mysql_connection_service.dart';
import '../repositories/classes_repository.dart';
import '../repositories/payments_repository.dart';
import '../repositories/reports_repository.dart';
import '../repositories/school_years_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/students_repository.dart';
import '../repositories/tariffs_repository.dart';
import '../repositories/users_repository.dart';

final dbServiceProvider = Provider<MySqlConnectionService>((ref) {
  final service = MySqlConnectionService();
  ref.onDispose(service.disconnect);
  return service;
});

final dbSettingsRepositoryProvider = Provider<DbSettingsRepository>(
  (ref) => DbSettingsRepository(),
);

/// Human-readable progress of the automatic connection ("Recherche du serveur…").
final dbStatusProvider = Provider<ValueNotifier<String>>(
  (ref) => ValueNotifier('Connexion au serveur…'),
);

/// Finds and connects to the MySQL server automatically, then creates/seeds
/// the schema. Everything that touches the database awaits this provider;
/// invalidate it to retry or after changing the advanced settings.
final dbReadyProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(dbServiceProvider);
  final status = ref.watch(dbStatusProvider);
  final connector = DbAutoConnector(
    db: db,
    settings: ref.watch(dbSettingsRepositoryProvider),
    onStatus: (s) => status.value = s,
  );
  await EmbeddedServer(onStatus: (s) => status.value = s).ensureRunning();
  await connector.connect();
  status.value = 'Chargement des données…';
  await bootstrapDatabase(db);
});

final settingsRepositoryProvider = Provider(
  (ref) => SettingsRepository(ref.watch(dbServiceProvider)),
);
final classesRepositoryProvider = Provider(
  (ref) => ClassesRepository(ref.watch(dbServiceProvider)),
);
final schoolYearsRepositoryProvider = Provider(
  (ref) => SchoolYearsRepository(ref.watch(dbServiceProvider)),
);
final studentsRepositoryProvider = Provider(
  (ref) => StudentsRepository(ref.watch(dbServiceProvider)),
);
final tariffsRepositoryProvider = Provider(
  (ref) => TariffsRepository(ref.watch(dbServiceProvider)),
);
final paymentsRepositoryProvider = Provider(
  (ref) => PaymentsRepository(
    ref.watch(dbServiceProvider),
    ref.watch(studentsRepositoryProvider),
  ),
);
final reportsRepositoryProvider = Provider(
  (ref) => ReportsRepository(ref.watch(dbServiceProvider)),
);

final usersRepositoryProvider = Provider(
  (ref) => UsersRepository(ref.watch(dbServiceProvider)),
);
