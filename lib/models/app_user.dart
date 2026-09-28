enum UserRole {
  /// La direction : tous les droits, seule à gérer les comptes administrateur.
  superAdmin,
  admin,
  caissier;

  String get dbValue => switch (this) {
    UserRole.superAdmin => 'SUPER_ADMIN',
    UserRole.admin => 'ADMIN',
    UserRole.caissier => 'CAISSIER',
  };

  static UserRole fromDb(String value) =>
      UserRole.values.firstWhere((r) => r.dbValue == value);

  String get label => switch (this) {
    UserRole.superAdmin => 'Direction',
    UserRole.admin => 'Administrateur',
    UserRole.caissier => 'Caissier',
  };

  /// Access to Tarifs, Paramètres and the user list.
  bool get hasAdminRights => this != UserRole.caissier;

  /// Whose accounts this role may create, reset and deactivate. A Direction
  /// account can only be changed by its own owner (change password) or by the
  /// recovery script run on the server PC.
  bool canManage(UserRole target) => switch (this) {
    UserRole.superAdmin => target != UserRole.superAdmin,
    UserRole.admin => target == UserRole.caissier,
    UserRole.caissier => false,
  };

  /// Roles this role may give to a new account.
  List<UserRole> get manageableRoles =>
      UserRole.values.where(canManage).toList();
}

/// An account of the application (never carries the password or its hash).
class AppUser {
  final int id;
  final String username;
  final String fullName;
  final UserRole role;
  final bool isActive;

  /// True after an administrator created or reset the account: the person
  /// must choose their own password before using the app.
  final bool mustChangePassword;

  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.isActive = true,
    this.mustChangePassword = false,
  });

  bool get isAdmin => role.hasAdminRights;
  bool get isSuperAdmin => role == UserRole.superAdmin;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final letters = parts
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return letters.isEmpty ? '?' : letters;
  }

  AppUser copyWith({bool? mustChangePassword, String? fullName}) => AppUser(
    id: id,
    username: username,
    fullName: fullName ?? this.fullName,
    role: role,
    isActive: isActive,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
  );

  factory AppUser.fromRow(Map<String, dynamic> row) => AppUser(
    id: row['id'] as int,
    username: row['username'] as String,
    fullName: row['full_name'] as String,
    role: UserRole.fromDb(row['role'] as String),
    isActive: (row['is_active'] as int) == 1,
    mustChangePassword: (row['must_change_password'] as int) == 1,
  );
}
