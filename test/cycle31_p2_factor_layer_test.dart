// Cycle 31 · phase P2 — service-layer second-factor capabilities.
//
// Test file name fixed by phase P2 (plan: plans/cycle-31-second-factor-password-change.md,
// phase P5 consumes this file name).
//
// Scope of what is unit-testable here:
//  * AuthService.isGoogleLinked — pure rule over a Supabase `User`; the gotrue
//    client exposes a public constructor, so plain fakes are enough.
//  * AuthService.verifyGoogleReauth — the account-binding rule is exercised
//    through the documented test seam (the google_sign_in plugin's account type
//    has a private constructor, so the plugin call itself cannot be faked
//    without adding a dev dependency).
//  * AuthService step-up OTP pair — guarded by the backend-ready check; the
//    send/verify round trip itself needs a live Supabase project.
//  * BiometricAuthService.confirmDeviceCredential — the local_auth method
//    channel is mocked, so the exact prompt arguments and the "nothing is
//    persisted" guarantee are asserted.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aiproject/services/auth/auth_service.dart';
import 'package:aiproject/services/auth/biometric_auth_service.dart';

const MethodChannel _localAuthChannel = MethodChannel(
  'plugins.flutter.io/local_auth',
);

const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

UserIdentity _identityFake(String provider) {
  return UserIdentity(
    id: 'identity-$provider',
    userId: 'user-id',
    identityData: const <String, dynamic>{},
    identityId: 'identity-$provider',
    provider: provider,
    createdAt: '2026-01-01T00:00:00Z',
    lastSignInAt: '2026-01-01T00:00:00Z',
  );
}

/// Builds a Supabase user fake. `identityProviders` becomes the
/// `identities` list; `appMetadata` is the `app_metadata` map.
User _userFake({
  List<String> identityProviders = const <String>[],
  Map<String, dynamic> appMetadata = const <String, dynamic>{},
}) {
  return User(
    id: 'user-id',
    appMetadata: appMetadata,
    userMetadata: const <String, dynamic>{},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    email: 'user@example.com',
    identities: identityProviders.map(_identityFake).toList(),
  );
}

void main() {
  // The local_auth / secure-storage method channels are mocked through the
  // test binary messenger, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AuthService.googleAccountEmailForTest = null;
  });

  group('AuthService.isGoogleLinked (cycle-31 P2)', () {
    test('returns true when an identity carries the google provider', () {
      final user = _userFake(identityProviders: <String>['google']);
      expect(AuthService.isGoogleLinked(user), isTrue);
    });

    test('returns true when google is one of several identities', () {
      final user = _userFake(identityProviders: <String>['email', 'google']);
      expect(AuthService.isGoogleLinked(user), isTrue);
    });

    test('returns false for a password-only identity', () {
      final user = _userFake(identityProviders: <String>['password']);
      expect(AuthService.isGoogleLinked(user), isFalse);
    });

    test('returns true when appMetadata provider is google', () {
      final user = _userFake(
        appMetadata: <String, dynamic>{'provider': 'google'},
      );
      expect(AuthService.isGoogleLinked(user), isTrue);
    });

    test('returns false without a google identity and google metadata', () {
      final user = _userFake(
        identityProviders: <String>['password'],
        appMetadata: <String, dynamic>{'provider': 'email'},
      );
      expect(AuthService.isGoogleLinked(user), isFalse);
    });
  });

  group('AuthService.verifyGoogleReauth (cycle-31 P2)', () {
    test('rejects an account email that differs from the expected email', () {
      AuthService.googleAccountEmailForTest = () async => 'other@example.com';

      expect(
        () => AuthService.verifyGoogleReauth('user@example.com'),
        throwsA(
          isA<GoogleSignInFailure>().having(
            (failure) => failure.code,
            'code',
            'email_mismatch',
          ),
        ),
      );
    });

    test('rejects an empty account email', () {
      AuthService.googleAccountEmailForTest = () async => '';

      expect(
        () => AuthService.verifyGoogleReauth('user@example.com'),
        throwsA(
          isA<GoogleSignInFailure>().having(
            (failure) => failure.code,
            'code',
            'email_mismatch',
          ),
        ),
      );
    });

    test('accepts a matching account email regardless of case and padding', () {
      AuthService.googleAccountEmailForTest = () async => '  USER@Example.com ';

      expect(AuthService.verifyGoogleReauth('user@example.com'), completes);
    });

    test('surfaces a typed failure when the Google client is unusable', () {
      // No --dart-define GOOGLE_SERVER_CLIENT_ID in the test environment, so
      // the plugin path fails closed with a typed failure the caller can map
      // to the email-OTP fallback.
      expect(
        () => AuthService.verifyGoogleReauth('user@example.com'),
        throwsA(
          isA<GoogleSignInFailure>().having(
            (failure) => failure.code,
            'code',
            'not_configured',
          ),
        ),
      );
    });
  });

  group('AuthService step-up OTP pair (cycle-31 P2)', () {
    test('sendOtpForStepUp refuses to run before the backend is ready', () {
      expect(
        () => AuthService.sendOtpForStepUp('user@example.com'),
        throwsA(isA<StateError>()),
      );
    });

    test('verifyOtpStepUp refuses to run before the backend is ready', () {
      expect(
        () => AuthService.verifyOtpStepUp('user@example.com', '123456'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('BiometricAuthService.confirmDeviceCredential (cycle-31 P2)', () {
    final List<MethodCall> localAuthCalls = <MethodCall>[];
    final List<MethodCall> secureStorageCalls = <MethodCall>[];

    setUp(() {
      localAuthCalls.clear();
      secureStorageCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            localAuthCalls.add(call);
            return true;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, (call) async {
            secureStorageCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, null);
    });

    test(
      'passes the step-up wording with the device-credential shape',
      () async {
        const reason = 'Confirm your identity to change your password';

        final ok = await BiometricAuthService.confirmDeviceCredential(
          localizedReason: reason,
        );

        expect(ok, isTrue);
        expect(localAuthCalls, hasLength(1));
        expect(localAuthCalls.single.method, 'authenticate');
        final args = Map<Object?, Object?>.from(
          localAuthCalls.single.arguments as Map<Object?, Object?>,
        );
        expect(args['localizedReason'], reason);
        expect(args['biometricOnly'], isFalse);
        // local_auth maps persistAcrossBackgrounding onto the legacy
        // `stickyAuth` option.
        expect(args['stickyAuth'], isTrue);
      },
    );

    test('returns false when the platform reports no confirmation', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async => false);

      final ok = await BiometricAuthService.confirmDeviceCredential(
        localizedReason: 'Confirm your identity to change your password',
      );

      expect(ok, isFalse);
    });

    test('returns false when the platform throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            throw PlatformException(code: 'auth_error');
          });

      final ok = await BiometricAuthService.confirmDeviceCredential(
        localizedReason: 'Confirm your identity to change your password',
      );

      expect(ok, isFalse);
    });

    test('persists no token and no secret', () async {
      final ok = await BiometricAuthService.confirmDeviceCredential(
        localizedReason: 'Confirm your identity to change your password',
      );

      expect(ok, isTrue);
      expect(secureStorageCalls, isEmpty);
    });
  });
}
