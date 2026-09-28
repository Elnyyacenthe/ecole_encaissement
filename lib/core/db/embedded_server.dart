import 'dart:async';
import 'dart:io';

import 'package:mysql1/mysql1.dart';

import 'db_auto_connector.dart';
import 'db_config.dart';

/// Installs and starts the database that ships with the application.
///
/// The "server PC" package contains a `mariadb` folder next to the app; on
/// that PC the first launch initializes the data, registers a Windows
/// service (auto-start, one UAC prompt) and opens the firewall port so the
/// other PCs can connect. Client PCs ship without the folder: this class
/// does nothing there and they find the server over the network.
class EmbeddedServer {
  static const int port = 3307;
  static const String rootPassword = 'CosbimpRoot#2026';
  static const String serviceName = 'COSBIMPDB';
  static const String firewallRule = 'COSBIMP Base de donnees';
  static const String backupTaskName = 'COSBIMP Sauvegarde';

  final void Function(String status) onStatus;
  EmbeddedServer({required this.onStatus});

  /// The bundled MariaDB folder, if this is the server PC's package.
  ///
  /// Only ever the executable's own sibling `mariadb` folder — exactly how
  /// build_release.ps1 lays out COSBIMP-Serveur. Deliberately NOT a search
  /// through parent directories: a Poste build run from inside (or copied
  /// under) the development tree would otherwise "discover" the dev
  /// database several folders up and wrongly start acting as its own
  /// server instead of finding the real one on the network.
  static Directory? locateBundle() {
    final dir = File(Platform.resolvedExecutable).parent;
    final candidate = Directory('${dir.path}${Platform.pathSeparator}mariadb');
    return File('${candidate.path}\\bin\\mariadbd.exe').existsSync()
        ? candidate
        : null;
  }

  Future<void> ensureRunning() async {
    if (!Platform.isWindows) return;
    final bundle = locateBundle();
    if (bundle == null) return; // client PC

    final bin = '${bundle.path}\\bin';
    final programData =
        Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    final root = Directory('$programData\\COSBIMP')
      ..createSync(recursive: true);
    final dataDir = '${root.path}\\data';
    final ini = File('${root.path}\\my.ini');

    if (!Directory('$dataDir\\mysql').existsSync()) {
      onStatus('Installation de la base de données (première utilisation)…');
      final r = await Process.run('$bin\\mariadb-install-db.exe', [
        '--datadir=$dataDir',
        '--port=$port',
        '--password=$rootPassword',
      ]);
      if (r.exitCode != 0) {
        throw DbConnectionException(
          "Installation de la base de données impossible : ${r.stderr}${r.stdout}",
        );
      }
    }

    String fwd(String p) => p.replaceAll('\\', '/');
    ini.writeAsStringSync('''
[mysqld]
basedir=${fwd(bundle.path)}
datadir=${fwd(dataDir)}
port=$port
bind-address=0.0.0.0
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
max_connections=100
innodb_buffer_pool_size=128M
log-error=${fwd(root.path)}/error.log
''');

    final backupScript = File('${bundle.parent.path}\\Sauvegarde.ps1');
    final needsBackupTask =
        backupScript.existsSync() && !await _hasBackupTask();
    if (!await _hasFirewallRule() || !await _hasService() || needsBackupTask) {
      onStatus('Configuration du serveur (réseau et sauvegardes)…');
      await _privilegedSetup(bin, root, ini, backupScript);
    }

    if (!await _isListening()) {
      onStatus('Démarrage de la base de données…');
      await Process.start('$bin\\mariadbd.exe', [
        '--defaults-file=${ini.path}',
      ], mode: ProcessStartMode.detached);
    }
    if (!await _waitListening(const Duration(seconds: 45))) {
      throw DbConnectionException(
        'La base de données n\'a pas démarré (voir ${root.path}\\error.log).',
      );
    }

    onStatus('Préparation de la base de données…');
    await _provision();
  }

  Future<bool> _hasFirewallRule() async {
    final r = await Process.run('netsh', [
      'advfirewall',
      'firewall',
      'show',
      'rule',
      'name=$firewallRule',
    ]);
    return r.exitCode == 0;
  }

