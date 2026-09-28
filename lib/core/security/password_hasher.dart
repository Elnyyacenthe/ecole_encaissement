import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Password hashing with PBKDF2-HMAC-SHA256 and a random salt per user.
/// Passwords are never stored or logged in clear text.
class PasswordHasher {
  static const int defaultIterations = 20000;

  static String newSalt() {
    final random = Random.secure();
    return _hex([for (var i = 0; i < 16; i++) random.nextInt(256)]);
  }

  static String hash(
    String password,
    String saltHex, {
    int iterations = defaultIterations,
  }) {
    final hmac = Hmac(sha256, utf8.encode(password));
    var u = hmac.convert([..._unhex(saltHex), 0, 0, 0, 1]).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return _hex(t);
  }

  /// Compares in constant time so timing does not reveal how much matched.
  static bool verify(
    String password,
    String saltHex,
    String expectedHex,
    int iterations,
  ) {
    final actual = hash(password, saltHex, iterations: iterations);
    if (actual.length != expectedHex.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHex.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _unhex(String hex) => [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}
