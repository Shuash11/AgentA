import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/services/auth/password_hasher.dart';

/// F6/C5 password-hash hardening: Argon2id PHC hashes + forever-valid
/// legacy salted-SHA256 verification.
void main() {
  // Golden legacy row as written by pre-F6 code: 16-byte salt b64url-encoded,
  // SHA256(salt + password) hex.
  const legacySalt = 'AQIDBAUGBwgJCgsMDQ4PEA';
  const legacyHash =
      '4d766229590ec516284813bead12f1e6777f5e761b82555e9e0baa6f329a99ac';

  // Deterministic Argon2id m=19456,t=2,p=1 v=19 hash of the same password
  // with the same 16 salt bytes (computed once, pinned as a vector).
  const phcHash =
      r'$argon2id$v=19$m=19456,t=2,p=1$AQIDBAUGBwgJCgsMDQ4PEA$jDr+t5EgO1Crdy5SpbpDjHh9EDJJJzZADiI4bwGERUY';

  group('legacy salted-SHA256 verification (unchanged behavior)', () {
    test('golden legacy vector verifies and is flagged for upgrade', () {
      final result = PasswordHasher.verifyPassword(
        'CorrectHorse1',
        storedHash: legacyHash,
        storedSalt: legacySalt,
      );
      expect(result.matched, true);
      expect(result.isLegacy, true);
      expect(result.needsUpgrade, true);
    });

    test('wrong legacy password is a miss without upgrade flag', () {
      final result = PasswordHasher.verifyPassword(
        'WrongHorse1',
        storedHash: legacyHash,
        storedSalt: legacySalt,
      );
      expect(result.matched, false);
      expect(result.needsUpgrade, false);
    });

    test('legacy guards: empty hash, empty salt, malformed shapes', () {
      expect(
        PasswordHasher.verifyPassword(
          'CorrectHorse1',
          storedHash: '',
          storedSalt: legacySalt,
        ).matched,
        false,
      );
      expect(
        PasswordHasher.verifyPassword(
          'CorrectHorse1',
          storedHash: legacyHash,
          storedSalt: '',
        ).matched,
        false,
      );
      expect(
        PasswordHasher.verifyPassword(
          'CorrectHorse1',
          storedHash: 'not-a-64-hex-hash',
          storedSalt: legacySalt,
        ).matched,
        false,
      );
      // Uppercase hex was never produced by sha256.toString(); miss.
      expect(
        PasswordHasher.verifyPassword(
          'CorrectHorse1',
          storedHash: legacyHash.toUpperCase(),
          storedSalt: legacySalt,
        ).matched,
        false,
      );
    });

    test('legacy bool alias verify() keeps its old contract', () {
      expect(
        PasswordHasher.verify('CorrectHorse1', legacySalt, legacyHash),
        true,
      );
      expect(
        PasswordHasher.verify('WrongHorse1', legacySalt, legacyHash),
        false,
      );
      expect(PasswordHasher.verify('CorrectHorse1', '', legacyHash), false);
      expect(PasswordHasher.verify('CorrectHorse1', legacySalt, ''), false);
    });
  });

  group('Argon2id PHC verification', () {
    test('golden PHC vector verifies as the current scheme', () {
      final result = PasswordHasher.verifyPassword(
        'CorrectHorse1',
        storedHash: phcHash,
        storedSalt: '',
      );
      expect(result.matched, true);
      expect(result.isLegacy, false);
      expect(result.needsUpgrade, false);
    });

    test('PHC verification ignores any legacy salt column value', () {
      final result = PasswordHasher.verifyPassword(
        'CorrectHorse1',
        storedHash: phcHash,
        storedSalt: 'stale-salt-column',
      );
      expect(result.matched, true);
    });

    test('wrong password on a PHC hash is a miss', () {
      final result = PasswordHasher.verifyPassword(
        'WrongHorse1',
        storedHash: phcHash,
        storedSalt: '',
      );
      expect(result.matched, false);
      expect(result.needsUpgrade, false);
    });

    test(
      'hashPassword round-trip: unique salts, fixed params, fixed lengths',
      () {
        final first = PasswordHasher.hashPassword('CorrectHorse1');
        final second = PasswordHasher.hashPassword('CorrectHorse1');

        expect(first, isNot(equals(second))); // fresh random salt each time
        expect(first.startsWith(r'$argon2id$v=19$m=19456,t=2,p=1$'), true);

        final parts = first.split(r'$');
        expect(parts.length, 6);
        expect(parts[4].length, 22); // 16-byte salt in B64
        expect(parts[5].length, 43); // 32-byte tag in B64

        expect(
          PasswordHasher.verifyPassword(
            'CorrectHorse1',
            storedHash: first,
            storedSalt: '',
          ).matched,
          true,
        );
        expect(
          PasswordHasher.verifyPassword(
            'CorrectHorse1',
            storedHash: second,
            storedSalt: '',
          ).matched,
          true,
        );
      },
    );

    test('malformed or foreign prefixed hashes miss without throwing', () {
      const malformed = <String>[
        r'$argon2id$garbage',
        r'$argon2id$v=19$'
            r'm=19456$AQIDBAUGBwgJCgsMDQ4PEA$t5EgO1Crdy5SpbpDjHh9EDJJJzZADiI4bwGERUY', // missing t,p
        r'$argon2id$v=20$m=19456,t=2,p=1$AQIDBAUGBwgJCgsMDQ4PEA$jDr+t5EgO1Crdy5SpbpDjHh9EDJJJzZADiI4bwGERUY', // future version
        r'$scrypt$v=19$m=19456,t=2,p=1$AQIDBAUGBwgJCgsMDQ4PEA$jDr+t5EgO1Crdy5SpbpDjHh9EDJJJzZADiI4bwGERUY', // unknown scheme
        r'$argon2id$v=19$m=19456,t=2,p=1$@@@@$jDr+t5EgO1Crdy5SpbpDjHh9EDJJJzZADiI4bwGERUY', // bad b64
        r'$argon2id$v=19$m=19456,t=2,p=1$AQIDBAUGBwgJCgsMDQ4PEA$AQID', // short tag
        r'$argon2id$v=19$m=999999999,t=2,p=1$AQIDBAUGBwgJCgsMDQ4PEA$jDr+t5EgO1Crdy5SpbpDjHh9EDJJJzZADiI4bwGERUY', // unbounded memory
        r'$argon2id$v=19$m=19456,m=19456,t=2,p=1$AQIDBAUGBwgJCgsMDQ4PEA$jDr+t5EgO1Crdy5SpbpDjHh9EDJJJzZADiI4bwGERUY', // duplicate param
      ];
      for (final stored in malformed) {
        final result = PasswordHasher.verifyPassword(
          'CorrectHorse1',
          storedHash: stored,
          storedSalt: '',
        );
        expect(result.matched, false, reason: stored);
        expect(result.needsUpgrade, false, reason: stored);
      }
    });

    test('bool alias verify() accepts a PHC hash and empty legacy salt', () {
      expect(PasswordHasher.verify('CorrectHorse1', '', phcHash), true);
      expect(PasswordHasher.verify('WrongHorse1', '', phcHash), false);
    });
  });
}
