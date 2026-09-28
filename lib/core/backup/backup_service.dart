import 'dart:async';
import 'dart:io';

import '../db/embedded_server.dart';

class BackupResult {
  final bool ok;
  final String message;
  const BackupResult(this.ok, this.message);
}

/// Runs Sauvegarde.ps1, the same script the Windows scheduled task runs.
/// Only the server PC has it (next to the bundled database).
class BackupService {
  static bool _running = false;

  static File? scriptFile() {
    if (!Platform.isWindows) return null;
    final bundle = EmbeddedServer.locateBundle();
    if (bundle == null) return null;
    final script = File('${bundle.parent.path}\\Sauvegarde.ps1');
    return script.existsSync() ? script : null;
  }

  static bool get isServerPc => scriptFile() != null;

  /// [source] is recorded in the journal (manuelle, rattrapage...).
  static Future<BackupResult> run(String source) async {
    final script = scriptFile();
    if (script == null) {
      return const BackupResult(
        false,
        'Sauvegarde possible uniquement sur le PC serveur.',
      );
    }
    if (_running) {
      return const BackupResult(false, 'Une sauvegarde est déjà en cours.');
    }
    _running = true;
    try {
      final r = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '-Source',
        source,
      ]).timeout(const Duration(minutes: 10));
      final text = '${r.stdout}'.trim();
      return BackupResult(
        r.exitCode == 0,
        text.isEmpty ? '${r.stderr}'.trim() : text,
      );
    } on TimeoutException {
      return const BackupResult(false, 'La sauvegarde a dépassé 10 minutes.');
    } catch (e) {
      return BackupResult(false, '$e');
    } finally {
      _running = false;
    }
  }
}
