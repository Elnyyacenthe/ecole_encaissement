import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../models/classe.dart';
import '../../models/tariff.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';

class TariffsScreen extends ConsumerWidget {
  const TariffsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(activeSchoolYearProvider);
    return PageScaffold(
      title: 'Tarifs',
      subtitle: year.value == null
          ? null
          : 'Année scolaire ${year.value!.label} - les montants modifiés '
                's\'appliquent à tous les élèves de cette année',
      child: AsyncValueView(
        value: year,
        data: (y) {
          if (y == null) {
            return const Center(child: Text('Aucune année scolaire active.'));
          }
          return AsyncValueView(
            value: ref.watch(tariffsProvider(y.id)),
            data: (tariffs) => ListView(
              children: [
                for (final niveau in Niveau.values) ...[
                  Text(
                    niveau.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (final t in tariffs.where(
                          (t) => t.niveau == niveau,
                        ))
                          ListTile(
                            title: Text(t.poste.labelFr),
                            subtitle: Text(
                              t.dateLimite == null
                                  ? 'Pas de date limite'
                                  : 'Date limite : ${formatDate(t.dateLimite!)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatMontant(t.montant),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(context, ref, t, y.id),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Tariff t,
    int yearId,
  ) async {
    final amount = TextEditingController(text: '${t.montant}');
    DateTime? due = t.dateLimite;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('${t.niveau.label} - ${t.poste.labelFr}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant (FCFA)'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      due == null ? 'Pas de date limite' : formatDate(due!),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: due ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => due = picked);
                    },
                    child: const Text('Choisir'),
                  ),
                  if (due != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => due = null),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    final montant = parseMontant(amount.text);
    amount.dispose();
    if (saved != true) return;
    if (montant == null || montant < 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Montant invalide.')));
      }
      return;
    }
    await ref
        .read(tariffsRepositoryProvider)
        .update(id: t.id, montant: montant, dateLimite: due);
    ref.invalidate(tariffsProvider(yearId));
    ref.invalidate(studentSituationProvider);
    ref.invalidate(unpaidReportProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tarif mis à jour.')));
    }
  }
}
