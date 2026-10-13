import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/key_derivators/api.dart' show Argon2Parameters;
import 'package:pointycastle/key_derivators/argon2.dart'
    show Argon2BytesGenerator;

/// Outcome of [PasswordHasher.verifyPassword].
///
/// Carries the scheme the stored hash matched with, so callers can run the
/// verify-then-upgrade flow without re-inspecting the stored string.
class PasswordVerification {
  /// True when the supplied password matched the stored hash.
  final bool matched;

  /// True when the match was against the legacy salted-SHA256 scheme.
  final bool isLegacy;

  const PasswordVerification({required this.matched, this.isLegacy = false});

  /// A failed verification (wrong password, malformed hash, empty inputs).
  static const PasswordVerification miss = PasswordVerification(matched: false);

  /// True when this successful verification came from a legacy row that
  /// should be re-hashed with [PasswordHasher.hashPassword].
  bool get needsUpgrade => matched && isLegacy;
}

/// Password hashing (F6/C5).
///
/// New passwords are hashed with **Argon2id** (m=19456 KiB, t=2, p=1, v=19,
/// 32-byte tag, 16-byte salt — the OWASP Password Storage Cheat Sheet
/// minimum) and stored as a self-describing PHC string:
/// `$argon2id$v=19$m=19456,t=2,p=1$<b64 salt>$<b64 tag>` (standard Base64,
/// padding omitted) in the existing `password` column.
///
/// Rows written before F6 hold salted `SHA256(salt + pw)` hex in `password`
/// plus the salt in `password_salt`. Those keep verifying **forever** — no
/// deadline and no migration — and [verifyPassword] flags them via
/// [PasswordVerification.needsUpgrade] so callers can transparently re-hash
/// after a successful login. A hash that carries the PHC prefix but fails to
/// parse or verify is a miss and never falls back to the legacy scheme (no
/// downgrade surface).
///
/// [hashPassword] deliberately costs hundreds of milliseconds of CPU on the
/// calling isolate (OWASP: a hash should take less than one second); call it
/// only from login/register flows that already await user-visible work.
class PasswordHasher {
  static const int saltBytes = 16;

  static const int _tagBytes = 32;
  static const int _memoryKiB = 19456; // 19 MiB
  static const int _iterations = 2;
  static const int _lanes = 1;

  /// Argon2 version 1.3, serialized as `v=19` (0x13).
  static const int _version = Argon2Parameters.ARGON2_VERSION_13;
  static const String _scheme = 'argon2id';

  // Bounds accepted when parsing a stored PHC string. They keep a malformed
  // or foreign row from triggering unbounded CPU/memory work; strings outside
  // these bounds are a miss, never an error.
  static const int _maxMemoryKiB = 262144; // 256 MiB
  static const int _maxIterations = 16;
  static const int _maxLanes = 8;

  /// 16 random bytes, base64url-encoded. Used by the legacy scheme; new
  /// hashes carry their salt inside the PHC string.
  static String generateSalt([int length = saltBytes]) {
    return base64Url.encode(_randomBytes(length));
  }

  /// Legacy salted SHA-256: `SHA256(salt + password)` hex.
  ///
  /// Kept forever so pre-F6 rows keep verifying; new code must use
  /// [hashPassword].
  static String hashWithSalt(String password, String salt) {
    return sha256.convert(utf8.encode('$salt$password')).toString();
  }

  /// Hashes [password] with Argon2id and returns a PHC string.
  static String hashPassword(String password) {
    final salt = Uint8List.fromList(_randomBytes(saltBytes));
    final tag = _argon2id(
      password,
      salt,
      memoryKiB: _memoryKiB,
      iterations: _iterations,
      lanes: _lanes,
    );
    return '\$$_scheme\$v=$_version'
        '\$m=$_memoryKiB,t=$_iterations,p=$_lanes'
        '\$${_encodeB64(salt)}\$${_encodeB64(tag)}';
  }

  /// Verifies [password] against a stored row, whichever scheme wrote it.
  ///
  /// A stored hash starting with `$` is parsed as a PHC string (new scheme);
  /// anything else is treated as legacy salted SHA-256 and must carry a
  /// non-empty [storedSalt]. Empty hashes/salts and malformed values are a
  /// miss — this method never throws.
  static PasswordVerification verifyPassword(
    String password, {
    required String storedHash,
    required String storedSalt,
  }) {
    if (storedHash.isEmpty) return PasswordVerification.miss;
    if (storedHash.startsWith(r'$')) {
      return _verifyPhc(password, storedHash);
    }
    if (storedSalt.isEmpty || !looksLikeLegacyHash(storedHash)) {
      return PasswordVerification.miss;
    }
    final matched = hashWithSalt(password, storedSalt) == storedHash;
    return PasswordVerification(matched: matched, isLegacy: matched);
  }

