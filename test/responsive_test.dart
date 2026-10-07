import 'dart:io';

import 'package:cosbimp_scolarite/app.dart';
import 'package:cosbimp_scolarite/core/router/app_router.dart';
import 'package:cosbimp_scolarite/models/app_user.dart';
import 'package:cosbimp_scolarite/models/backup_entry.dart';
import 'package:cosbimp_scolarite/providers/backup_providers.dart';
import 'package:cosbimp_scolarite/models/classe.dart';
import 'package:cosbimp_scolarite/models/invoice_summary.dart';
import 'package:cosbimp_scolarite/models/payment.dart';
import 'package:cosbimp_scolarite/models/payment_situation.dart';
import 'package:cosbimp_scolarite/models/school_year.dart';
import 'package:cosbimp_scolarite/models/student.dart';
import 'package:cosbimp_scolarite/models/tariff.dart';
import 'package:cosbimp_scolarite/providers/auth_provider.dart';
import 'package:cosbimp_scolarite/providers/data_providers.dart';
import 'package:cosbimp_scolarite/providers/db_providers.dart';
import 'package:cosbimp_scolarite/providers/sync_provider.dart';
import 'package:cosbimp_scolarite/repositories/reports_repository.dart';
import 'package:flutter/material.dart' show ListView;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Scrollable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads real fonts so text widths match the app (the default test font is
/// far wider and would report overflows that do not exist).
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

final _classe = const Classe(
  id: 1,
  name: 'Cours Élémentaire Deux',
  section: Section.francophone,
  niveau: Niveau.primaire,
  displayOrder: 1,
);

StudentWithClasse _student(int i) => StudentWithClasse(
  student: Student(
    id: i,
    matricule: '26MP${i.toString().padLeft(3, '0')}',
    fullName: 'NKOULOU ESSAME YACINTHE LUDOVIC $i',
    classeId: 1,
    schoolYearId: 1,
    dateInscription: DateTime.utc(2026, 9, 19),
  ),
  classeName: 'Cours Élémentaire Deux',
  section: 'FRANCOPHONE',
  niveau: 'PRIMAIRE',
  schoolYearLabel: '2026-2027',
);

final _situation = StudentSituation(
  postes: [
    const PosteSituation(
      poste: Poste.inscription,
      montantDu: 17500,
      montantPaye: 17500,
    ),
    PosteSituation(
      poste: Poste.tranche1,
      montantDu: 40000,
      montantPaye: 12500,
      dateLimite: DateTime.utc(2026, 9, 30),
    ),
    PosteSituation(
      poste: Poste.tranche2,
      montantDu: 40000,
      montantPaye: 0,
      dateLimite: DateTime.utc(2026, 11, 30),
    ),
    PosteSituation(
      poste: Poste.tranche3,
      montantDu: 20000,
      montantPaye: 0,
      dateLimite: DateTime.utc(2027, 1, 31),
    ),
  ],
);

List<Payment> _payments() => [
  for (final (i, p) in [Poste.inscription, Poste.tranche1].indexed)
    Payment(
      id: i + 1,
      invoiceNumber: 29994,
      studentId: 1,
      poste: p,
      montantPaye: 20000,
      datePaiement: DateTime.utc(2026, 9, 19),
      createdAt: DateTime.utc(2026, 9, 19, 12),
      operateur: 'Marie Claire',
    ),
];

final _baseOverrides = [
  dbReadyProvider.overrideWith((ref) async {}),
  dataSyncProvider.overrideWith((ref) {}),
  logoBytesProvider.overrideWith((ref) async => null),
  classesProvider.overrideWith((ref) async => [_classe]),
  schoolYearsProvider.overrideWith(
    (ref) async => [
      const SchoolYear(id: 1, label: '2026-2027', isActive: true),
      const SchoolYear(id: 2, label: '2025-2026', isActive: false),
    ],
  ),
  activeSchoolYearProvider.overrideWith(
    (ref) async => const SchoolYear(id: 1, label: '2026-2027', isActive: true),
  ),
  tariffsProvider.overrideWith(
    (ref, id) async => [
      for (final n in Niveau.values)
        for (final p in Poste.values)
          Tariff(
            id: n.index * 4 + p.index,
            schoolYearId: 1,
            niveau: n,
            poste: p,
            montant: 40000,
            dateLimite: DateTime.utc(2026, 9, 30),
          ),
    ],
  ),
  studentsProvider.overrideWith(
    (ref) async => [for (var i = 1; i <= 25; i++) _student(i)],
  ),
  studentProvider.overrideWith((ref, id) async => _student(1)),
  classeHeadcountsProvider.overrideWith(
    (ref) async => [ClasseHeadcount(classe: _classe, total: 25)],
  ),
  studentClassHistoryProvider.overrideWith(
    (ref, fullName) async => [_student(1)],
  ),
  studentSearchProvider.overrideWith(
    (ref, q) async => [for (var i = 1; i <= 8; i++) _student(i)],
  ),
  studentSituationProvider.overrideWith((ref, id) async => _situation),
  studentInvoicesProvider.overrideWith(
    (ref, id) async => Invoice.group(_payments()),
  ),
  historyProvider.overrideWith(
    (ref) async => [
      for (var i = 0; i < 12; i++)
        InvoiceSummary(
          invoiceNumber: 29994 + i,
          firstPaymentId: i + 1,
          studentId: 1,
          matricule: '26MP001',
          fullName: 'NKOULOU ESSAME YACINTHE LUDOVIC',
          classeName: 'Cours Élémentaire Deux',
          datePaiement: DateTime.utc(2026, 9, 19),
          createdAt: DateTime.utc(2026, 9, 19, 12),
          operateur: 'Marie Claire',
          lines: const [
            PosteAllocation(Poste.inscription, 17500),
            PosteAllocation(Poste.tranche1, 22500),
            PosteAllocation(Poste.tranche2, 6000),
          ],
        ),
    ],
  ),
  dashboardStatsProvider.overrideWith(
    (ref) async => const DashboardStats(
      studentCount: 120,
      paymentsToday: 8,
      totalToday: 450000,
      cancellationsToday: 1,
    ),
  ),
  unpaidReportProvider.overrideWith(
    (ref) async => [
      for (var i = 0; i < 20; i++)
        UnpaidRow(
          studentId: i + 1,
          matricule: '26MP001',
          fullName: 'NKOULOU ESSAME YACINTHE LUDOVIC',
          classeName: 'Cours Élémentaire Deux',
          section: 'FRANCOPHONE',
          niveau: 'PRIMAIRE',
          montantDu: 40000,
          montantPaye: 12500,
        ),
    ],
  ),
];

const _paths = [
  '/dashboard',
  '/students',
  '/students/new',
  '/students/1/edit',
  '/students/1',
  '/classes',
  '/payments',
  '/payments?student=1',
  '/history',
  '/reports/unpaid',
  '/tariffs',
  '/settings/school-years',
];

const _sizes = [
  Size(1920, 1080),
  Size(1366, 768),
  Size(1024, 640),
  Size(800, 600),
  Size(700, 500),
  Size(560, 480),
];

void main() {
  setUpAll(_loadFonts);
  authTests();

  for (final size in _sizes) {
    for (final path in _paths) {
      testWidgets('$path @ ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: _overrides(_admin),
            child: const CosbimpApp(),
          ),
        );
        appRouter.go(path);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

const _admin = AppUser(
  id: 1,
  username: 'admin',
  fullName: 'Administrateur Principal',
  role: UserRole.admin,
);

const _direction = AppUser(
  id: 3,
  username: 'directrice',
  fullName: 'Direction',
  role: UserRole.superAdmin,
);

const _caissier = AppUser(
  id: 2,
  username: 'marie',
  fullName: 'Marie Claire NGONO',
  role: UserRole.caissier,
);

class _FakeAuth extends AuthNotifier {
  final AppUser? initial;
  _FakeAuth(this.initial);

  @override
  AppUser? build() => initial;
}

/// Every provider faked, plus the given logged-in user (null = logged out).
// ignore: strict_top_level_inference
_overrides(AppUser? user, {bool isServer = true}) => [
  ..._baseOverrides,
  authProvider.overrideWith(() => _FakeAuth(user)),
  usersProvider.overrideWith((ref) async => [_admin, _caissier]),
  defaultAdminHintProvider.overrideWith((ref) async => true),
  backupLogProvider.overrideWith(
    (ref) async => [
      BackupEntry(
        id: 2,
        createdAt: DateTime.now(),
        fileName: 'cosbimp_2026-09-19_190000.sql.gz',
        sizeBytes: 4300000,
        ok: true,
        source: 'planifiee',
        copiedTo: 'E:/Sauvegardes COSBIMP avec un nom de dossier assez long',
      ),
      BackupEntry(
        id: 1,
        createdAt: DateTime.now().subtract(const Duration(hours: 6)),
        fileName: 'cosbimp_2026-09-19_123000.sql.gz',
        sizeBytes: 0,
        ok: false,
        source: 'manuelle',
        message: 'mariadb-dump a echoue',
      ),
    ],
  ),
  backupCopyDirProvider.overrideWith((ref) async => 'E:/Sauvegardes COSBIMP'),
  isServerPcProvider.overrideWith((ref) => isServer),
];

void authTests() {
  for (final size in _sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('connexion @ $label', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(overrides: _overrides(null), child: const CosbimpApp()),
      );
      appRouter.go('/dashboard');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Se connecter'), findsOneWidget);
      expect(find.text('Tableau de bord'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('changement de mot de passe obligatoire @ $label', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(_admin.copyWith(mustChangePassword: true)),
          child: const CosbimpApp(),
        ),
      );
      appRouter.go('/dashboard');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Choisissez votre mot de passe'), findsOneWidget);
      expect(find.text('Tableau de bord'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final isServer in [true, false]) {
      testWidgets(
        'paramètres direction (${isServer ? "serveur" : "poste"}) : utilisateurs et sauvegardes @ $label',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              overrides: _overrides(_direction, isServer: isServer),
              child: const CosbimpApp(),
            ),
          );
          appRouter.go('/settings/school-years');
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          await tester.scrollUntilVisible(
            find.text('Dernières sauvegardes'),
            300,
            scrollable: find
                .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pump();
          expect(find.text('Sauvegarder maintenant'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('caissier : pages admin refusées @ $label', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(_caissier),
          child: const CosbimpApp(),
        ),
      );
      for (final path in [
        '/tariffs',
        '/settings/school-years',
        '/students/1/edit',
      ]) {
        appRouter.go(path);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(
          find.text('Accès réservé aux administrateurs'),
          findsOneWidget,
          reason: path,
        );
      }
      // The read-only fiche stays open to a caissier even though editing
      // it is not.
      appRouter.go('/students/1');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Accès réservé aux administrateurs'), findsNothing);

      appRouter.go('/history');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Accès réservé aux administrateurs'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
