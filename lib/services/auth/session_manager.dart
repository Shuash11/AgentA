import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'password_hasher.dart';

class LocalSession {
  final String uid;
  final String email;
  final String provider;

  const LocalSession({
    required this.uid,
    required this.email,
    required this.provider,
  });
}

class SessionManager {
  static const String _uidKey = 'session_uid';
  static const String _emailKey = 'session_email';
  static const String _providerKey = 'session_provider';
  static const String _lastEmailKey = 'session_last_email';
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _biometricUidKey = 'biometric_uid';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Salted hash (C5). Prefer [PasswordHasher.hashWithSalt] for new code.
  static String hashPassword(String password, {String salt = ''}) {
    if (salt.isEmpty) return PasswordHasher.hashWithSalt(password, '');
    return PasswordHasher.hashWithSalt(password, salt);
  }

  static Future<void> saveSession({
    required String uid,
    required String email,
    required String provider,
  }) async {
    await _storage.write(key: _uidKey, value: uid);
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _providerKey, value: provider);
    if (email.isNotEmpty) {
      await _storage.write(key: _lastEmailKey, value: email);
    }
  }

  static Future<LocalSession?> currentSession() async {
    try {
      final uid = await _storage.read(key: _uidKey);
      if (uid == null || uid.isEmpty) return null;
      final email = await _storage.read(key: _emailKey) ?? '';
      final provider = await _storage.read(key: _providerKey) ?? 'password';
      return LocalSession(uid: uid, email: email, provider: provider);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> lastEmail() async {
    try {
      return await _storage.read(key: _lastEmailKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _uidKey);
      await _storage.delete(key: _emailKey);
      await _storage.delete(key: _providerKey);
      // M16: logout must not leave identity hints, stashed secrets, or a
      // lingering biometric opt-in behind.
      await _storage.delete(key: _lastEmailKey);
      await _storage.delete(key: _biometricEnabledKey);
      await _storage.delete(key: _biometricUidKey);
      try {
        final all = await _storage.readAll();
        for (final key in all.keys) {
          if (key.startsWith('pwd_')) {
            await _storage.delete(key: key);
          }
        }
      } catch (e) {
        // L20: best-effort wipe, but never silently — log so a failing
        // storage layer is diagnosable.
        if (kDebugMode) debugPrint('[SessionManager] legacy pwd_* sweep failed: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SessionManager] session clear failed: $e');
    }
  }

  // ── C2: plaintext password vault REMOVED ──────────────────────────
  // Sessions store only uid/email/provider. No password is ever stashed.
  // The two helpers below exist solely for one-time migration cleanup:
  // delete a single legacy `pwd_<id>` key, or best-effort wipe for a
  // list of known ids. Sync now requires password re-entry instead of
  // reading a stashed secret (see SyncService._syncPendingUsers).

  static String legacyPwdKey(String localId) => 'pwd_$localId';

  static Future<void> dropStashedPassword(String localId) async {
    try {
      await _storage.delete(key: legacyPwdKey(localId));
    } catch (e) {
      if (kDebugMode) debugPrint('[SessionManager] dropStashedPassword failed: $e');
    }
  }

  static Future<void> wipeLegacyPasswordVault(List<String> knownIds) async {
    for (final id in knownIds) {
      await dropStashedPassword(id);
    }
  }
}
