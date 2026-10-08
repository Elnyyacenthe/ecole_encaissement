import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../models/classe.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';

/// Classes with their effectif (headcount) for the active year — click one
/// to see its roster in Élèves. Admin/Direction can add, rename and remove
/// classes here (each school configures its own list).
class ClassesScreen extends ConsumerWidget {
  const ClassesScreen({super.key});

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final data = await showDialog<_NewClasse>(
      context: context,
      builder: (_) => const _ClasseDialog(),
    );
    if (data == null) return;
    try {
      await ref
          .read(classesRepositoryProvider)
          .create(name: data.name, section: data.section, niveau: data.niveau);
      ref.invalidate(classesProvider);
      ref.invalidate(classeHeadcountsProvider);
      if (context.mounted) _snack(context, 'Classe ajoutée.');
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Classe classe,
  ) async {
    final controller = TextEditingController(text: classe.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer la classe'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom de la classe'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    try {
      await ref.read(classesRepositoryProvider).rename(classe.id, name);
      ref.invalidate(classesProvider);
      ref.invalidate(classeHeadcountsProvider);
      if (context.mounted) _snack(context, 'Classe renommée.');
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Classe classe,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer "${classe.name}" ?'),
        content: const Text(
          "Impossible si des élèves (actuels ou passés) y sont rattachés.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(classesRepositoryProvider).delete(classe.id);
      ref.invalidate(classesProvider);
      ref.invalidate(classeHeadcountsProvider);
      if (context.mounted) _snack(context, 'Classe supprimée.');
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headcounts = ref.watch(classeHeadcountsProvider);
    final year = ref.watch(activeSchoolYearProvider).value;
    final canManage = ref.watch(authProvider)?.role.hasAdminRights ?? false;

    return PageScaffold(
      title: 'Classes',
      subtitle: year == null
          ? null
          : "Effectifs de l'année scolaire ${year.label} — cliquez une "
                'classe pour voir sa liste',
      actions: [
        if (canManage)
          FilledButton.icon(
            onPressed: () => _add(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter une classe'),
          ),
      ],
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
                          canManage: canManage,
                          onTap: () {
                            ref
                                .read(studentFilterProvider.notifier)
                                .setClasse(h.classe.id);
                            context.go('/students');
                          },
                          onRename: () => _rename(context, ref, h.classe),
                          onDelete: () => _delete(context, ref, h.classe),
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
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  const _ClasseCard({
    required this.headcount,
    required this.canManage,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (canManage)
                      PopupMenuButton<String>(
                        iconSize: 18,
                        tooltip: 'Actions',
                        onSelected: (v) =>
                            v == 'rename' ? onRename() : onDelete(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Renommer'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Supprimer'),
                          ),
                        ],
                      ),
                  ],
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

class _NewClasse {
  final String name;
  final Section section;
  final Niveau niveau;
  const _NewClasse(this.name, this.section, this.niveau);
}

class _ClasseDialog extends StatefulWidget {
  const _ClasseDialog();

  @override
  State<_ClasseDialog> createState() => _ClasseDialogState();
}

class _ClasseDialogState extends State<_ClasseDialog> {
  final _name = TextEditingController();
  Section _section = Section.francophone;
  Niveau _niveau = Niveau.maternelle;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle classe'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Nom de la classe'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Section>(
              initialValue: _section,
              decoration: const InputDecoration(labelText: 'Section'),
              items: [
                for (final s in Section.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _section = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Niveau>(
              initialValue: _niveau,
              decoration: const InputDecoration(labelText: 'Niveau'),
              items: [
                for (final n in Niveau.values)
                  DropdownMenuItem(value: n, child: Text(n.label)),
              ],
              onChanged: (v) => setState(() => _niveau = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _NewClasse(_name.text, _section, _niveau),
                ),
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}
