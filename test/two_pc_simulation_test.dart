// ignore_for_file: avoid_print
// Simulation de deux PC : chacun a sa propre connexion et son propre état
// (ProviderContainer), comme deux machines distinctes branchées sur le même
// serveur. Nécessite une base MariaDB de test : voir la variable SIM_PORT.
//
//   SIM_PORT=3399 flutter test test/two_pc_simulation_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:cosbimp_scolarite/core/db/db_auto_connector.dart';
import 'package:cosbimp_scolarite/core/db/db_bootstrap.dart';
import 'package:cosbimp_scolarite/core/db/db_config.dart';
import 'package:cosbimp_scolarite/core/db/db_settings_repository.dart';
import 'package:cosbimp_scolarite/core/db/mysql_connection_service.dart';
import 'package:cosbimp_scolarite/models/tariff.dart';
import 'package:cosbimp_scolarite/providers/data_providers.dart';
import 'package:cosbimp_scolarite/providers/db_providers.dart';
import 'package:cosbimp_scolarite/providers/sync_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _simPort = Platform.environment['SIM_PORT'];
final _port = int.parse(_simPort ?? '3399');
final _skip = _simPort == null
    ? 'Simulation à deux PC : nécessite une base MariaDB de test (variable SIM_PORT)'
    : null;

