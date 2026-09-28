import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backup/backup_service.dart';
import '../models/backup_entry.dart';
import '../repositories/backup_repository.dart';
import 'db_providers.dart';

final backupRepositoryProvider = Provider(
  (ref) => BackupRepository(
    ref.watch(dbServiceProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

/// True on the PC that hosts the database (backups are made from there).
final isServerPcProvider = Provider<bool>((ref) => BackupService.isServerPc);

final backupLogProvider = FutureProvider<List<BackupEntry>>((ref) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(backupRepositoryProvider).recent();
});

final backupCopyDirProvider = FutureProvider<String?>((ref) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(backupRepositoryProvider).copyDir();
});

/// Safety net on the server PC: the Windows scheduled task makes the daily
/// backups; if the PC was off or the task could not be created, the app makes
/// one itself when the last successful backup is more than 20 hours old.
final backupSchedulerProvider = Provider<void>((ref) {
  if (!ref.watch(dbReadyProvider).hasValue) return;
  if (!ref.watch(isServerPcProvider)) return;
  final repo = ref.watch(backupRepositoryProvider);

  Future<void> check() async {
    try {
      final hours = await repo.hoursSinceLastSuccess();
      if (hours == null || hours >= 20) {
        await BackupService.run('rattrapage');
        ref.invalidate(backupLogProvider);
      }
    } catch (_) {
      // Retried at the next tick.
    }
  }

  final first = Timer(const Duration(seconds: 45), check);
  final periodic = Timer.periodic(const Duration(minutes: 30), (_) => check());
  ref.onDispose(() {
    first.cancel();
    periodic.cancel();
  });
});
