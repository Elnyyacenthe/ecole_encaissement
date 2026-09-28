import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/classe.dart';
import '../models/invoice_summary.dart';
import '../models/payment.dart';
import '../models/payment_situation.dart';
import '../models/receipt_data.dart';
import '../models/school_year.dart';
import '../models/student.dart';
import '../models/tariff.dart';
import '../repositories/reports_repository.dart';
import 'db_providers.dart';

/// Logo saved in the database; null until one is chosen (or while the
/// database is still connecting), in which case bundled files are used.
final logoBytesProvider = FutureProvider<Uint8List?>((ref) async {
  if (!ref.watch(dbReadyProvider).hasValue) return null;
  return ref.watch(settingsRepositoryProvider).loadLogo();
});

final classesProvider = FutureProvider<List<Classe>>((ref) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(classesRepositoryProvider).all();
});

final schoolYearsProvider = FutureProvider<List<SchoolYear>>((ref) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(schoolYearsRepositoryProvider).all();
});

final activeSchoolYearProvider = FutureProvider<SchoolYear?>((ref) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(schoolYearsRepositoryProvider).active();
});

final tariffsProvider = FutureProvider.family<List<Tariff>, int>((
  ref,
  yearId,
) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(tariffsRepositoryProvider).forYear(yearId);
});

// --- Students -------------------------------------------------------------

class StudentFilter {
  final String query;
  final int? classeId;
  final bool includeCancelled;
  const StudentFilter({
    this.query = '',
    this.classeId,
    this.includeCancelled = false,
  });
}

class StudentFilterNotifier extends Notifier<StudentFilter> {
  @override
  StudentFilter build() => const StudentFilter();

  void setQuery(String query) => state = StudentFilter(
    query: query,
    classeId: state.classeId,
    includeCancelled: state.includeCancelled,
  );

  void setClasse(int? classeId) => state = StudentFilter(
    query: state.query,
    classeId: classeId,
    includeCancelled: state.includeCancelled,
  );

  void setIncludeCancelled(bool value) => state = StudentFilter(
    query: state.query,
    classeId: state.classeId,
    includeCancelled: value,
  );
}

final studentFilterProvider =
    NotifierProvider<StudentFilterNotifier, StudentFilter>(
      StudentFilterNotifier.new,
    );

/// Students of the active school year matching the current filter.
final studentsProvider = FutureProvider<List<StudentWithClasse>>((ref) async {
  await ref.watch(dbReadyProvider.future);
  final filter = ref.watch(studentFilterProvider);
  final year = await ref.watch(activeSchoolYearProvider.future);
  return ref
      .watch(studentsRepositoryProvider)
      .search(
        query: filter.query,
        classeId: filter.classeId,
        schoolYearId: year?.id,
        includeCancelled: filter.includeCancelled,
      );
});

final studentProvider = FutureProvider.family<StudentWithClasse?, int>((
  ref,
  id,
) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(studentsRepositoryProvider).getById(id);
});

/// Live search used by the cashier screen (all years, any filter ignored).
final studentSearchProvider =
    FutureProvider.family<List<StudentWithClasse>, String>((ref, query) async {
      await ref.watch(dbReadyProvider.future);
      if (query.trim().isEmpty) return const [];
      return ref
          .watch(studentsRepositoryProvider)
          .search(query: query, limit: 20);
    });

// --- Payments -------------------------------------------------------------

final studentSituationProvider = FutureProvider.family<StudentSituation, int>((
  ref,
  studentId,
) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(paymentsRepositoryProvider).situationFor(studentId);
});

final studentInvoicesProvider = FutureProvider.family<List<Invoice>, int>((
  ref,
  studentId,
) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(paymentsRepositoryProvider).invoicesForStudent(studentId);
});

class HistoryFilter {
  final String query;
  final DateTime? from;
  final DateTime? to;
  const HistoryFilter({this.query = '', this.from, this.to});
}

class HistoryFilterNotifier extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => const HistoryFilter();

  void setQuery(String query) =>
      state = HistoryFilter(query: query, from: state.from, to: state.to);
  void setFrom(DateTime? from) =>
      state = HistoryFilter(query: state.query, from: from, to: state.to);
  void setTo(DateTime? to) =>
      state = HistoryFilter(query: state.query, from: state.from, to: to);
  void clearDates() => state = HistoryFilter(query: state.query);
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilter>(
      HistoryFilterNotifier.new,
    );

final historyProvider = FutureProvider<List<InvoiceSummary>>((ref) async {
  await ref.watch(dbReadyProvider.future);
  final f = ref.watch(historyFilterProvider);
  return ref
      .watch(paymentsRepositoryProvider)
      .history(query: f.query, from: f.from, to: f.to);
});

final receiptDataProvider = FutureProvider.family<ReceiptData?, int>((
  ref,
  paymentId,
) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(paymentsRepositoryProvider).receiptData(paymentId);
});

final dashboardStatsProvider = FutureProvider<DashboardStats?>((ref) async {
  await ref.watch(dbReadyProvider.future);
  final year = await ref.watch(activeSchoolYearProvider.future);
  if (year == null) return null;
  return ref.watch(reportsRepositoryProvider).dashboard(year.id);
});

// --- Unpaid report --------------------------------------------------------

class UnpaidFilter {
  final Poste poste;
  final DateTime? asOf;
  const UnpaidFilter({this.poste = Poste.tranche1, this.asOf});
}

class UnpaidFilterNotifier extends Notifier<UnpaidFilter> {
  @override
  UnpaidFilter build() => const UnpaidFilter();

  void setPoste(Poste poste) =>
      state = UnpaidFilter(poste: poste, asOf: state.asOf);
  void setAsOf(DateTime? asOf) =>
      state = UnpaidFilter(poste: state.poste, asOf: asOf);
}

final unpaidFilterProvider =
    NotifierProvider<UnpaidFilterNotifier, UnpaidFilter>(
      UnpaidFilterNotifier.new,
    );

final unpaidReportProvider = FutureProvider<List<UnpaidRow>>((ref) async {
  await ref.watch(dbReadyProvider.future);
  final filter = ref.watch(unpaidFilterProvider);
  final year = await ref.watch(activeSchoolYearProvider.future);
  if (year == null) return const [];
  return ref
      .watch(reportsRepositoryProvider)
      .unpaid(schoolYearId: year.id, poste: filter.poste, asOf: filter.asOf);
});

// --- Users ----------------------------------------------------------------

final usersProvider = FutureProvider<List<AppUser>>((ref) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(usersRepositoryProvider).list();
});

/// True while the built-in administrator still has its initial password.
final defaultAdminHintProvider = FutureProvider<bool>((ref) async {
  await ref.watch(dbReadyProvider.future);
  return ref.watch(usersRepositoryProvider).usesDefaultAdminPassword();
});
