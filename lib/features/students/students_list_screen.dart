import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/cancel_dialog.dart';
import '../../core/widgets/hscroll_table.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../models/classe.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';

class StudentsListScreen extends ConsumerWidget {
  const StudentsListScreen({super.key});

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref, {
    required int studentId,
    required String studentName,
  }) async {
    final me = ref.read(authProvider);
    if (me == null) return;
    final reason = await showCancelReasonDialog(
      context,
      title: "Annuler l'inscription de $studentName",
      message:
          "Cette inscription restera visible dans l'application, marquée "
          "ANNULÉE, avec le motif ci-dessous. Elle ne sera plus proposée pour "
          'un encaissement.',
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(studentsRepositoryProvider)
          .cancel(studentId: studentId, cancelledBy: me.fullName, reason: reason);
      ref.invalidate(studentsProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(unpaidReportProvider);
      if (context.mounted) _snack(context, 'Inscription annulée.');
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
    }
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, int studentId) async {
    try {
      await ref.read(studentsRepositoryProvider).confirm(studentId);
      ref.invalidate(studentsProvider);
      ref.invalidate(unpaidReportProvider);
      if (context.mounted) {
        _snack(context, 'Inscription confirmée — comptera dans les impayés.');
      }
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students = ref.watch(studentsProvider);
    final classes = ref.watch(classesProvider);
    final filter = ref.watch(studentFilterProvider);
    final me = ref.watch(authProvider);
    final canCancel = me != null;

    return PageScaffold(
      title: 'Élèves',
      subtitle: 'Liste des élèves de l\'année scolaire active',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/students/promotion'),
          icon: const Icon(Icons.move_up_outlined),
          label: const Text('Promouvoir depuis une année précédente'),
        ),
        FilledButton.icon(
          onPressed: () => context.go('/students/new'),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Nouvel élève'),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 380,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Rechercher par nom ou matricule',
                    ),
                    onChanged: ref
                        .read(studentFilterProvider.notifier)
                        .setQuery,
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<int?>(
                    initialValue: filter.classeId,
                    decoration: const InputDecoration(labelText: 'Classe'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Toutes les classes'),
                      ),
                      for (final c in classes.value ?? const <Classe>[])
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: ref
                        .read(studentFilterProvider.notifier)
                        .setClasse,
                  ),
                ),
                FilterChip(
                  label: const Text('Afficher les annulées'),
                  selected: filter.includeCancelled,
                  onSelected: ref
                      .read(studentFilterProvider.notifier)
                      .setIncludeCancelled,
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncValueView(
              value: students,
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('Aucun élève trouvé.'));
                }
                return SingleChildScrollView(
                  child: Card(
                    child: HScrollTable(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Matricule')),
                          DataColumn(label: Text('Nom')),
                          DataColumn(label: Text('Classe')),
                          DataColumn(label: Text('Niveau')),
                          DataColumn(label: Text('Section')),
                          DataColumn(label: Text('Inscrit le')),
                          DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (final s in list)
                            DataRow(
                              color: s.student.isCancelled
                                  ? WidgetStateProperty.all(
                                      AppColors.danger.withValues(alpha: 0.05),
                                    )
                                  : null,
                              cells: [
                                DataCell(Text(s.student.matricule)),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          s.student.fullName,
                                          overflow: TextOverflow.ellipsis,
                                          style: s.student.isCancelled
                                              ? const TextStyle(
                                                  decoration: TextDecoration
                                                      .lineThrough,
                                                  color: AppColors.textMuted,
                                                )
                                              : null,
                                        ),
                                      ),
                                      if (s.student.isCancelled) ...[
                                        const SizedBox(width: 8),
                                        Tooltip(
                                          message:
                                              'Motif : ${s.student.cancellation!.reason}',
                                          child: const CancelledBadge(),
                                        ),
                                      ] else if (!s.student.confirme) ...[
                                        const SizedBox(width: 8),
                                        const Tooltip(
                                          message:
                                              "Créée par une promotion en masse : pas encore "
                                              "comptée dans les impayés tant qu'aucun "
                                              "paiement ou confirmation n'a eu lieu.",
                                          child: CancelledBadge(
                                            label: 'PROVISOIRE',
                                            color: AppColors.gold,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                DataCell(Text(s.classeName)),
                                DataCell(Text(Niveau.fromDb(s.niveau).label)),
                                DataCell(Text(Section.fromDb(s.section).label)),
                                DataCell(
                                  Text(formatDate(s.student.dateInscription)),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Modifier',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => context.go(
                                          '/students/${s.student.id}/edit',
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Encaisser ou retirer un reçu',
                                        icon: const Icon(Icons.point_of_sale),
                                        onPressed: () => context.go(
                                          '/payments?student=${s.student.id}',
                                        ),
                                      ),
                                      if (!s.student.isCancelled &&
                                          !s.student.confirme)
                                        IconButton(
                                          tooltip:
                                              "Confirmer l'inscription (compte "
                                              'maintenant dans les impayés)',
                                          icon: const Icon(
                                            Icons.check_circle_outline,
                                            color: AppColors.gold,
                                          ),
                                          onPressed: () =>
                                              _confirm(context, ref, s.student.id),
                                        ),
                                      if (canCancel && !s.student.isCancelled)
                                        IconButton(
                                          tooltip: "Annuler l'inscription",
                                          icon: const Icon(
                                            Icons.person_off_outlined,
                                            color: AppColors.danger,
                                          ),
                                          onPressed: () => _cancel(
                                            context,
                                            ref,
                                            studentId: s.student.id,
                                            studentName: s.student.fullName,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
