import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../providers/data_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(activeSchoolYearProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final identity = ref.watch(schoolIdentityProvider).value;
    final schoolName = identity?.name ?? 'Complexe Scolaire Bilingue Mariane et Paul';

    return PageScaffold(
      title: 'Tableau de bord',
      subtitle: '$schoolName - année scolaire ${year.value?.label ?? '-'}',
      child: ListView(
        children: [
          AsyncValueView(
            value: stats,
            data: (s) => Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                _StatCard(
                  icon: Icons.people_alt_outlined,
                  color: AppColors.navy,
                  label: 'Élèves inscrits',
                  value: '${s?.studentCount ?? 0}',
                  onTap: () => context.go('/students'),
                ),
                _StatCard(
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.green,
                  label: "Paiements aujourd'hui",
                  value: '${s?.paymentsToday ?? 0}',
                  onTap: () => context.go('/payments'),
                ),
                _StatCard(
                  icon: Icons.account_balance_wallet_outlined,
                  color: AppColors.gold,
                  label: "Encaissé aujourd'hui",
                  value: formatMontant(s?.totalToday ?? 0),
                  onTap: () => context.go('/payments'),
                ),
                _StatCard(
                  icon: Icons.cancel_outlined,
                  color: AppColors.danger,
                  label: "Annulations aujourd'hui",
                  value: '${s?.cancellationsToday ?? 0}',
                  onTap: () => context.go('/history'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Actions rapides',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              _ActionTile(
                icon: Icons.person_add_alt_1_outlined,
                title: 'Nouvel élève',
                text: 'Inscrire un élève et générer son matricule',
                onTap: () => context.go('/students/new'),
              ),
              _ActionTile(
                icon: Icons.point_of_sale,
                title: 'Encaisser un paiement',
                text: 'Enregistrer un paiement et imprimer le reçu',
                onTap: () => context.go('/payments'),
              ),
              _ActionTile(
                icon: Icons.assignment_late_outlined,
                title: 'Rapport des impayés',
                text: 'Lister les élèves qui n\'ont pas soldé',
                onTap: () => context.go('/reports/unpaid'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 290,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 290,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.navy, size: 30),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
