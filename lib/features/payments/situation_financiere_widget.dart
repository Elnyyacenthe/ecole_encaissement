import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../models/payment_situation.dart';

/// Per-poste due / paid / remaining table plus the yearly totals.
class SituationFinanciereWidget extends StatelessWidget {
  final StudentSituation situation;
  const SituationFinanciereWidget({super.key, required this.situation});

  @override
  Widget build(BuildContext context) {
    final bold = Theme.of(context).textTheme.titleSmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Situation financière',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (situation.postes.isEmpty)
              const Text(
                'Aucun tarif défini pour cet élève (voir écran Tarifs).',
              )
            else
              Table(
                columnWidths: const {0: FlexColumnWidth(2.2)},
                children: [
                  TableRow(
                    children: [
                      _cell('Poste', style: bold),
                      _cell('Date limite', style: bold),
                      _cell('Dû', style: bold, right: true),
                      _cell('Payé', style: bold, right: true),
                      _cell('Reste', style: bold, right: true),
                    ],
                  ),
                  for (final p in situation.postes)
                    TableRow(
                      children: [
                        _cell(p.poste.labelFr),
                        _cell(
                          p.dateLimite == null
                              ? '-'
                              : formatDate(p.dateLimite!),
                        ),
                        _cell(formatMontant(p.montantDu), right: true),
                        _cell(formatMontant(p.montantPaye), right: true),
                        _cell(
                          p.estSolde ? 'Soldé' : formatMontant(p.resteAPayer),
                          right: true,
                          color: p.estSolde
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ],
                    ),
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    children: [
                      _cell('Total année', style: bold),
                      _cell(''),
                      _cell(
                        formatMontant(situation.totalDu),
                        style: bold,
                        right: true,
                      ),
                      _cell(
                        formatMontant(situation.totalPaye),
                        style: bold,
                        right: true,
                      ),
                      _cell(
                        formatMontant(situation.totalReste),
                        style: bold,
                        right: true,
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    String text, {
    TextStyle? style,
    bool right = false,
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: (style ?? const TextStyle()).copyWith(color: color),
    ),
  );
}
