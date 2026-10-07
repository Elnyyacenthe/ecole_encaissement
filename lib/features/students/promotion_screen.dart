import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/hscroll_table.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../models/classe.dart';
import '../../models/promotion.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';

/// Bulk re-enrolment: takes the roster of a previous school year and
/// proposes it, class by class, for the currently active year — instead of
/// recreating every student by hand at the start of each year.
class PromotionScreen extends ConsumerStatefulWidget {
  const PromotionScreen({super.key});

  @override
  ConsumerState<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends ConsumerState<PromotionScreen> {
  int? _fromYearId;
  DateTime _dateInscription = DateTime.now();
  final Map<int, int?> _selection = {};
  bool _saving = false;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateInscription,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dateInscription = picked);
  }

  Future<void> _confirm(int toYearId, List<PromotionCandidate> candidates) async {
    final selections = [
      for (final c in candidates)
        PromotionSelection(
          studentId: c.studentId,
          fullName: c.fullName,
          targetClasseId: _selection[c.studentId],
        ),
    ];
    final included = selections.where((s) => s.targetClasseId != null).length;
    if (included == 0) {
      _snack('Choisissez au moins un élève à promouvoir.');
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(promotionRepositoryProvider)
          .commit(
            toYearId: toYearId,
            selections: selections,
            dateInscription: _dateInscription,
          );
      ref.invalidate(studentsProvider);
      ref.invalidate(dashboardStatsProvider);
      if (!mounted) return;
      if (result.failures.isEmpty) {
        _snack('${result.promoted} élève(s) inscrit(s) dans la nouvelle année.');
        context.go('/students');
      } else {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('${result.promoted} inscrit(s), ${result.failures.length} échec(s)'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final f in result.failures)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(f, style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) context.go('/students');
      }
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(schoolYearsProvider);
    final activeYear = ref.watch(activeSchoolYearProvider);

    return PageScaffold(
      title: 'Promotion des élèves',
      subtitle:
          "Reprend la liste d'une année précédente et propose la classe "
          "suivante pour chaque élève, plutôt que de tout ressaisir à la main",
      child: AsyncValueView(
        value: years,
        data: (yearList) {
          final active = activeYear.value;
          if (active == null) {
            return const Center(child: Text('Aucune année active.'));
          }
          final sourceCandidates = yearList
              .where((y) => y.id != active.id)
              .toList();
          if (sourceCandidates.isEmpty) {
            return const Center(
              child: Text(
                "Aucune autre année scolaire à partir de laquelle promouvoir.",
              ),
            );
          }
          // Falls back to the first candidate whenever nothing is selected
          // yet, or the previous selection is no longer offered (e.g. it
          // just became the active year itself, or the database was reset
          // while this screen was open) — never trust a stale id blindly.
          if (_fromYearId == null ||
              !sourceCandidates.any((y) => y.id == _fromYearId)) {
            _fromYearId = sourceCandidates.first.id;
          }
          final fromYear = sourceCandidates.firstWhere(
            (y) => y.id == _fromYearId,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<int>(
                      initialValue: _fromYearId,
                      decoration: const InputDecoration(
                        labelText: 'Depuis l\'année',
                      ),
                      items: [
                        for (final y in sourceCandidates)
                          DropdownMenuItem(value: y.id, child: Text(y.label)),
                      ],
                      onChanged: (v) => setState(() => _fromYearId = v),
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: AppColors.textMuted),
                  SizedBox(
                    width: 240,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Vers l\'année active',
                      ),
                      child: Text(active.label),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: "Date d'inscription",
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(formatDate(_dateInscription)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Les élèves déjà réinscrits dans l'année active (même nom) "
                "n'apparaissent pas ci-dessous.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _PromotionTable(
                  key: ValueKey('${fromYear.id}-${active.id}'),
                  fromYearId: fromYear.id,
                  toYearId: active.id,
                  selection: _selection,
                  onSelectionChanged: () => setState(() {}),
                  saving: _saving,
                  onConfirm: _confirm,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PromotionTable extends ConsumerWidget {
  final int fromYearId;
  final int toYearId;
  final Map<int, int?> selection;
  final VoidCallback onSelectionChanged;
  final bool saving;
  final void Function(int toYearId, List<PromotionCandidate> candidates) onConfirm;

  const _PromotionTable({
    super.key,
    required this.fromYearId,
    required this.toYearId,
    required this.selection,
    required this.onSelectionChanged,
    required this.saving,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(classesProvider).value ?? const <Classe>[];
    final preview = ref.watch(
      promotionPreviewProvider((fromYearId: fromYearId, toYearId: toYearId)),
    );

    return AsyncValueView(
      value: preview,
      data: (candidates) {
        if (candidates.isEmpty) {
          return const Center(
            child: Text(
              "Aucun élève à promouvoir depuis cette année (déjà tous "
              "réinscrits, ou année vide).",
            ),
          );
        }
        for (final c in candidates) {
          selection.putIfAbsent(c.studentId, () => c.suggestedClasseId);
        }
        final included = selection.values.where((v) => v != null).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Card(
                child: HScrollTable(
                  child: DataTable(
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 64,
                    columns: const [
                      DataColumn(label: Text('Matricule')),
                      DataColumn(label: Text('Élève')),
                      DataColumn(label: Text('Classe actuelle')),
                      DataColumn(label: Text('Nouvelle classe')),
                    ],
                    rows: [
                      for (final c in candidates)
                        DataRow(
                          cells: [
                            DataCell(Text(c.matricule)),
                            DataCell(Text(c.fullName)),
                            DataCell(Text(c.currentClasseName)),
                            DataCell(
                              SizedBox(
                                width: 240,
                                child: DropdownButtonFormField<int?>(
                                  initialValue: selection[c.studentId],
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: null,
                                      child: Text(
                                        'Ne pas promouvoir',
                                        style: TextStyle(
                                          color: AppColors.danger,
                                        ),
                                      ),
                                    ),
                                    for (final cl in classes.where(
                                      (cl) => cl.section == c.section,
                                    ))
                                      DropdownMenuItem(
                                        value: cl.id,
                                        child: Text(cl.name),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    selection[c.studentId] = v;
                                    onSelectionChanged();
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '$included élève(s) sur ${candidates.length} seront inscrit(s).',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: saving ? null : () => onConfirm(toYearId, candidates),
                  icon: const Icon(Icons.done_all),
                  label: Text(
                    saving ? 'Enregistrement…' : 'Confirmer la promotion',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
