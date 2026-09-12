import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
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
    } catch (_) {}
  }

  static String _pwdKey(String localId) => 'pwd_$localId';

  static Future<void> stashPassword(String localId, String password) async {
    if (password.isEmpty) return;
    try {
      await _storage.write(key: _pwdKey(localId), value: password);
    } catch (_) {}
  }

  static Future<String?> takeStashedPassword(String localId) async {
    try {
      return await _storage.read(key: _pwdKey(localId));
    } catch (_) {
      return null;
    }
  }

  static Future<void> dropStashedPassword(String localId) async {
    try {
      await _storage.delete(key: _pwdKey(localId));
    } catch (_) {}
  }
}
