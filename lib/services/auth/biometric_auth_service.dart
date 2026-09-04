// ignore_for_file: empty_catches
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  static const String _enabledKey = 'biometric_enabled';
  static const String _uidKey = 'biometric_uid';

  static final LocalAuthentication _auth = LocalAuthentication();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnrolled() async {
    try {
      final flag = await _storage.read(key: _enabledKey);
      final uid = await _storage.read(key: _uidKey);
      return flag == '1' && uid != null && uid.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enroll(String uid) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Enable quick unlock for AgentA?',
        biometricOnly: true,
      );
      if (!ok) return false;
      await _storage.write(key: _enabledKey, value: '1');
      await _storage.write(key: _uidKey, value: uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> unlock() async {
    try {
      if (!await isEnrolled()) return null;
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock AgentA',
        biometricOnly: true,
      );
      if (!ok) return null;
      return _storage.read(key: _uidKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> disable() async {
    try {
      await _storage.delete(key: _enabledKey);
      await _storage.delete(key: _uidKey);
    } catch (_) {}
  }
}
