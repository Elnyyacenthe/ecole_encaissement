import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_value_view.dart';
import '../../models/backup_entry.dart';
import '../../providers/backup_providers.dart';

/// Automatic backups: state of the last one, "back up now", extra copy
/// folder and the journal. Backups are made on the server PC.
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _busy = false;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    final result = await BackupService.run('manuelle');
    ref.invalidate(backupLogProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(result.ok ? 'Sauvegarde terminée.' : 'Échec : ${result.message}');
  }

  Future<void> _chooseCopyDir() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Choisir ce dossier',
    );
    if (path == null) return;
    await ref.read(backupRepositoryProvider).setCopyDir(path);
    ref.invalidate(backupCopyDirProvider);
    if (mounted) _snack('Les sauvegardes seront aussi copiées dans : $path');
  }

  Future<void> _clearCopyDir() async {
    await ref.read(backupRepositoryProvider).setCopyDir(null);
    ref.invalidate(backupCopyDirProvider);
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(backupLogProvider);
    final copyDir = ref.watch(backupCopyDirProvider).value;
    final isServer = ref.watch(isServerPcProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sauvegardes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'La base est sauvegardée automatiquement chaque jour à 12h30 et à 19h00 '
          '(rattrapée au démarrage si le PC était éteint). Les 10 plus récentes sont '
          'toujours conservées, les autres pendant 60 jours.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AsyncValueView(
                  value: log,
                  data: (entries) => _StatusBanner(entries: entries),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: isServer && !_busy ? _backupNow : null,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.backup_outlined),
                      label: Text(
                        _busy
                            ? 'Sauvegarde en cours…'
                            : 'Sauvegarder maintenant',
                      ),
                    ),
                    if (!isServer)
                      const Text(
                        'Disponible sur le PC serveur uniquement.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                  ],
                ),
                const Divider(height: 32),
                Text(
                  'Copie de sécurité externe',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Une sauvegarde qui reste sur le même PC ne protège pas d\'une panne de ce PC. '
                  'Choisissez une clé USB, un disque externe ou un dossier partagé sur un autre '
                  'ordinateur : chaque sauvegarde y sera aussi copiée.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      copyDir == null
                          ? Icons.folder_off_outlined
                          : Icons.folder_outlined,
                      color: copyDir == null ? AppColors.gold : AppColors.green,
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        copyDir ?? 'Aucun dossier choisi',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: copyDir == null ? AppColors.textMuted : null,
                        ),
                      ),
                    ),
                    if (isServer) ...[
                      OutlinedButton(
                        onPressed: _chooseCopyDir,
                        child: Text(
                          copyDir == null ? 'Choisir un dossier…' : 'Changer…',
                        ),
                      ),
                      if (copyDir != null)
                        TextButton(
                          onPressed: _clearCopyDir,
                          child: const Text('Retirer'),
                        ),
                    ],
                  ],
                ),
                if (!isServer)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Le dossier se choisit depuis le PC serveur.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                const Divider(height: 32),
                Text(
                  'Dernières sauvegardes',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                AsyncValueView(
                  value: log,
                  data: (entries) => entries.isEmpty
                      ? const Text(
                          'Aucune pour le moment.',
                          style: TextStyle(color: AppColors.textMuted),
                        )
                      : Column(
                          children: [
                            for (final e in entries.take(8))
                              _EntryRow(entry: e),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sur le PC serveur, les fichiers sont dans C:\\ProgramData\\COSBIMP\\backups. '
                  'Pour restaurer, utilisez « Restaurer-une-sauvegarde.bat » dans le dossier COSBIMP du PC serveur.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final List<BackupEntry> entries;
  const _StatusBanner({required this.entries});

  @override
  Widget build(BuildContext context) {
    final lastOk = entries.where((e) => e.ok).firstOrNull;
    final latest = entries.firstOrNull;

    late final Color color;
    late final IconData icon;
    late final String text;

    if (latest == null) {
      color = AppColors.gold;
      icon = Icons.warning_amber_rounded;
      text =
          'Aucune sauvegarde pour le moment. La première sera faite automatiquement '
          '(12h30 ou 19h00), ou cliquez sur « Sauvegarder maintenant ».';
    } else if (!latest.ok) {
      color = AppColors.danger;
      icon = Icons.error_outline;
      text =
          'La dernière sauvegarde a échoué (${formatDateTime(latest.createdAt)}) : '
          '${latest.message ?? 'erreur inconnue'}'
          '${lastOk == null ? '' : '\nDernière réussite : ${formatDateTime(lastOk.createdAt)}.'}';
    } else {
      final t = latest.createdAt;
      final age = DateTime.now().difference(
        DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second),
      );
      final warnCopy = (latest.message ?? '').contains(
        'copie externe impossible',
      );
      if (age.inHours >= 36) {
        color = AppColors.gold;
        icon = Icons.warning_amber_rounded;
        text =
            'La dernière sauvegarde date de plus de 36 heures '
            '(${formatDateTime(t)}). Vérifiez que le PC serveur est allumé.';
      } else if (warnCopy) {
        color = AppColors.gold;
        icon = Icons.warning_amber_rounded;
        text = '${latest.message}';
      } else {
        color = AppColors.green;
        icon = Icons.verified_outlined;
        text =
            'Dernière sauvegarde réussie : ${formatDateTime(t)} '
            '(${formatTaille(latest.sizeBytes)})'
            '${latest.copiedTo == null ? '' : ', copiée dans ${latest.copiedTo}'}.';
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final BackupEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            entry.ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: entry.ok ? AppColors.green : AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 16,
              children: [
                Text(formatDateTime(entry.createdAt)),
                Text(
                  entry.sourceLabel,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                if (entry.ok)
                  Text(
                    formatTaille(entry.sizeBytes),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
