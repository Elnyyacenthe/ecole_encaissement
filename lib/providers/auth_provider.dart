import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import 'db_providers.dart';

/// The person using this PC right now (null = not logged in). Kept in memory
/// only: closing the app logs out.
class AuthNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  Future<void> login(String username, String password) async {
    state = await ref
        .read(usersRepositoryProvider)
        .authenticate(username, password);
  }

  void logout() => state = null;

  /// Changes the logged-in person's own display name.
  Future<void> updateOwnName(String name) async {
    final user = state;
    if (user == null) return;
    await ref
        .read(usersRepositoryProvider)
        .updateFullName(actor: user, userId: user.id, fullName: name);
    state = user.copyWith(
      fullName: name.trim().replaceAll(RegExp(r'\s+'), ' '),
    );
  }

  Future<void> changePassword(String current, String next) async {
    final user = state;
    if (user == null) return;
    await ref
        .read(usersRepositoryProvider)
        .changePassword(
          userId: user.id,
          currentPassword: current,
          newPassword: next,
        );
    state = user.copyWith(mustChangePassword: false);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AppUser?>(AuthNotifier.new);
