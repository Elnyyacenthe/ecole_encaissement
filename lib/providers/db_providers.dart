import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/db_auto_connector.dart';
import '../core/db/db_bootstrap.dart';
import '../core/db/db_settings_repository.dart';
import '../core/db/embedded_server.dart';
import '../core/db/mysql_connection_service.dart';
import '../repositories/classes_repository.dart';
import '../repositories/payments_repository.dart';
import '../repositories/promotion_repository.dart';
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

/// The error from the most recent failed attempt, while [dbReadyProvider]
/// keeps retrying in the background — null once connected. Lets the waiting
/// screen show what's wrong and offer an immediate retry, without the whole
/// provider surfacing an [AsyncError] and stopping (see [dbReadyProvider]).
class _DbLastErrorNotifier extends Notifier<Object?> {
  @override
  Object? build() => null;
  void set(Object? value) => state = value;
}

final dbLastErrorProvider = NotifierProvider<_DbLastErrorNotifier, Object?>(
  _DbLastErrorNotifier.new,
);

/// Completing this skips the current backoff wait so "Réessayer maintenant"
/// retries right away instead of waiting out the timer. [dbReadyProvider]
/// replaces it with a fresh instance at the start of every wait so the
/// button always targets the wait actually in progress.
class _DbManualRetryNotifier extends Notifier<Completer<void>> {
  @override
  Completer<void> build() => Completer<void>();
  void set(Completer<void> value) => state = value;
}

final dbManualRetryProvider =
    NotifierProvider<_DbManualRetryNotifier, Completer<void>>(
      _DbManualRetryNotifier.new,
    );

/// One connection attempt's wait before the next retry: short at first,
/// capped so it never becomes a long silent gap.
Duration _backoff(int attempt) {
  const steps = [2, 3, 5, 8, 12];
  return Duration(seconds: attempt <= steps.length ? steps[attempt - 1] : 15);
}

/// Finds and connects to the MySQL server automatically, then creates/seeds
/// the schema — retrying forever in the background (with a fresh network
/// scan each time via [DbAutoConnector.connect]) instead of giving up after
/// one failure, since the server PC may simply not be up yet or the network
/// may be briefly unstable. [dbLastErrorProvider] carries the latest error
/// for the waiting screen; "Réessayer maintenant" (via
/// [dbManualRetryProvider]) skips the wait instead of needing a full
/// provider invalidation. Everything that touches the database awaits this
/// provider; invalidate it after changing the advanced settings.
final dbReadyProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(dbServiceProvider);
  final status = ref.watch(dbStatusProvider);
  final lastError = ref.read(dbLastErrorProvider.notifier);
  final connector = DbAutoConnector(
    db: db,
    settings: ref.watch(dbSettingsRepositoryProvider),
    onStatus: (s) => status.value = s,
  );

  var attempt = 0;
  while (true) {
    try {
      await EmbeddedServer(onStatus: (s) => status.value = s).ensureRunning();
      await connector.connect();
      status.value = 'Chargement des données…';
      await bootstrapDatabase(db);
      lastError.set(null);
      return;
    } catch (e) {
      attempt++;
      lastError.set(e);
      final wait = _backoff(attempt);
      status.value =
          'Serveur introuvable (tentative $attempt). Nouvel essai dans '
          '${wait.inSeconds}s…';
      final signal = Completer<void>();
      ref.read(dbManualRetryProvider.notifier).set(signal);
      await Future.any([Future<void>.delayed(wait), signal.future]);
    }
  }
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

final promotionRepositoryProvider = Provider(
  (ref) => PromotionRepository(
    ref.watch(dbServiceProvider),
    ref.watch(studentsRepositoryProvider),
    ref.watch(classesRepositoryProvider),
  ),
);
