import '../core/db/mysql_connection_service.dart';
import '../core/security/password_hasher.dart';
import '../models/app_user.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

const int kMinPasswordLength = 6;

/// Login name of the account created on first start; its password must be
/// changed at the first login.
const String kDefaultAdminUsername = 'admin';
const String kDefaultAdminPassword = 'admin';

/// Account for the school's Direction, created on first start (or on update):
/// the safety net when an administrator password is lost. Its initial password
/// is given to the Direction, who must replace it at the first login.
const String kDirectionUsername = 'directrice';
const String kDirectionInitialPassword = 'Direction@2026';

const _columns =
    'id, username, full_name, role, is_active, must_change_password';

int _int(Object? v) => (v as num).toInt();

class UsersRepository {
  final MySqlConnectionService db;
  UsersRepository(this.db);

  static Future<void> _insertAccount(
    MySqlConnectionService db, {
    required String username,
    required String fullName,
    required UserRole role,
    required String password,
  }) async {
    final salt = PasswordHasher.newSalt();
    await db.execute(
      'INSERT IGNORE INTO users (username, full_name, role, password_hash, salt, iterations, '
      'must_change_password, is_active) VALUES (?, ?, ?, ?, ?, ?, 1, 1)',
      [
        username,
        fullName,
        role.dbValue,
        PasswordHasher.hash(password, salt),
        salt,
        PasswordHasher.defaultIterations,
      ],
    );
  }

  /// Creates the starting accounts: the default administrator when there is
  /// no account yet, and the Direction account when there is none (also on an
  /// existing installation). Idempotent and safe if two PCs start together.
  static Future<void> ensureDefaultAccounts(MySqlConnectionService db) async {
    final n = await db.select('SELECT COUNT(*) AS n FROM users');
    if (_int(n.first['n']) == 0) {
      await _insertAccount(
        db,
        username: kDefaultAdminUsername,
        fullName: 'Administrateur',
        role: UserRole.admin,
        password: kDefaultAdminPassword,
      );
    }
    final direction = await db.select(
      "SELECT COUNT(*) AS n FROM users WHERE role = 'SUPER_ADMIN'",
    );
    if (_int(direction.first['n']) == 0) {
      await _insertAccount(
        db,
        username: kDirectionUsername,
        fullName: 'Direction',
        role: UserRole.superAdmin,
        password: kDirectionInitialPassword,
      );
    }
  }

  /// The account matching [username] and [password], or throws an
  /// [AuthException]. The message is the same for an unknown login and a
  /// wrong password so it does not reveal which logins exist.
  Future<AppUser> authenticate(String username, String password) async {
    final rows = await db.select(
      'SELECT $_columns, password_hash, salt, iterations FROM users WHERE username = ?',
      [username.trim().toLowerCase()],
    );
    const wrong = 'Identifiant ou mot de passe incorrect.';
    if (rows.isEmpty) {
      // Same amount of work as a real check.
      PasswordHasher.hash(password, PasswordHasher.newSalt());
      throw AuthException(wrong);
    }
    final r = rows.first;
    final ok = PasswordHasher.verify(
      password,
      r['salt'] as String,
      r['password_hash'] as String,
      _int(r['iterations']),
    );
    if (!ok) throw AuthException(wrong);
    final user = AppUser.fromRow(r);
    if (!user.isActive) {
      throw AuthException(
        "Ce compte est désactivé. Contactez l'administrateur.",
      );
    }
    return user;
  }

  /// True while the built-in administrator still has its initial password
  /// (used only to show the first-use hint on the login screen).
  Future<bool> usesDefaultAdminPassword() async {
    final rows = await db.select(
      'SELECT password_hash, salt, iterations FROM users WHERE username = ? AND must_change_password = 1',
      [kDefaultAdminUsername],
    );
    if (rows.isEmpty) return false;
    final r = rows.first;
    return PasswordHasher.verify(
      kDefaultAdminPassword,
      r['salt'] as String,
      r['password_hash'] as String,
      _int(r['iterations']),
    );
  }

  static void validateNewPassword(String password) {
    if (password.length < kMinPasswordLength) {
      throw AuthException(
        'Le mot de passe doit contenir au moins $kMinPasswordLength caractères.',
      );
    }
  }

