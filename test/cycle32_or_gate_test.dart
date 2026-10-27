// Cycle 32 · phase P1 — device-credential OR gate (PIN-only devices).
//
// Test file name fixed by phase P1 (plan:
// plans/cycle-32-screen-lock-or-gate.md).
//
// The defect: the step-up pre-probe was `isSupported()` = AND of
// `isDeviceSupported()` and `canCheckBiometrics`, so a PIN-only device
// (secure lock, no biometric hardware/enrollment) degraded instead of
// receiving the device-credential prompt — even though
// `confirmDeviceCredential` (biometricOnly: false) would show it.
//
// What is exercised here:
//  * BiometricAuthService.isDeviceCredentialPromptAvailable — the
//    vendor-recommended OR of both platform probes (both always awaited),
//    try/catch→false like isSupported().
//  * BiometricAuthService.isSupported — AND-semantics regression lock: the
//    login biometric surface (chip visibility + enroll offer) must not change.
//  * The two step-up probe seams (PasswordChangeFactorGate and
//    OfflinePasswordService `deviceCredentialPromptAvailable`) consume the new
//    predicate — asserted through the real seams against the mocked legacy
//    local_auth method channel (the P2/P4 channel-mock pattern; in unit tests
//    `LocalAuthPlatform.instance` is DefaultLocalAuthPlatform, which maps
//    `canCheckBiometrics` onto `getAvailableBiometrics` non-empty and
//    `isDeviceSupported()` onto the `isDeviceSupported` channel method).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiproject/presentation/profile/change_pass_page.dart';
import 'package:aiproject/services/auth/biometric_auth_service.dart';
import 'package:aiproject/services/auth/offline_password_service.dart';

const MethodChannel _localAuthChannel = MethodChannel(
  'plugins.flutter.io/local_auth',
);

// ── channel mock state (legacy local_auth method channel) ──────────────────

/// `isDeviceSupported()` probe result — true on any device with a secure
/// lock (PIN/pattern/passcode or biometrics).
bool _deviceSupported = true;

/// `getAvailableBiometrics` result — non-empty implies `canCheckBiometrics`
/// true (biometric hardware with enrollment).
List<String> _enrolledBiometrics = <String>['fingerprint'];

/// Channel method that should throw, for the platform-error rows.
String? _throwOnMethod;

final List<MethodCall> _localAuthCalls = <MethodCall>[];

/// Installs the local_auth channel mock (the P2/P4 test pattern).
void _installChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_localAuthChannel, (call) async {
        _localAuthCalls.add(call);
        if (call.method == _throwOnMethod) {
          throw PlatformException(code: 'auth_error');
        }
        switch (call.method) {
          case 'isDeviceSupported':
            return _deviceSupported;
          case 'getAvailableBiometrics':
            return _enrolledBiometrics;
        }
        return null;
      });
}

void main() {
  // The local_auth method channel is mocked through the test binary
  // messenger, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _localAuthCalls.clear();
    _deviceSupported = true;
    _enrolledBiometrics = <String>['fingerprint'];
    _throwOnMethod = null;
    _installChannelMock();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localAuthChannel, null);
  });

  group(
    'BiometricAuthService.isDeviceCredentialPromptAvailable (cycle-32 P1)',
    () {
      test('biometric-hardware device (both probes true) -> true', () async {
        expect(
          await BiometricAuthService.isDeviceCredentialPromptAvailable(),
          isTrue,
        );
      });

      test(
        'PIN-only device (canCheck=false, supported=true) -> true',
        () async {
          // The cycle-32 fix: a screen lock without biometric hardware or
          // enrollment can still show the PIN prompt, because
          // confirmDeviceCredential runs with biometricOnly: false.
          _enrolledBiometrics = <String>[];

          expect(
            await BiometricAuthService.isDeviceCredentialPromptAvailable(),
            isTrue,
          );
        },
      );

      test(
        'biometrics true while isDeviceSupported reports false -> true',
        () async {
          _deviceSupported = false;

          expect(
            await BiometricAuthService.isDeviceCredentialPromptAvailable(),
            isTrue,
          );
        },
      );

      test('neither probe available -> false (no-lock degrade)', () async {
        _deviceSupported = false;
        _enrolledBiometrics = <String>[];

        expect(
          await BiometricAuthService.isDeviceCredentialPromptAvailable(),
          isFalse,
        );
      });

      test('both probes are always awaited (no OR short-circuit)', () async {
        await BiometricAuthService.isDeviceCredentialPromptAvailable();

        final methods = _localAuthCalls.map((call) => call.method);
        expect(methods, contains('getAvailableBiometrics'));
        expect(methods, contains('isDeviceSupported'));
      });

      test('a throw on the biometrics probe -> false', () async {
        _throwOnMethod = 'getAvailableBiometrics';

        expect(
          await BiometricAuthService.isDeviceCredentialPromptAvailable(),
          isFalse,
        );
      });

      test(
        'a throw on the device-support probe -> false, biometrics true',
        () async {
          _throwOnMethod = 'isDeviceSupported';

          expect(
            await BiometricAuthService.isDeviceCredentialPromptAvailable(),
            isFalse,
          );
        },
      );
    },
  );

  group('BiometricAuthService.isSupported regression lock (AND semantics)', () {
    test('PIN-only device -> false (login surface unchanged)', () async {
      // The login chip + enroll offer keep the AND gate: no biometric
      // hardware/enrollment means no fingerprint surface, even though the
      // device-credential OR predicate is true for the step-up flows.
      _enrolledBiometrics = <String>[];

      expect(await BiometricAuthService.isSupported(), isFalse);
    });

    test('biometric-hardware device -> true', () async {
      expect(await BiometricAuthService.isSupported(), isTrue);
    });

    test('no lock, no biometrics -> false', () async {
      _deviceSupported = false;
      _enrolledBiometrics = <String>[];

      expect(await BiometricAuthService.isSupported(), isFalse);
    });
  });

  group('step-up probe seams consume the OR predicate (cycle-32 P1)', () {
    test('P3 gate: PIN-only device -> prompt available', () async {
      // isSupported() (AND) is false on this device class (regression-locked
      // above), so a true seam value proves the gate reads the new predicate.
      _enrolledBiometrics = <String>[];

      final gate = const PasswordChangeFactorGate();
      expect(await gate.deviceCredentialPromptAvailable(), isTrue);
      expect(_localAuthCalls, isNotEmpty);
    });

    test('P3 gate: no lock -> false (degrade notice preserved)', () async {
      _deviceSupported = false;
      _enrolledBiometrics = <String>[];

      final gate = const PasswordChangeFactorGate();
      expect(await gate.deviceCredentialPromptAvailable(), isFalse);
    });

    test('P4 service: PIN-only device -> prompt available', () async {
      _enrolledBiometrics = <String>[];

      final service = OfflinePasswordService();
      expect(await service.deviceCredentialPromptAvailable(), isTrue);
      expect(_localAuthCalls, isNotEmpty);
    });

    test('P4 service: no lock -> false (degrade preserved)', () async {
      _deviceSupported = false;
      _enrolledBiometrics = <String>[];

      final service = OfflinePasswordService();
      expect(await service.deviceCredentialPromptAvailable(), isFalse);
    });
  });
}
