import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  runApp(
    // Riverpod 3 retries failed providers by default; a DB error should be
    // shown immediately and retried only on explicit user action.
    ProviderScope(retry: (_, _) => null, child: const CosbimpApp()),
  );
}