  /// Lets a user choose a new password after proving the current one.
  Future<void> changePassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    validateNewPassword(newPassword);
    if (newPassword == currentPassword) {
      throw AuthException(
        "Le nouveau mot de passe doit être différent de l'actuel.",
      );
    }
    final rows = await db.select(
      'SELECT password_hash, salt, iterations FROM users WHERE id = ?',
      [userId],
    );
    if (rows.isEmpty) throw AuthException('Compte introuvable.');
    final r = rows.first;
    if (!PasswordHasher.verify(
      currentPassword,
      r['salt'] as String,
      r['password_hash'] as String,
      _int(r['iterations']),
    )) {
      throw AuthException('Le mot de passe actuel est incorrect.');
    }
    await _setPassword(userId, newPassword, mustChange: false);
  }

  Future<List<AppUser>> list() async {
    final rows = await db.select(
      "SELECT $_columns FROM users ORDER BY is_active DESC, FIELD(role,'SUPER_ADMIN','ADMIN','CAISSIER'), full_name",
    );
    return rows.map(AppUser.fromRow).toList();
  }

  Future<UserRole> _roleOf(int userId) async {
    final rows = await db.select('SELECT role FROM users WHERE id = ?', [
      userId,
    ]);
    if (rows.isEmpty) throw AuthException('Compte introuvable.');
    return UserRole.fromDb(rows.first['role'] as String);
  }

  /// Throws unless [actor] may manage accounts of role [target].
  static void _requireRight(AppUser actor, UserRole target) {
    if (!actor.role.canManage(target)) {
      throw AuthException(
        target == UserRole.superAdmin
            ? 'Le compte Direction ne peut être modifié que par la Direction elle-même.'
            : "Vous n'avez pas le droit de gérer ce type de compte.",
      );
    }
  }

  /// Changes the name shown in the app and printed on receipts as the
  /// "Encaisseur". Everyone may change their own; otherwise the same rights
  /// as for resetting a password apply.
  Future<void> updateFullName({
    required AppUser actor,
    required int userId,
    required String fullName,
  }) async {
    final name = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.length < 2) {
      throw AuthException('Le nom doit contenir au moins 2 caractères.');
    }
    if (name.length > 100) {
      throw AuthException('Nom trop long (100 caractères).');
    }
    if (userId != actor.id) _requireRight(actor, await _roleOf(userId));
    await db.execute('UPDATE users SET full_name = ? WHERE id = ?', [
      name,
      userId,
    ]);
  }

  /// New account; the person must choose their own password at first login.
  Future<void> create({
    required AppUser actor,
    required String username,
    required String fullName,
    required UserRole role,
    required String temporaryPassword,
  }) async {
    _requireRight(actor, role);
    final login = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch(login)) {
      throw AuthException(
        "L'identifiant doit faire 3 à 30 caractères : lettres, chiffres, point, tiret.",
      );
    }
    if (fullName.trim().isEmpty) throw AuthException('Le nom est obligatoire.');
    validateNewPassword(temporaryPassword);
    final exists = await db.select('SELECT 1 FROM users WHERE username = ?', [
      login,
    ]);
    if (exists.isNotEmpty) {
      throw AuthException('Cet identifiant existe déjà.');
    }
    final salt = PasswordHasher.newSalt();
    await db.execute(
      'INSERT INTO users (username, full_name, role, password_hash, salt, iterations, '
      'must_change_password, is_active) VALUES (?, ?, ?, ?, ?, ?, 1, 1)',
      [
        login,
        fullName.trim(),
        role.dbValue,
        PasswordHasher.hash(temporaryPassword, salt),
        salt,
        PasswordHasher.defaultIterations,
      ],
    );
  }

  /// [actor] sets a temporary password for someone who forgot theirs: the
  /// person must replace it at the next login. An administrator can do this
  /// for cashiers only; the Direction can also do it for administrators.
  Future<void> resetPassword(
    AppUser actor,
    int userId,
    String temporaryPassword,
  ) async {
    _requireRight(actor, await _roleOf(userId));
    validateNewPassword(temporaryPassword);
    await _setPassword(userId, temporaryPassword, mustChange: true);
  }

  Future<void> setActive(AppUser actor, int userId, bool active) async {
    _requireRight(actor, await _roleOf(userId));
    if (!active) {
      // Someone with administrator rights must always remain able to log in.
      final others = await db.select(
        "SELECT COUNT(*) AS n FROM users WHERE role IN ('SUPER_ADMIN','ADMIN') "
        'AND is_active = 1 AND id <> ?',
        [userId],
      );
      final target = await _roleOf(userId);
      if (target != UserRole.caissier && _int(others.first['n']) == 0) {
        throw AuthException('Il doit rester au moins un administrateur actif.');
      }
    }
    await db.execute('UPDATE users SET is_active = ? WHERE id = ?', [
      active ? 1 : 0,
      userId,
    ]);
  }

  Future<void> _setPassword(
    int userId,
    String password, {
    required bool mustChange,
  }) async {
    final salt = PasswordHasher.newSalt();
    await db.execute(
      'UPDATE users SET password_hash = ?, salt = ?, iterations = ?, must_change_password = ? '
      'WHERE id = ?',
      [
        PasswordHasher.hash(password, salt),
        salt,
        PasswordHasher.defaultIterations,
        mustChange ? 1 : 0,
        userId,
      ],
    );
  }
}