  /// Backwards-compatible bool alias of [verifyPassword]; kept for existing
  /// callers and tests. Prefer [verifyPassword], which reports the scheme.
  static bool verify(String password, String salt, String expectedHash) {
    return verifyPassword(
      password,
      storedHash: expectedHash,
      storedSalt: salt,
    ).matched;
  }

  /// Detects legacy unsalted SHA-256 hex (64 hex chars). With the salted
  /// scheme (v7+) the same shape identifies the stored hash column; the
  /// salt lives in `password_salt`.
  static bool looksLikeLegacyHash(String value) {
    return value.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
  }

  // ── internals ─────────────────────────────────────────────────────────

  static PasswordVerification _verifyPhc(String password, String storedHash) {
    try {
      final phc = _parsePhc(storedHash);
      if (phc == null) return PasswordVerification.miss;
      final tag = _argon2id(
        password,
        phc.salt,
        memoryKiB: phc.memoryKiB,
        iterations: phc.iterations,
        lanes: phc.lanes,
      );
      if (!_constantTimeEquals(tag, phc.tag)) {
        return PasswordVerification.miss;
      }
      return const PasswordVerification(matched: true);
    } catch (_) {
      // A malformed or foreign row is a failed attempt, never an error —
      // and never a fallback to the legacy scheme (downgrade surface).
      return PasswordVerification.miss;
    }
  }

  static _PhcHash? _parsePhc(String value) {
    // $argon2id$v=19$m=...,t=...,p=...$<salt>$<tag> splits into a leading
    // empty element plus five fields.
    final parts = value.split(r'$');
    if (parts.length != 6 || parts[0].isNotEmpty) return null;
    if (parts[1] != _scheme) return null;
    if (parts[2] != 'v=$_version') return null;

    final params = <String, int>{};
    for (final pair in parts[3].split(',')) {
      final eq = pair.indexOf('=');
      if (eq <= 0 || eq == pair.length - 1) return null;
      final name = pair.substring(0, eq);
      final parsed = int.tryParse(pair.substring(eq + 1));
      if (parsed == null || params.containsKey(name)) return null;
      params[name] = parsed;
    }

    final memoryKiB = params['m'];
    final iterations = params['t'];
    final lanes = params['p'];
    if (memoryKiB == null || iterations == null || lanes == null) return null;
    if (lanes < 1 || lanes > _maxLanes) return null;
    if (iterations < 1 || iterations > _maxIterations) return null;
    if (memoryKiB < 8 * lanes || memoryKiB > _maxMemoryKiB) return null;

    final salt = _decodeB64(parts[4]);
    final tag = _decodeB64(parts[5]);
    if (salt == null || salt.length < 8 || salt.length > 48) return null;
    if (tag == null || tag.length < 12 || tag.length > 64) return null;

    return _PhcHash(
      memoryKiB: memoryKiB,
      iterations: iterations,
      lanes: lanes,
      salt: salt,
      tag: tag,
    );
  }

  static Uint8List _argon2id(
    String password,
    Uint8List salt, {
    required int memoryKiB,
    required int iterations,
    required int lanes,
  }) {
    final generator = Argon2BytesGenerator();
    generator.init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: _tagBytes,
        iterations: iterations,
        memory: memoryKiB,
        lanes: lanes,
        version: _version,
      ),
    );
    return generator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  static String _encodeB64(List<int> bytes) {
    return base64.encode(bytes).replaceAll('=', '');
  }

  static Uint8List? _decodeB64(String value) {
    try {
      final padded = value + '=' * ((4 - value.length % 4) % 4);
      return base64.decode(padded);
    } catch (_) {
      return null;
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Parsed fields of an argon2id PHC string.
class _PhcHash {
  final int memoryKiB;
  final int iterations;
  final int lanes;
  final Uint8List salt;
  final Uint8List tag;

  const _PhcHash({
    required this.memoryKiB,
    required this.iterations,
    required this.lanes,
    required this.salt,
    required this.tag,
  });
}
