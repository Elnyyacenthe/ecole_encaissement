import 'package:cosbimp_scolarite/core/security/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PBKDF2-HMAC-SHA256 : vecteurs de test officiels (RFC 7914)', () {
    const saltHex = '73616c74'; // "salt"
    expect(
      PasswordHasher.hash('password', saltHex, iterations: 1),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      PasswordHasher.hash('password', saltHex, iterations: 2),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
  });

  test('vérification : bon mot de passe accepté, mauvais refusé', () {
    final salt = PasswordHasher.newSalt();
    final h = PasswordHasher.hash('Secret123', salt);
    expect(
      PasswordHasher.verify(
        'Secret123',
        salt,
        h,
        PasswordHasher.defaultIterations,
      ),
      isTrue,
    );
    expect(
      PasswordHasher.verify(
        'secret123',
        salt,
        h,
        PasswordHasher.defaultIterations,
      ),
      isFalse,
    );
    expect(
      PasswordHasher.verify('', salt, h, PasswordHasher.defaultIterations),
      isFalse,
    );
  });

  test(
    'deux comptes avec le même mot de passe ont des empreintes différentes',
    () {
      final a = PasswordHasher.hash('meme', PasswordHasher.newSalt());
      final b = PasswordHasher.hash('meme', PasswordHasher.newSalt());
      expect(a, isNot(b));
    },
  );
}
