import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/core/utils/auth_retry.dart';
import 'package:aiproject/services/auth/password_hasher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AuthRetryPolicy (Bug 3: offline register fallback)', () {
    test('AuthRetryableFetchException is always retryable', () {
      // gotrue >=2.27 wraps ALL network errors as AuthRetryableFetchException
      // with statusCode: null — it must be retryable or savePendingSignup is
      // never reached while offline.
      final e = AuthRetryableFetchException();
      expect(e.statusCode, isNull);
      expect(AuthRetryPolicy.isRetryable(e), true);
    });

    test(
      'AuthRetryableFetchException with a status code is still retryable',
      () {
        final e = AuthRetryableFetchException(statusCode: null);
        expect(AuthRetryPolicy.isRetryable(e), true);
      },
    );

    test('AuthException retryable status codes unchanged', () {
      expect(
        AuthRetryPolicy.isRetryable(
          const AuthException('x', statusCode: '408'),
        ),
        true,
      );
      expect(
        AuthRetryPolicy.isRetryable(
          const AuthException('x', statusCode: '429'),
        ),
        true,
      );
      expect(
        AuthRetryPolicy.isRetryable(
          const AuthException('x', statusCode: '500'),
        ),
        true,
      );
      expect(
        AuthRetryPolicy.isRetryable(
          const AuthException('x', statusCode: '503'),
        ),
        true,
      );
    });

    test('AuthException non-retryable status codes unchanged', () {
      expect(
        AuthRetryPolicy.isRetryable(
          const AuthException('x', statusCode: '400'),
        ),
        false,
      );
      expect(
        AuthRetryPolicy.isRetryable(
          const AuthException('x', statusCode: '401'),
        ),
        false,
      );
      expect(
        AuthRetryPolicy.isRetryable(
          const AuthException('x', statusCode: '403'),
        ),
        false,
      );
    });

    test('network exceptions are retryable', () {
      expect(
        AuthRetryPolicy.isRetryable(const SocketException('offline')),
        true,
      );
      expect(AuthRetryPolicy.isRetryable(TimeoutException('timeout')), true);
    });
  });

  group('Local account validation (Bug 4: offline sign-in regression)', () {
    test('PasswordHasher roundtrip for locally stored accounts', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashWithSalt('MyNewPass1', salt);
      expect(PasswordHasher.verify('MyNewPass1', salt, hash), true);
    });

    test('validation still rejects wrong password and empty inputs', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashWithSalt('MyNewPass1', salt);
      expect(PasswordHasher.verify('wrongPass1', salt, hash), false);
      expect(PasswordHasher.verify('', salt, hash), false);
      expect(PasswordHasher.verify('MyNewPass1', '', hash), false);
      expect(PasswordHasher.verify('MyNewPass1', salt, ''), false);
    });

    test('fresh salt per account produces independent hashes', () {
      final saltA = PasswordHasher.generateSalt();
      final saltB = PasswordHasher.generateSalt();
      expect(saltA, isNot(equals(saltB)));
      expect(
        PasswordHasher.hashWithSalt('MyNewPass1', saltA),
        isNot(equals(PasswordHasher.hashWithSalt('MyNewPass1', saltB))),
      );
    });
  });
}
