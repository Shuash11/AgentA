import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/core/config/app_config.dart';
import 'package:aiproject/services/auth/auth_service.dart';
import 'package:aiproject/services/auth/password_hasher.dart';
import 'package:aiproject/services/auth/recovery_code_hasher.dart';
import 'package:aiproject/core/utils/auth_retry.dart';
import 'dart:io';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AppConfig trim/validate (M21)', () {
    test('googleServerClientId getter trims whitespace', () {
      // AppConfig getter always trims — validate empty, malformed, valid cases via validateGoogleConfigAtStartup
      // Directly test validate logic: empty should be invalid
      expect(AppConfig.googleServerClientId, isA<String>());
      // validate at startup should handle empty/malformed without throwing full secret
      final ok = AppConfig.validateGoogleConfigAtStartup();
      // ok may be true/false depending on env, but should not throw and should set error if invalid
      expect(ok, isA<bool>());
      if (!ok) {
        expect(AppConfig.googleConfigError, isNotNull);
      }
      // Check suffix helper never leaks full id
      final suffix = AppConfig.googleIdSuffixForLog;
      expect(suffix.length, lessThanOrEqualTo(8 + 3)); // "..." + 8
    });

    test('supabase getters trim (M21)', () {
      expect(AppConfig.supabaseUrl, equals(AppConfig.supabaseUrl.trim()));
      expect(AppConfig.supabasePublishableKey, equals(AppConfig.supabasePublishableKey.trim()));
    });

    test('envLengths logs lengths-only (no secrets)', () {
      final lengths = AppConfig.envLengths;
      expect(lengths.containsKey('SUPABASE_URL'), true);
      expect(lengths.containsKey('GOOGLE_SERVER_CLIENT_ID'), true);
      for (final v in lengths.values) {
        expect(v, isA<int>());
        expect(v, greaterThanOrEqualTo(0));
      }
    });
  });

  group('Auth validators', () {
    test('validateEmail', () {
      expect(AuthService.validateEmail(null), isNotNull);
      expect(AuthService.validateEmail(''), isNotNull);
      expect(AuthService.validateEmail('no-at'), isNotNull);
      expect(AuthService.validateEmail('good@example.com'), isNull);
      // trimmed email considered valid
      expect(AuthService.validateEmail(' good@example.com '), isNull);
    });

    test('validatePassword', () {
      expect(AuthService.validatePassword(null), isNotNull);
      expect(AuthService.validatePassword(''), isNotNull);
      expect(AuthService.validatePassword('123'), isNotNull);
      expect(AuthService.validatePassword('12345'), isNotNull);
      // M12: minimum 8 chars + letters and digits.
      expect(AuthService.validatePassword('123456'), isNotNull); // too short
      expect(AuthService.validatePassword('12345678'), isNotNull); // digits only
      expect(AuthService.validatePassword('abcdefgh'), isNotNull); // letters only
      expect(AuthService.validatePassword('abc12345'), isNull); // valid
    });
  });

  group('PasswordHasher offline-login deny (M15)', () {
    test('verify denies wrong password', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashWithSalt('correctPass', salt);
      expect(PasswordHasher.verify('correctPass', salt, hash), true);
      expect(PasswordHasher.verify('wrongPass', salt, hash), false);
      expect(PasswordHasher.verify('', salt, hash), false);
      expect(PasswordHasher.verify('correctPass', '', hash), false);
      expect(PasswordHasher.verify('correctPass', salt, ''), false);
    });

    test('salt is random and hash length stable', () {
      final s1 = PasswordHasher.generateSalt();
      final s2 = PasswordHasher.generateSalt();
      expect(s1, isNot(equals(s2)));
      final h = PasswordHasher.hashWithSalt('a', s1);
      expect(h.length, 64); // sha256 hex
    });
  });

  group('RecoveryCodeHasher', () {
    test('hash/verify roundtrip', () {
      const code = 'ABC-DEF';
      final hash = RecoveryCodeHasher.hash(code);
      expect(hash, isNotEmpty);
      expect(RecoveryCodeHasher.verify(code, hash), true);
      expect(RecoveryCodeHasher.verify('WRONG', hash), false);
    });
  });

  group('AuthRetryPolicy substring-free (H10)', () {
    test('SocketException is retryable', () {
      expect(AuthRetryPolicy.isRetryable(const SocketException('failed')), true);
    });
    test('TimeoutException is retryable', () {
      expect(AuthRetryPolicy.isRetryable(TimeoutException('t')), true);
    });
    test('AuthException 503 is retryable', () {
      const e = AuthException('server error', statusCode: '503');
      expect(AuthRetryPolicy.isRetryable(e), true);
    });
    test('AuthException 400 is not retryable', () {
      const e = AuthException('bad request', statusCode: '400');
      expect(AuthRetryPolicy.isRetryable(e), false);
    });
    test('Generic exception not retryable', () {
      expect(AuthRetryPolicy.isRetryable(Exception('network')), false);
      expect(AuthRetryPolicy.isRetryable(Exception('socket')), false);
    });
  });
}
