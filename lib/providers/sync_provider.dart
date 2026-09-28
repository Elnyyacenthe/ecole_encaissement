import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/sequence_service.dart';
import 'backup_providers.dart';
import 'data_providers.dart';
import 'db_providers.dart';

/// Keeps every screen in step with the other PCs: polls the shared data
/// version every few seconds and, when it changed, reloads the data shown.
/// Watched once by the app shell so it lives as long as the app.
final dataSyncProvider = Provider<void>((ref) {
  if (!ref.watch(dbReadyProvider).hasValue) return;
  final db = ref.watch(dbServiceProvider);

  int? lastVersion;
  var polling = false;
  final timer = Timer.periodic(const Duration(seconds: 3), (_) async {
    if (polling) return;
    polling = true;
    try {
      final rows = await db.select(
        'SELECT current_value FROM counters WHERE counter_key = ?',
        [SequenceService.dataVersionKey],
      );
      final version = rows.isEmpty
          ? 0
          : (rows.first['current_value'] as num).toInt();
      if (lastVersion != null && version != lastVersion) {
        _refreshAll(ref);
      }
      lastVersion = version;
    } catch (_) {
      // Network hiccup: the next tick retries (the service reconnects itself).
    } finally {
      polling = false;
    }
  });
  ref.onDispose(timer.cancel);
});

void _refreshAll(Ref ref) {
  ref
    ..invalidate(studentsProvider)
    ..invalidate(studentProvider)
    ..invalidate(studentSearchProvider)
    ..invalidate(studentSituationProvider)
    ..invalidate(studentInvoicesProvider)
    ..invalidate(historyProvider)
    ..invalidate(receiptDataProvider)
    ..invalidate(dashboardStatsProvider)
    ..invalidate(unpaidReportProvider)
    ..invalidate(tariffsProvider)
    ..invalidate(schoolYearsProvider)
    ..invalidate(activeSchoolYearProvider)
    ..invalidate(usersProvider)
    ..invalidate(backupLogProvider)
    ..invalidate(backupCopyDirProvider)
    ..invalidate(logoBytesProvider);
}
