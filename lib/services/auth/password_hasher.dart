import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Salted password hashing: SHA256(salt + password).
/// Small single-responsibility helper (C5). Argon2 not available
/// without native plugins, so salted SHA-256 is the minimum bar.
/// Local DB is app-private (scoped storage); see docs/backend-rls.md
/// for the sqlcipher upgrade note.
class PasswordHasher {
  static const int saltBytes = 16;

  static String generateSalt([int length = saltBytes]) {
    final rng = Random.secure();
    final bytes = List<int>.generate(length, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String hashWithSalt(String password, String salt) {
    return sha256.convert(utf8.encode('$salt$password')).toString();
  }

  static bool verify(String password, String salt, String expectedHash) {
    if (salt.isEmpty || expectedHash.isEmpty) return false;
    return hashWithSalt(password, salt) == expectedHash;
  }

  /// Detects legacy unsalted SHA-256 hex (64 hex chars).
  static bool looksLikeLegacyHash(String value) {
    return value.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
  }
}
