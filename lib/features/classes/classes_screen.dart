import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../models/classe.dart';
import '../../providers/data_providers.dart';

/// Classes with their effectif (headcount) for the active year — click one
/// to see its roster in Élèves.
class ClassesScreen extends ConsumerWidget {
  const ClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headcounts = ref.watch(classeHeadcountsProvider);
    final year = ref.watch(activeSchoolYearProvider).value;

    return PageScaffold(
      title: 'Classes',
      subtitle: year == null
          ? null
          : "Effectifs de l'année scolaire ${year.label} — cliquez une "
                'classe pour voir sa liste',
      child: AsyncValueView(
        value: headcounts,
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucune classe.'));
          }
          final bySection = <Section, List<ClasseHeadcount>>{};
          for (final h in list) {
            bySection.putIfAbsent(h.classe.section, () => []).add(h);
          }
          return ListView(
            children: [
              for (final section in Section.values)
                if (bySection[section]?.isNotEmpty ?? false) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, top: 8),
                    child: Text(
                      section.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final h in bySection[section]!)
                        _ClasseCard(
                          headcount: h,
                          onTap: () {
                            ref
                                .read(studentFilterProvider.notifier)
                                .setClasse(h.classe.id);
                            context.go('/students');
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _ClasseCard extends StatelessWidget {
  final ClasseHeadcount headcount;
  final VoidCallback onTap;
  const _ClasseCard({required this.headcount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = headcount.classe;
    return SizedBox(
      width: 220,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  c.niveau.label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.people_alt_outlined,
                      size: 18,
                      color: AppColors.navy,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${headcount.total} élève${headcount.total > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
