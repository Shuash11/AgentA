import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/local_user_dao.dart';

/// F6/C5: compare-and-swap hash upgrade helper — atomic, stale-safe, and the
/// best-effort wrapper never throws (an upgrade failure cannot block login).
void main() {
  late Database db;
  final dao = LocalUserDao();

  const legacySalt = 'AQIDBAUGBwgJCgsMDQ4PEA';
  const legacyHash =
      '4d766229590ec516284813bead12f1e6777f5e761b82555e9e0baa6f329a99ac';
  const newHash =
      r'$argon2id$v=19$m=19456,t=2,p=1$AQIDBAUGBwgJCgsMDQ4PEA$jDr+t5EgO1Crdy5SpbpDjHh9EDJJJzZADiI4bwGERUY';

  Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE pending_signups (
        local_id TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        password TEXT NOT NULL,
        display_name TEXT NOT NULL,
        recovery_code TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_synced INTEGER DEFAULT 0,
        provider TEXT DEFAULT 'password',
        password_salt TEXT DEFAULT ''
      )
    ''');
  }

  Future<void> seedLegacyRow() async {
    await dao.savePendingSignup(
      localId: 'row-1',
      email: 'user@example.com',
      password: legacyHash,
      displayName: 'User',
      recoveryCode: '',
      passwordSalt: legacySalt,
    );
  }

  setUpAll(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async => createSchema(db),
      ),
    );
    DatabaseHelper.testDatabase = db;
  });

  tearDownAll(() async {
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  setUp(() async {
    await db.delete('pending_signups');
  });

  test(
    'upgradePasswordHash rewrites the row and clears password_salt',
    () async {
      await seedLegacyRow();

      final updated = await dao.upgradePasswordHash(
        localId: 'row-1',
        expectedHash: legacyHash,
        newHash: newHash,
      );

      expect(updated, 1);
      final row = await dao.getPendingSignupByLocalId('row-1');
      expect(row!['password'], newHash);
      expect(row['password_salt'], '');
    },
  );

  test('stale expectedHash is a no-op (compare-and-swap)', () async {
    await seedLegacyRow();

    final updated = await dao.upgradePasswordHash(
      localId: 'row-1',
      expectedHash: 'deadbeef' * 8, // no longer the stored value
      newHash: newHash,
    );

    expect(updated, 0);
    final row = await dao.getPendingSignupByLocalId('row-1');
    expect(row!['password'], legacyHash);
    expect(row['password_salt'], legacySalt);
  });

  test('tryUpgradePasswordHash returns true on a successful upgrade', () async {
    await seedLegacyRow();

    final upgraded = await dao.tryUpgradePasswordHash(
      localId: 'row-1',
      expectedHash: legacyHash,
      newHash: newHash,
    );

    expect(upgraded, true);
  });

  test(
    'tryUpgradePasswordHash never throws when the database is broken',
    () async {
      // A closed database makes every query throw; the wrapper must swallow it
      // (login must never fail because the post-auth upgrade could not run).
      final brokenDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      DatabaseHelper.testDatabase = brokenDb;
      await brokenDb.close();

      final upgraded = await dao.tryUpgradePasswordHash(
        localId: 'row-1',
        expectedHash: legacyHash,
        newHash: newHash,
      );

      expect(upgraded, false);
      DatabaseHelper.testDatabase = db; // restore for teardown
    },
  );
}
