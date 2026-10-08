import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/hscroll_table.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../models/classe.dart';
import '../../models/tariff.dart';
import '../../pdf/individual_notice_pdf_builder.dart';
import '../../pdf/pdf_assets.dart';
import '../../pdf/unpaid_report_pdf_builder.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';
import '../../repositories/reports_repository.dart';

/// Builds one [NoticeData] per row by fetching each student's full-year
/// situation, then opens the print preview for those pages.
Future<void> _printIndividualNotices(
  WidgetRef ref, {
  required List<UnpaidRow> rows,
  required Poste poste,
}) async {
  final payments = ref.read(paymentsRepositoryProvider);
  final notices = await Future.wait<NoticeData>([
    for (final row in rows)
      payments
          .situationFor(row.studentId)
          .then((s) => NoticeData(row: row, subjectPoste: poste, situation: s)),
  ]);
  final bytes = await buildIndividualNoticesPdf(
    notices: notices,
    logo: await loadLogoBytes(ref),
    identity: await loadSchoolIdentity(ref),
  );
  final name = notices.length == 1
      ? 'note_${notices.first.row.matricule}.pdf'
      : 'notes_individuelles_${poste.dbValue.toLowerCase()}.pdf';
  await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
}

class UnpaidReportScreen extends ConsumerWidget {
  const UnpaidReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(unpaidFilterProvider);
    final notifier = ref.read(unpaidFilterProvider.notifier);
    final report = ref.watch(unpaidReportProvider);
    final year = ref.watch(activeSchoolYearProvider).value;
    final classes = ref.watch(classesProvider).value ?? const <Classe>[];
    final classeLabel = filter.classeId == null
        ? null
        : classes.where((c) => c.id == filter.classeId).firstOrNull?.name;

    return PageScaffold(
      title: 'Rapport des impayés',
      subtitle: 'Élèves n\'ayant pas encore soldé le poste choisi — pour '
          'toute l\'école ou une seule classe',
      actions: [
        OutlinedButton.icon(
          onPressed: report.hasValue && report.requireValue.isNotEmpty
              ? () => _printIndividualNotices(
                  ref,
                  rows: report.requireValue,
                  poste: filter.poste,
                )
              : null,
          icon: const Icon(Icons.assignment_ind_outlined),
          label: Text(
            classeLabel == null
                ? 'Notes individuelles (toute l\'école)'
                : 'Notes individuelles ($classeLabel)',
          ),
        ),
        FilledButton.icon(
          onPressed: report.hasValue && year != null
              ? () async {
                  final bytes = await buildUnpaidReportPdf(
                    rows: report.requireValue,
                    poste: filter.poste,
                    schoolYearLabel: year.label,
                    asOf: filter.asOf,
                    logo: await loadLogoBytes(ref),
                    identity: await loadSchoolIdentity(ref),
                    classeLabel: classeLabel,
                  );
                  await Printing.layoutPdf(
                    name: 'impayes_${filter.poste.dbValue.toLowerCase()}'
                        '${classeLabel == null ? '' : '_${classeLabel.toLowerCase().replaceAll(' ', '_')}'}'
                        '.pdf',
                    onLayout: (_) async => bytes,
                  );
                }
              : null,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(
            classeLabel == null
                ? 'Liste collective (toute l\'école)'
                : 'Liste collective ($classeLabel)',
          ),
        ),
      ],
      child: ListView(
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<Poste>(
                  initialValue: filter.poste,
                  decoration: const InputDecoration(labelText: 'Poste'),
                  items: [
                    for (final p in Poste.values)
                      DropdownMenuItem(value: p, child: Text(p.labelFr)),
                  ],
                  onChanged: (p) {
                    if (p != null) notifier.setPoste(p);
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<int?>(
                  initialValue: filter.classeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Classe'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text("Pour tout le monde (toute l'école)"),
                    ),
                    for (final c in classes)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text('Par classe : ${c.name}'),
                      ),
                  ],
                  onChanged: notifier.setClasse,
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(
                  filter.asOf == null
                      ? 'Paiements jusqu\'au : toutes dates'
                      : 'Paiements jusqu\'au ${formatDate(filter.asOf!)}',
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: filter.asOf ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) notifier.setAsOf(picked);
                },
              ),
              if (filter.asOf != null)
                TextButton(
                  onPressed: () => notifier.setAsOf(null),
                  child: const Text('Toutes dates'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Trois façons de sortir les impayés : pour tout le monde (aucune '
            'classe choisie), par classe (menu "Classe" ci-dessus), ou '
            'individuel (bouton note sur une seule ligne).',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          AsyncValueView(
            value: report,
            data: (rows) {
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Aucun impayé pour ce poste.')),
                );
              }
              final totalReste = rows.fold<int>(0, (s, r) => s + r.reste);
              final now = DateTime.now();
              final overdueCount = rows.where((r) => r.isOverdue(now)).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: HScrollTable(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Matricule')),
                          DataColumn(label: Text('Nom')),
                          DataColumn(label: Text('Classe')),
                          DataColumn(label: Text('Déjà payé'), numeric: true),
                          DataColumn(label: Text('Reste dû'), numeric: true),
                          DataColumn(label: Text('Date limite')),
                          DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (final r in rows)
                            DataRow(
                              color: r.isOverdue(now)
                                  ? WidgetStateProperty.all(
                                      const Color(0xFFFDECEA),
                                    )
                                  : null,
                              cells: [
                                DataCell(Text(r.matricule)),
                                DataCell(Text(r.fullName)),
                                DataCell(Text(r.classeName)),
                                DataCell(Text(formatMontant(r.montantPaye))),
                                DataCell(Text(formatMontant(r.reste))),
                                DataCell(
                                  r.dateLimite == null
                                      ? const Text('-')
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(formatDate(r.dateLimite!)),
                                            if (r.isOverdue(now)) ...[
                                              const SizedBox(width: 6),
                                              const Icon(
                                                Icons.warning_amber_rounded,
                                                size: 16,
                                                color: AppColors.danger,
                                              ),
                                            ],
                                          ],
                                        ),
                                ),
                                DataCell(
                                  IconButton(
                                    tooltip: 'Note individuelle',
                                    icon: const Icon(
                                      Icons.assignment_ind_outlined,
                                    ),
                                    onPressed: () => _printIndividualNotices(
                                      ref,
                                      rows: [r],
                                      poste: filter.poste,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      '${rows.length} élève(s) - total restant dû : ${formatMontant(totalReste)}'
                      '${overdueCount == 0 ? '' : ' - dont $overdueCount en retard'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
