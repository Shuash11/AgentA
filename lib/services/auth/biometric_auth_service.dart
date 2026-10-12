import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  static const String _enabledKey = 'biometric_enabled';
  static const String _uidKey = 'biometric_uid';

  static final LocalAuthentication _auth = LocalAuthentication();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[Biometric] isSupported failed: $e | $stack');
      return false;
    }
  }

  static Future<bool> isEnrolled() async {
    try {
      final flag = await _storage.read(key: _enabledKey);
      final uid = await _storage.read(key: _uidKey);
      return flag == '1' && uid != null && uid.isNotEmpty;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[Biometric] isEnrolled failed: $e | $stack');
      return false;
    }
  }

  static Future<bool> enroll(String uid) async {
    try {
      // local_auth 3.x: biometricOnly=false allows the device PIN/pattern
      // fallback (M17); persistAcrossBackgrounding keeps the prompt alive
      // when the app is backgrounded (the old stickyAuth option).
      final ok = await _auth.authenticate(
        localizedReason: 'Enable quick unlock for AgentA?',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (!ok) return false;
      await _storage.write(key: _enabledKey, value: '1');
      await _storage.write(key: _uidKey, value: uid);
      if (kDebugMode) {
        debugPrint('[Biometric] enroll success uidLen=${uid.length}');
      }
      return true;
    } on LocalAuthException catch (e) {
      // M17: no biometrics enrolled / no credentials set is a normal state,
      // not a crash — degrade silently (debug log only).
      const unavailableCodes = <LocalAuthExceptionCode>{
        LocalAuthExceptionCode.noBiometricsEnrolled,
        LocalAuthExceptionCode.noBiometricHardware,
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable,
        LocalAuthExceptionCode.noCredentialsSet,
        LocalAuthExceptionCode.uiUnavailable,
        LocalAuthExceptionCode.userCanceled,
      };
      if (unavailableCodes.contains(e.code)) {
        if (kDebugMode) debugPrint('[Biometric] enroll unavailable: ${e.code}');
        return false;
      }
      if (kDebugMode) debugPrint('[Biometric] enroll failed: $e');
      return false;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[Biometric] enroll failed: $e | $stack');
      return false;
    }
  }

  static Future<String?> unlock() async {
    try {
      if (!await isEnrolled()) return null;
      // local_auth 3.x: device-credential fallback + backgrounding-stable prompt.
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock AgentA',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (!ok) return null;
      return await _storage.read(key: _uidKey);
    } on LocalAuthException catch (e) {
      const unavailableCodes = <LocalAuthExceptionCode>{
        LocalAuthExceptionCode.noBiometricsEnrolled,
        LocalAuthExceptionCode.noBiometricHardware,
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable,
        LocalAuthExceptionCode.noCredentialsSet,
        LocalAuthExceptionCode.uiUnavailable,
        LocalAuthExceptionCode.userCanceled,
        LocalAuthExceptionCode.temporaryLockout,
        LocalAuthExceptionCode.biometricLockout,
        LocalAuthExceptionCode.systemCanceled,
        LocalAuthExceptionCode.timeout,
      };
      if (unavailableCodes.contains(e.code)) {
        if (kDebugMode) debugPrint('[Biometric] unlock unavailable: ${e.code}');
        return null;
      }
      if (kDebugMode) debugPrint('[Biometric] unlock failed: $e');
      return null;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[Biometric] unlock failed: $e | $stack');
      return null;
    }
  }

  static Future<void> disable() async {
    try {
      await _storage.delete(key: _enabledKey);
      await _storage.delete(key: _uidKey);
      if (kDebugMode) debugPrint('[Biometric] disable done');
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[Biometric] disable failed: $e | $stack');
    }
  }
}
