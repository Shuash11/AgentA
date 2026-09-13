import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Recovery-code hashing (H8). Raw codes are shown once at creation,
/// then only the SHA-256 hash is stored locally and in Supabase
/// (`recovery_code_hash` / hashed `recovery_code`).
/// Server-side RPC verification is the target; see docs/backend-rls.md.
class RecoveryCodeHasher {
  static String normalize(String code) =>
      code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  static String hash(String code) {
    return sha256.convert(utf8.encode(normalize(code))).toString();
  }

  static bool verify(String entered, String storedHash) {
    if (storedHash.isEmpty) return false;
    return hash(entered) == storedHash;
  }
}