/// One simulated PC: its own DB connection and its own provider state.
ProviderContainer _pc() {
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      dbReadyProvider.overrideWith((ref) async {
        final db = ref.watch(dbServiceProvider);
        await db.connect(
          DbConfig.defaults.copyWith(host: '127.0.0.1', port: _port),
        );
        await bootstrapDatabase(db);
      }),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _wait(int seconds) =>
    Future<void>.delayed(Duration(seconds: seconds));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'deux PC : mêmes données, mises à jour automatiques, aucun doublon',
    () async {
      SharedPreferences.setMockInitialValues({});
      final pc1 = _pc(); // "serveur"
      final pc2 = _pc(); // "poste"

      await pc1.read(dbReadyProvider.future);
      await pc2.read(dbReadyProvider.future);
      expect(
        pc1.read(dbServiceProvider),
        isNot(same(pc2.read(dbServiceProvider))),
      );

      // Le PC2 affiche déjà des écrans (l'état est mis en cache) ...
      pc2.read(dataSyncProvider);
      pc1.read(dataSyncProvider);
      final year = (await pc2.read(activeSchoolYearProvider.future))!;
      final classes = await pc2.read(classesProvider.future);
      expect((await pc2.read(studentsProvider.future)).length, 0);
      expect((await pc2.read(historyProvider.future)).length, 0);
      expect((await pc2.read(dashboardStatsProvider.future))!.studentCount, 0);
      await _wait(4); // laisse la synchro prendre sa référence

      // ... 1) le PC1 inscrit un élève : le PC2 le voit sans rien faire.
      final studentsRepo1 = pc1.read(studentsRepositoryProvider);
      final id = await studentsRepo1.create(
        fullName: 'ELEVE CREE SUR PC1',
        classeId: classes.first.id,
        schoolYearId: year.id,
        dateInscription: DateTime.now(),
      );
      await _wait(5);
      final seen = await pc2.read(studentsProvider.future);
      expect(
        seen.map((s) => s.student.fullName),
        contains('ELEVE CREE SUR PC1'),
      );
      expect((await pc2.read(dashboardStatsProvider.future))!.studentCount, 1);
      print(
        '1) PC2 voit l\'élève créé sur PC1 : ${seen.first.student.matricule}',
      );

      // 2) le PC1 encaisse 80 000 F (répartis sur 3 postes) : le PC2 voit la facture.
      await pc1
          .read(paymentsRepositoryProvider)
          .record(
            studentId: id,
            poste: Poste.inscription,
            montant: 80000,
            datePaiement: DateTime.now(),
            operateur: 'Caissier PC1',
          );
      await _wait(5);
      final history = await pc2.read(historyProvider.future);
      expect(history.length, 1);
      expect(history.first.total, 80000);
      expect(history.first.lines.length, 3);
      final sit = await pc2.read(studentSituationProvider(id).future);
      expect(sit.totalPaye, 80000);
      print(
        '2) PC2 voit la facture n°${history.first.invoiceNumber} de ${history.first.total} F',
      );

      // 3) les deux PC créent des élèves et encaissent EN MÊME TEMPS.
      final repo2 = pc2.read(studentsRepositoryProvider);
      final created = await Future.wait([
        for (var i = 0; i < 8; i++)
          studentsRepo1.create(
            fullName: 'PC1-$i',
            classeId: classes.first.id,
            schoolYearId: year.id,
            dateInscription: DateTime.now(),
          ),
        for (var i = 0; i < 8; i++)
          repo2.create(
            fullName: 'PC2-$i',
            classeId: classes.first.id,
            schoolYearId: year.id,
            dateInscription: DateTime.now(),
          ),
      ]);
      final all = await pc1
          .read(studentsRepositoryProvider)
          .search(schoolYearId: year.id);
      final matricules = all.map((s) => s.student.matricule).toList()..sort();
      expect(
        matricules.toSet().length,
        matricules.length,
        reason: 'matricule en double',
      );
      expect(matricules.length, 17);
      expect(matricules.first, '26MP001');
      expect(matricules.last, '26MP017');
      print(
        '3) 16 élèves créés en même temps par 2 PC : ${matricules.first}..${matricules.last}, aucun doublon ni trou',
      );

      // Paiements simultanés sur le même élève depuis les deux PC : jamais plus que le dû.
      final target = created.first;
      final pays = await Future.wait([
        for (var i = 0; i < 6; i++)
          (i.isEven ? pc1 : pc2)
              .read(paymentsRepositoryProvider)
              .record(
                studentId: target,
                poste: Poste.inscription,
                montant: 30000,
                datePaiement: DateTime.now(),
                operateur: 'Simul',
              )
              .then((_) => true, onError: (_) => false),
      ]);
      final accepted = pays.where((ok) => ok).length;
      final tSit = await pc1
          .read(paymentsRepositoryProvider)
          .situationFor(target);
      expect(tSit.totalPaye <= tSit.totalDu, isTrue);
      expect(tSit.totalPaye, accepted * 30000);
      final invoices = await pc2.read(paymentsRepositoryProvider).history();
      final numbers = invoices.map((i) => i.invoiceNumber).toList();
      expect(
        numbers.toSet().length,
        numbers.length,
        reason: 'n° de facture en double',
      );
      print(
        '4) 6 encaissements simultanés (2 PC) sur le même élève : $accepted acceptés, total payé ${tSit.totalPaye} <= dû ${tSit.totalDu}; factures uniques',
      );

      // 5) le logo choisi sur le PC1 apparaît sur le PC2.
      expect(await pc2.read(logoBytesProvider.future), isNull);
      await pc1
          .read(settingsRepositoryProvider)
          .saveLogo(
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5]),
          );
      await _wait(5);
      expect((await pc2.read(logoBytesProvider.future))?.length, 9);
      print('5) le logo enregistré sur PC1 est visible sur PC2');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: _skip,
  );

  test(
    'un poste retrouve le serveur sur le réseau (adresse LAN, pas 127.0.0.1)',
    () async {
      final db = MySqlConnectionService();
      final connector = DbAutoConnector(
        db: db,
        settings: DbSettingsRepository(),
        onStatus: (_) {},
      );
      final found = await connector.scanLan(3307); // serveur réel de ce PC
      print('6) hôtes qui répondent sur le port 3307 du réseau : $found');
      final lan = found.where((h) => !h.startsWith('127.')).toList();
      expect(
        lan,
        isNotEmpty,
        reason: 'le serveur doit être visible depuis le réseau',
      );

      // Connexion par l'adresse réseau, comme le ferait un autre PC (lecture seule).
      await db.probe(DbConfig.defaults.copyWith(host: lan.first));
      print(
        '7) connexion acceptée par ${lan.first}:3307 avec les identifiants intégrés',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: _skip,
  );
}
