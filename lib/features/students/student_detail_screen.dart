import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/cancel_dialog.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../models/app_user.dart';
import '../../models/classe.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';
import '../payments/situation_financiere_widget.dart';

/// Read-only consultation fiche — the default way to look at a student,
/// replacing "open Modifier then Annuler" just to see their information.
/// "Modifier" is a separate, explicit, role-gated button.
class StudentDetailScreen extends ConsumerWidget {
  final int studentId;
  const StudentDetailScreen({super.key, required this.studentId});

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref, {
    required int id,
    required String name,
  }) async {
    final me = ref.read(authProvider);
    if (me == null) return;
    final reason = await showCancelReasonDialog(
      context,
      title: "Annuler l'inscription de $name",
      message:
          "Cette inscription restera visible, marquée ANNULÉE, avec le "
          "motif ci-dessous. Elle ne sera plus proposée pour un encaissement.",
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(studentsRepositoryProvider)
          .cancel(studentId: id, cancelledBy: me.fullName, reason: reason);
      ref.invalidate(studentProvider(id));
      ref.invalidate(studentsProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(unpaidReportProvider);
      if (context.mounted) _snack(context, 'Inscription annulée.');
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
    }
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, int id) async {
    try {
      await ref.read(studentsRepositoryProvider).confirm(id);
      ref.invalidate(studentProvider(id));
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
    final student = ref.watch(studentProvider(studentId));
    final me = ref.watch(authProvider);
    final canEdit = me?.role.hasAdminRights ?? false;

    return PageScaffold(
      title: 'Fiche élève',
      subtitle: 'Consultation — utilisez "Modifier" pour changer une information',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/payments?student=$studentId'),
          icon: const Icon(Icons.point_of_sale),
          label: const Text('Encaisser'),
        ),
        if (canEdit)
          FilledButton.icon(
            onPressed: () => context.go('/students/$studentId/edit'),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Modifier'),
          ),
      ],
      child: AsyncValueView(
        value: student,
        data: (s) {
          if (s == null) {
            return const Center(child: Text('Élève introuvable.'));
          }
          return _Detail(
            s: s,
            me: me,
            onCancel: () =>
                _cancel(context, ref, id: s.student.id, name: s.student.fullName),
            onConfirm: () => _confirm(context, ref, s.student.id),
          );
        },
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  final StudentWithClasse s;
  final AppUser? me;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _Detail({
    required this.s,
    required this.me,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = s.student;
    final situation = ref.watch(studentSituationProvider(student.id));
    final history = ref.watch(studentClassHistoryProvider(student.fullName));

    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        student.fullName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    if (student.isCancelled)
                      const CancelledBadge()
                    else if (!student.confirme)
                      const CancelledBadge(
                        label: 'PROVISOIRE',
                        color: AppColors.gold,
                      ),
                  ],
                ),
                if (student.isCancelled) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Motif : ${student.cancellation!.reason}',
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _kv('Matricule', student.matricule),
                    _kv('Classe', s.classeName),
                    _kv('Niveau', Niveau.fromDb(s.niveau).label),
                    _kv('Section', Section.fromDb(s.section).label),
                    _kv('Année scolaire', s.schoolYearLabel),
                    _kv("Date d'inscription", formatDate(student.dateInscription)),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (!student.isCancelled && !student.confirme)
                      OutlinedButton.icon(
                        onPressed: onConfirm,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text("Confirmer l'inscription"),
                      ),
                    if (me != null && !student.isCancelled)
                      OutlinedButton.icon(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        icon: const Icon(Icons.person_off_outlined),
                        label: const Text("Annuler l'inscription"),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'État civil',
          children: [
            _kv(
              'Date de naissance',
              student.dateNaissance == null
                  ? '-'
                  : formatDate(student.dateNaissance!),
            ),
            _kv('Lieu de naissance', student.lieuNaissance ?? '-'),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Parents ou tuteur',
          children: [
            _kv('Nom du père', student.nomPere ?? '-'),
            _kv('Profession', student.professionPere ?? '-'),
            _kv('Nom de la mère', student.nomMere ?? '-'),
            _kv('Profession', student.professionMere ?? '-'),
            _kv('Adresse', student.adresseParents ?? '-'),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: "Contacts susceptibles de chercher l'enfant",
          children: [
            _kv('Contact 1', student.contactUrgence1 ?? '-'),
            _kv('Contact 2', student.contactUrgence2 ?? '-'),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Historique des classes',
          subtitle:
              'Fiches portant ce nom exact, toutes années confondues — pas '
              "une identité garantie si deux élèves partagent le même nom.",
          children: [
            AsyncValueView(
              value: history,
              data: (rows) {
                if (rows.length <= 1) {
                  return const Text(
                    'Aucun autre historique trouvé.',
                    style: TextStyle(color: AppColors.textMuted),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 110,
                              child: Text(
                                r.schoolYearLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${r.classeName} - ${r.student.matricule}',
                              ),
                            ),
                            if (r.student.isCancelled)
                              const CancelledBadge()
                            else if (!r.student.confirme)
                              const CancelledBadge(
                                label: 'PROVISOIRE',
                                color: AppColors.gold,
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncValueView(
          value: situation,
          data: (sit) => SituationFinanciereWidget(situation: sit),
        ),
      ],
    );
  }

  Widget _kv(String label, String value) => SizedBox(
    width: 260,
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label : ',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 24, runSpacing: 8, children: children),
          ],
        ),
      ),
    );
  }
}