  Future<bool> _hasService() async =>
      (await Process.run('sc', ['query', serviceName])).exitCode == 0;

  Future<bool> _hasBackupTask() async =>
      (await Process.run('schtasks', [
        '/Query',
        '/TN',
        backupTaskName,
      ])).exitCode ==
      0;

  /// One UAC prompt: open the firewall port, install the auto-start service
  /// and register the daily backup task. If the user declines, the database
  /// still runs (as a plain process) but only until the PC restarts and only
  /// for this PC; the app then makes its own catch-up backups.
  /// Idempotent: only what is missing is created.
  Future<void> _privilegedSetup(
    String bin,
    Directory root,
    File ini,
    File backupScript,
  ) async {
    final script = File('${root.path}\\setup_service.ps1');
    script.writeAsStringSync(
      r'''
netsh advfirewall firewall show rule name="@@RULE@@" | Out-Null
if ($LASTEXITCODE -ne 0) {
  netsh advfirewall firewall add rule name="@@RULE@@" dir=in action=allow protocol=TCP localport=@@PORT@@ profile=any | Out-Null
}
if (-not (Get-Service -Name @@SVC@@ -ErrorAction SilentlyContinue)) {
  & "@@BIN@@\mariadb-admin.exe" -uroot "-p@@ROOTPW@@" -h127.0.0.1 -P@@PORT@@ shutdown 2>$null
  Start-Sleep -Seconds 3
  & "@@BIN@@\mariadbd.exe" --install @@SVC@@ "--defaults-file=@@INI@@" | Out-Null
  Set-Service -Name @@SVC@@ -StartupType Automatic
  Start-Service -Name @@SVC@@
} else {
  Set-Service -Name @@SVC@@ -StartupType Automatic
  if ((Get-Service -Name @@SVC@@).Status -ne 'Running') { Start-Service -Name @@SVC@@ }
}
if (Test-Path "@@BACKUP@@") {
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "@@BACKUP@@" -Source planifiee'
  $triggers = @((New-ScheduledTaskTrigger -Daily -At '12:30'), (New-ScheduledTaskTrigger -Daily -At '19:00'))
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
  $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  Register-ScheduledTask -TaskName '@@TASK@@' -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force | Out-Null
}
'''
          .replaceAll('@@RULE@@', firewallRule)
          .replaceAll('@@PORT@@', '$port')
          .replaceAll('@@SVC@@', serviceName)
          .replaceAll('@@BIN@@', bin)
          .replaceAll('@@ROOTPW@@', rootPassword)
          .replaceAll('@@INI@@', ini.path)
          .replaceAll('@@BACKUP@@', backupScript.path)
          .replaceAll('@@TASK@@', backupTaskName),
    );
    try {
      final p = await Process.start('powershell.exe', [
        '-NoProfile',
        '-Command',
        "try { Start-Process -FilePath powershell.exe -Verb RunAs -Wait -WindowStyle Hidden "
            "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','${script.path}' } "
            "catch { exit 1 }",
      ]);
      // Do not hang forever if nobody answers the Windows prompt.
      await p.exitCode.timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          p.kill();
          return -1;
        },
      );
    } catch (_) {
      // Declined or unavailable: carry on without the service.
    }
  }

  Future<bool> _isListening() async {
    try {
      final s = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(milliseconds: 500),
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _waitListening(Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (await _isListening()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Idempotently creates the application database and user.
  Future<void> _provision() async {
    final app = DbConfig.defaults;
    final conn = await MySqlConnection.connect(
      ConnectionSettings(
        host: '127.0.0.1',
        port: port,
        user: 'root',
        password: rootPassword,
        timeout: const Duration(seconds: 15),
      ),
    );
    try {
      await conn.query(
        'CREATE DATABASE IF NOT EXISTS `${app.dbName}` '
        'CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
      for (final host in ['%', 'localhost']) {
        await conn.query(
          "CREATE USER IF NOT EXISTS '${app.user}'@'$host' IDENTIFIED BY '${app.password}'",
        );
        await conn.query(
          "GRANT ALL PRIVILEGES ON `${app.dbName}`.* TO '${app.user}'@'$host'",
        );
      }
      await conn.query('FLUSH PRIVILEGES');
    } finally {
      await conn.close();
    }
  }
}
