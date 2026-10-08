import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/school_logo.dart';
import '../models/school_identity.dart';
import '../providers/data_providers.dart';

/// Logo bytes for PDFs: the one saved in the database, else a bundled file,
/// else null (documents then print without a logo instead of failing).
Future<Uint8List?> loadLogoBytes(WidgetRef ref) async {
  try {
    final saved = await ref.read(logoBytesProvider.future);
    if (saved != null) return saved;
  } catch (_) {
    // Fall back to bundled files.
  }
  for (final asset in kLogoAssets) {
    try {
      final data = await rootBundle.load(asset);
      return data.buffer.asUint8List();
    } catch (_) {
      // Try the next accepted file name.
    }
  }
  return null;
}

/// The school's configured identity for printed documents, falling back to
/// the built-in defaults (handled by [ReceiptLabels.forSection] itself)
/// if anything goes wrong reading it.
Future<SchoolIdentity> loadSchoolIdentity(WidgetRef ref) async {
  try {
    return await ref.read(schoolIdentityProvider.future);
  } catch (_) {
    return const SchoolIdentity(matriculePrefix: 'MP');
  }
}
