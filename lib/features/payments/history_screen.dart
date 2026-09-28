import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/cancel_dialog.dart';
import '../../core/widgets/hscroll_table.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';

/// Every invoice issued, newest first, with search and date filters.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref, {
    required int invoiceNumber,
    required String studentName,
  }) async {
    final me = ref.read(authProvider);
    if (me == null) return;
    final reason = await showCancelReasonDialog(
      context,
      title: 'Annuler la facture n°$invoiceNumber ($studentName)',
      message:
          "Cette facture restera visible dans l'historique, marquée "
          "ANNULÉE, avec le motif ci-dessous. Les montants ne compteront "
          'plus dans la situation de cet élève ni dans les rapports.',
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(paymentsRepositoryProvider)
          .cancelInvoice(
            invoiceNumber: invoiceNumber,
            cancelledBy: me.fullName,
            reason: reason,
          );
      ref.invalidate(historyProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(unpaidReportProvider);
      if (context.mounted) _snack(context, 'Facture annulée.');
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final filter = ref.watch(historyFilterProvider);
    final notifier = ref.read(historyFilterProvider.notifier);
    final me = ref.watch(authProvider);
    final canCancel = me != null;

    Future<void> pick({required bool from}) async {
      final current = from ? filter.from : filter.to;
      final picked = await showDatePicker(
        context: context,
        initialDate: current ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      from ? notifier.setFrom(picked) : notifier.setTo(picked);
    }

    return PageScaffold(
      title: 'Historique des paiements',
      subtitle:
          'Toutes les factures émises, de la plus récente à la plus ancienne',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(historyProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Actualiser'),
        ),
      ],
      child: ListView(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 340,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Nom, matricule ou n° de facture',
                  ),
                  onChanged: notifier.setQuery,
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(
                  filter.from == null
                      ? 'Du : début'
                      : 'Du : ${formatDate(filter.from!)}',
                ),
                onPressed: () => pick(from: true),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(
                  filter.to == null
                      ? 'Au : aujourd\'hui'
                      : 'Au : ${formatDate(filter.to!)}',
                ),
                onPressed: () => pick(from: false),
              ),
              if (filter.from != null || filter.to != null)
                TextButton(
                  onPressed: notifier.clearDates,
                  child: const Text('Toutes les dates'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          AsyncValueView(
            value: history,
            data: (invoices) {
              if (invoices.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Aucun paiement ne correspond à cette recherche.',
                    ),
                  ),
                );
              }
              final total = invoices.fold<int>(0, (s, i) => s + i.total);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _Chip(
                        icon: Icons.receipt_long_outlined,
                        text: '${invoices.length} facture(s)',
                      ),
                      _Chip(
                        icon: Icons.account_balance_wallet_outlined,
                        text: 'Total encaissé : ${formatMontant(total)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: HScrollTable(
                      child: DataTable(
                        dataRowMinHeight: 56,
                        dataRowMaxHeight: 72,
                        columns: const [
                          DataColumn(label: Text('N° facture')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Élève')),
                          DataColumn(label: Text('Détail')),
                          DataColumn(label: Text('Encaisseur')),
                          DataColumn(label: Text('Montant'), numeric: true),
                          DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (final inv in invoices)
                            DataRow(
                              color: inv.isCancelled
                                  ? WidgetStateProperty.all(
                                      AppColors.danger.withValues(alpha: 0.05),
                                    )
                                  : null,
                              cells: [
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${inv.invoiceNumber}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (inv.isCancelled) ...[
                                        const SizedBox(width: 8),
                                        Tooltip(
                                          message:
                                              'Motif : ${inv.cancellation!.reason}',
                                          child: const CancelledBadge(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${formatDate(inv.datePaiement)}\n${formatTime(inv.createdAt)}',
                                  ),
                                ),
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        inv.fullName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${inv.matricule} - ${inv.classeName}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => context.go(
                                    '/payments?student=${inv.studentId}',
                                  ),
                                ),
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (final l in inv.lines)
                                        Text(
                                          '${l.poste.labelFr} : ${formatMontant(l.montant)}',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                    ],
                                  ),
                                ),
                                DataCell(Text(inv.operateur)),
                                DataCell(
                                  Text(
                                    formatMontant(inv.total),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Voir / imprimer le reçu',
                                        icon: const Icon(Icons.print_outlined),
                                        onPressed: () => context.go(
                                          '/payments/${inv.firstPaymentId}/receipt?back=history',
                                        ),
                                      ),
                                      if (canCancel && !inv.isCancelled)
                                        IconButton(
                                          tooltip: 'Annuler cette facture',
                                          icon: const Icon(
                                            Icons.cancel_outlined,
                                            color: AppColors.danger,
                                          ),
                                          onPressed: () => _cancel(
                                            context,
                                            ref,
                                            invoiceNumber: inv.invoiceNumber,
                                            studentName: inv.fullName,
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
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.navy),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}
