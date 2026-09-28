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
import '../../models/payment_situation.dart';
import '../../models/student.dart';
import '../../models/tariff.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';
import 'situation_financiere_widget.dart';

class EncaissementScreen extends ConsumerStatefulWidget {
  final int? initialStudentId;
  const EncaissementScreen({super.key, this.initialStudentId});

  @override
  ConsumerState<EncaissementScreen> createState() => _EncaissementScreenState();
}

class _EncaissementScreenState extends ConsumerState<EncaissementScreen> {
  final _search = TextEditingController();
  final _montant = TextEditingController();
  String _query = '';
  int? _studentId;
  Poste? _poste;
  DateTime _date = DateTime.now();
  bool _saving = false;
  int? _lastPaymentId;

  @override
  void initState() {
    super.initState();
    final id = widget.initialStudentId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _select(id));
    }
  }

  @override
  void didUpdateWidget(covariant EncaissementScreen old) {
    super.didUpdateWidget(old);
    final id = widget.initialStudentId;
    if (id != null && id != old.initialStudentId) _select(id);
  }

  @override
  void dispose() {
    _search.dispose();
    _montant.dispose();
    super.dispose();
  }

  /// Selects a student and pre-fills the form with the first unpaid poste
  /// and its remaining amount.
  Future<void> _select(int studentId) async {
    ref.invalidate(studentSituationProvider(studentId));
    final situation = await ref.read(
      studentSituationProvider(studentId).future,
    );
    if (!mounted) return;
    final firstOpen = situation.postes.where((p) => !p.estSolde).firstOrNull;
    setState(() {
      _studentId = studentId;
      _poste = firstOpen?.poste;
      _montant.text = firstOpen == null ? '' : '${firstOpen.resteAPayer}';
      _lastPaymentId = null;
      _date = DateTime.now();
    });
  }

  Future<void> _save() async {
    final studentId = _studentId;
    final poste = _poste;
    final montant = parseMontant(_montant.text);
    if (studentId == null || poste == null) return;
    if (montant == null || montant <= 0) {
      _snack('Saisissez un montant valide.');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(paymentsRepositoryProvider)
          .record(
            studentId: studentId,
            poste: poste,
            montant: montant,
            datePaiement: _date,
            operateur: ref.read(authProvider)?.fullName ?? '',
          );
      ref.invalidate(studentSituationProvider(studentId));
      ref.invalidate(studentInvoicesProvider(studentId));
      ref.invalidate(historyProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(unpaidReportProvider);
      final situation = await ref.read(
        studentSituationProvider(studentId).future,
      );
      if (!mounted) return;
      final next = situation.postes.where((p) => !p.estSolde).firstOrNull;
      setState(() {
        _lastPaymentId = id;
        _poste = next?.poste;
        _montant.text = next == null ? '' : '${next.resteAPayer}';
      });
      _snack('Paiement enregistré.');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _cancelInvoice({
    required int invoiceNumber,
    required String studentName,
  }) async {
    final me = ref.read(authProvider);
    if (me == null) return;
    final reason = await showCancelReasonDialog(
      context,
      title: 'Annuler la facture n°$invoiceNumber ($studentName)',
      message:
          "Cette facture restera visible, marquée ANNULÉE, avec le motif "
          'ci-dessous. Les montants ne compteront plus dans la situation de '
          'cet élève ni dans les rapports.',
    );
    if (reason == null || !mounted) return;
    try {
      await ref
          .read(paymentsRepositoryProvider)
          .cancelInvoice(
            invoiceNumber: invoiceNumber,
            cancelledBy: me.fullName,
            reason: reason,
          );
      final studentId = _studentId;
      if (studentId != null) {
        ref.invalidate(studentSituationProvider(studentId));
        ref.invalidate(studentInvoicesProvider(studentId));
      }
      ref.invalidate(historyProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(unpaidReportProvider);
      if (mounted) _snack('Facture annulée.');
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Encaissement',
      subtitle:
          'Recherchez un élève, enregistrez le paiement et imprimez le reçu',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = _studentId == null
              ? const Center(
                  child: Text('Recherchez et sélectionnez un élève.'),
                )
              : _buildPayment(_studentId!);

          // Narrow window: search on top, payment below (instead of side by side).
          if (constraints.maxWidth < 900) {
            return Column(
              children: [
                SizedBox(height: 230, child: Card(child: _buildSearch())),
                const SizedBox(height: 12),
                Expanded(child: content),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 340, child: Card(child: _buildSearch())),
              const SizedBox(width: 20),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearch() {
    final results = ref.watch(studentSearchProvider(_query));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Nom ou matricule',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: results.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e),
            data: (list) => ListView(
              children: [
                for (final s in list)
                  ListTile(
                    selected: s.student.id == _studentId,
                    title: Text(s.student.fullName),
                    subtitle: Text('${s.student.matricule} - ${s.classeName}'),
                    onTap: () => _select(s.student.id),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPayment(int studentId) {
    final student = ref.watch(studentProvider(studentId));
    final situation = ref.watch(studentSituationProvider(studentId));
    final history = ref.watch(studentInvoicesProvider(studentId));

    return AsyncValueView(
      value: student,
      data: (s) {
        if (s == null) return const Center(child: Text('Élève introuvable.'));
        return ListView(
          children: [
            _studentHeader(s),
            const SizedBox(height: 16),
            if (s.student.isCancelled)
              Card(
                color: AppColors.danger.withValues(alpha: 0.06),
                child: ListTile(
                  leading: const Icon(
                    Icons.person_off_outlined,
                    color: AppColors.danger,
                  ),
                  title: const Text(
                    'Inscription annulée',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Motif : ${s.student.cancellation!.reason}\n'
                    'Aucun encaissement ne peut être enregistré pour cet élève.',
                  ),
                ),
              )
            else
              _paymentForm(situation.value),
            if (_lastPaymentId != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Paiement enregistré'),
                  trailing: FilledButton.icon(
                    onPressed: () =>
                        context.go('/payments/$_lastPaymentId/receipt'),
                    icon: const Icon(Icons.print),
                    label: const Text('Imprimer le reçu'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            AsyncValueView(
              value: situation,
              data: (sit) => SituationFinanciereWidget(situation: sit),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.history,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Historique des paiements de cet élève',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => context.go('/history'),
                  icon: const Icon(Icons.list_alt_outlined, size: 18),
                  label: const Text('Historique complet'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AsyncValueView(
              value: history,
              data: (invoices) {
                if (invoices.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Aucun paiement enregistré pour cet élève.'),
                    ),
                  );
                }
                return Card(
                  child: HScrollTable(
                    child: DataTable(
                      dataRowMinHeight: 56,
                      dataRowMaxHeight: 72,
                      columns: const [
                        DataColumn(label: Text('N° facture')),
                        DataColumn(label: Text('Date')),
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
                              DataCell(Text(formatDate(inv.datePaiement))),
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final l in inv.lines)
                                      Text(
                                        '${l.poste.labelFr} : ${formatMontant(l.montantPaye)}',
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
                                        '/payments/${inv.firstPaymentId}/receipt',
                                      ),
                                    ),
                                    if (ref.watch(authProvider) != null &&
                                        !inv.isCancelled)
                                      IconButton(
                                        tooltip: 'Annuler cette facture',
                                        icon: const Icon(
                                          Icons.cancel_outlined,
                                          color: AppColors.danger,
                                        ),
                                        onPressed: () => _cancelInvoice(
                                          invoiceNumber: inv.invoiceNumber,
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
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _studentHeader(StudentWithClasse s) => Card(
    child: ListTile(
      leading: const Icon(Icons.person_outline, size: 32),
      title: Text(
        s.student.fullName,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        'Matricule ${s.student.matricule} - ${s.classeName} - '
        '${Niveau.fromDb(s.niveau).label} - ${Section.fromDb(s.section).label}',
      ),
    ),
  );

  Widget _paymentForm(StudentSituation? situation) {
    final postes = situation?.postes;
    final open =
        postes?.where((p) => !p.estSolde).toList() ?? const <PosteSituation>[];
    final allPaid = postes != null && postes.isNotEmpty && open.isEmpty;

    if (allPaid) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.verified_outlined),
          title: Text("Tous les postes de l'année sont soldés pour cet élève."),
        ),
      );
    }
    final montant = parseMontant(_montant.text);
    final split = (situation != null && montant != null && montant > 0)
        ? situation.allocate(montant, startWith: _poste)
        : null;
    final tooHigh = split != null && split.leftover > 0;
    final canSave = !_saving && split != null && !tooHigh;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<Poste>(
                initialValue: open.any((p) => p.poste == _poste)
                    ? _poste
                    : null,
                decoration: const InputDecoration(labelText: 'Commencer par'),
                items: [
                  for (final p in open)
                    DropdownMenuItem(
                      value: p.poste,
                      child: Text(p.poste.labelFr),
                    ),
                ],
                onChanged: (p) {
                  setState(() => _poste = p);
                  final match = open.where((x) => x.poste == p).firstOrNull;
                  if (match != null) _montant.text = '${match.resteAPayer}';
                },
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _montant,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Montant versé (FCFA)',
                  helperText: situation == null
                      ? null
                      : 'Maximum : ${formatMontant(situation.totalReste)}',
                ),
              ),
            ),
            SizedBox(
              width: 160,
              child: InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date de paiement',
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(formatDate(_date)),
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Encaisseur (nom de la personne connectée)',
                  prefixIcon: Icon(Icons.badge_outlined, size: 18),
                ),
                child: Text(
                  ref.watch(authProvider)?.fullName ?? '-',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: canSave ? _save : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer le paiement'),
            ),
            if (split != null)
              SizedBox(
                width: double.infinity,
                child: _allocationPreview(split, situation!),
              ),
          ],
        ),
      ),
    );
  }

  /// Shows how the typed amount will be spread over the postes.
  Widget _allocationPreview(
    ({List<PosteAllocation> parts, int leftover}) split,
    StudentSituation situation,
  ) {
    final over = split.leftover > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: over ? const Color(0xFFFDECEA) : const Color(0xFFEDF4FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (over)
            Text(
              'Ce montant dépasse de ${formatMontant(split.leftover)} le total restant '
              "à payer pour l'année (${formatMontant(situation.totalReste)}).",
              style: const TextStyle(color: Color(0xFFB3261E)),
            )
          else ...[
            const Text(
              'Répartition du versement',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (final p in split.parts)
              Text(
                '${p.poste.labelFr} : ${formatMontant(p.montant)}'
                '${p.montant == situation.forPoste(p.poste).resteAPayer ? ' (soldé)' : ' (reste ${formatMontant(situation.forPoste(p.poste).resteAPayer - p.montant)})'}',
              ),
          ],
        ],
      ),
    );
  }
}
