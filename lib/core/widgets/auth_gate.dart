import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/change_password_form.dart';
import '../../features/auth/login_screen.dart';
import '../../features/setup/setup_wizard_screen.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backup_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';
import 'connection_views.dart';

/// Nothing of the application is shown until the server is reachable, a
/// user is logged in (and, if required, has chosen their own password), and
/// — for a brand-new installation — the first-launch setup assistant has
/// run (see [setupCompletedProvider]).
class AuthGate extends ConsumerWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(dbReadyProvider);
    return ready.when(
      loading: () => const ConnectingView(),
      error: (e, _) => ConnectionErrorView(error: e),
      data: (_) {
        // On the server PC: makes a catch-up backup if none is recent.
        ref.watch(backupSchedulerProvider);
        final user = ref.watch(authProvider);
        if (user == null) return const LoginScreen();
        if (user.mustChangePassword) return const ForcedPasswordChangeScreen();
        final setupDone = ref.watch(setupCompletedProvider);
        if (setupDone.value == false) return const SetupWizardScreen();
        return child;
      },
    );
  }
}
