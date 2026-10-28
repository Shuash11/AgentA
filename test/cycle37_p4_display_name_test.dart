// Cycle 37 · P4 — Edit-Profile display-name fix.
//
// What is exercised here:
//  * The display-name save (UserRepository's DisplayNameSaver): every write
//    outcome is observable — success, the profiles row blocked (RLS → 0
//    rows), the row write failing and the Auth write failing. A blocked row
//    write must abort BEFORE the Auth write, so the Auth metadata never
//    holds a value the database does not.
//  * The device copy: the local row's display_name follows the edit, so an
//    offline account never keeps the name it was created with.
//  * The profile screen: a saved name is on screen again the moment the
//    edit screen pops (the refresh-on-pop), and the self-heal never
//    overwrites an Auth name that is already there.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:aiproject/cubit/theme/theme_cubit.dart';
import 'package:aiproject/cubit/update/update_cubit.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/local_user_dao.dart';
import 'package:aiproject/data/models/user_profile_model.dart';
import 'package:aiproject/presentation/profile/editprofile.dart';
import 'package:aiproject/presentation/profile/profilepage.dart';
import 'package:aiproject/repositories/user_repository.dart';
import 'package:aiproject/services/update/version_check_service.dart';
import 'package:aiproject/services/update/version_source.dart';

const String _uid = 'uid-1';
const String _email = 'user@example.com';

Future<void> _createSchema(Database db) async {
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

/// A fake profile data gate — the page never touches Supabase statics
/// directly, so every outcome (row present / missing, Auth name present /
/// absent) is driven from here.
class _FakeProfileGate extends ProfileDataGate {
  _FakeProfileGate({this.user, this.profileName});

  ProfileUser? user;
  String? profileName;
  int profileLoads = 0;
  final List<String> backfills = [];

  @override
  ProfileUser? loadUser() => user;

  @override
  Future<UserProfileModel?> loadProfile(String uid) async {
    profileLoads++;
    final name = profileName;
    if (name == null) return null;
    return UserProfileModel(
      uid: uid,
      displayName: name,
      email: _email,
      recoveryCode: '',
    );
  }

  @override
  Future<void> backfillDisplayName(String displayName) async {
    backfills.add(displayName);
  }
}

/// A version source that never touches the network — the profile screen
/// renders the update row, the cubit must not call out.
class _FakeVersionSource implements VersionSource {
  @override
  Future<ReleaseFetchResult> fetchLatestRelease() async =>
      const ReleaseNotFound();

  @override
  DateTime? get backoffUntil => null;
}

/// Drives the route transition to its end. The bound keeps a stuck
/// animation from spinning the suite (the profile spinner animates
/// forever, so this is only used once the screen is loaded).
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

void main() {
  late Database db;
  final dao = LocalUserDao();

  setUpAll(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async => _createSchema(db),
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
    await dao.savePendingSignup(
      localId: _uid,
      email: _email,
      password: 'hash',
      displayName: 'Old Name',
      recoveryCode: 'hash',
    );
  });

  group('DisplayNameSaver — write outcomes (cycle-37 P4)', () {
    test('a successful save writes the row, then the Auth metadata', () async {
      final calls = <String>[];
      final saver = DisplayNameSaver(
        writeProfileRow: (uid, name) async {
          calls.add('row:$uid:$name');
          return 1;
        },
        writeAuthMetadata: (name) async {
          calls.add('auth:$name');
        },
        localUserDao: dao,
      );

      await saver.save(uid: _uid, displayName: 'New Name');

      expect(calls, ['row:$_uid:New Name', 'auth:New Name']);
    });

    test('a blocked row write (0 rows) aborts before the Auth write', () async {
      var authWrites = 0;
      final saver = DisplayNameSaver(
        writeProfileRow: (uid, name) async => 0,
        writeAuthMetadata: (name) async => authWrites++,
        localUserDao: dao,
      );

      await expectLater(
        saver.save(uid: _uid, displayName: 'New Name'),
        throwsA(
          isA<DisplayNameSaveException>().having(
            (e) => e.failure,
            'failure',
            DisplayNameSaveFailure.profileRowBlocked,
          ),
        ),
      );
      // The Auth metadata must never hold a value the database rejected.
      expect(authWrites, 0);
    });

    test('a failing row write aborts before the Auth write', () async {
      var authWrites = 0;
      final saver = DisplayNameSaver(
        writeProfileRow: (uid, name) async => throw Exception('network down'),
        writeAuthMetadata: (name) async => authWrites++,
        localUserDao: dao,
      );

      await expectLater(
        saver.save(uid: _uid, displayName: 'New Name'),
        throwsA(
          isA<DisplayNameSaveException>().having(
            (e) => e.failure,
            'failure',
            DisplayNameSaveFailure.profileRowFailed,
          ),
        ),
      );
      expect(authWrites, 0);
    });

    test('a failing Auth write is reported, not swallowed', () async {
      var rowWrites = 0;
      final saver = DisplayNameSaver(
        writeProfileRow: (uid, name) async {
          rowWrites++;
          return 1;
        },
        writeAuthMetadata: (name) async => throw Exception('auth rejected'),
        localUserDao: dao,
      );

      await expectLater(
        saver.save(uid: _uid, displayName: 'New Name'),
        throwsA(
          isA<DisplayNameSaveException>().having(
            (e) => e.failure,
            'failure',
            DisplayNameSaveFailure.authFailed,
          ),
        ),
      );
      expect(rowWrites, 1);
    });

    test(
      'the device copy follows the edit, even when the row is blocked',
      () async {
        final saver = DisplayNameSaver(
          writeProfileRow: (uid, name) async => 0,
          writeAuthMetadata: (name) async {},
          localUserDao: dao,
        );

        await expectLater(
          saver.save(uid: _uid, displayName: 'New Name'),
          throwsA(isA<DisplayNameSaveException>()),
        );

        // The offline account keeps the name the user entered on the device.
        final row = await dao.getPendingSignupByLocalId(_uid);
        expect(row!['display_name'], 'New Name');
      },
    );

    test('the shipped entry point aborts a blocked row write', () async {
      var authWrites = 0;
      UserRepository.displayNameSaverOverride = DisplayNameSaver(
        writeProfileRow: (uid, name) async => 0,
        writeAuthMetadata: (name) async => authWrites++,
        localUserDao: dao,
      );
      addTearDown(() => UserRepository.displayNameSaverOverride = null);

      await expectLater(
        UserRepository.updateDisplayName(_uid, 'New Name'),
        throwsA(
          isA<DisplayNameSaveException>().having(
            (e) => e.failure,
            'failure',
            DisplayNameSaveFailure.profileRowBlocked,
          ),
        ),
      );
      // The Auth metadata must never hold a value the database rejected.
      expect(authWrites, 0);
    });
  });

  group('LocalUserDao.updateDisplayName (cycle-37 P4)', () {
    test('updates the row of that account only', () async {
      await dao.savePendingSignup(
        localId: 'uid-2',
        email: _email,
        password: 'hash',
        displayName: 'Other Name',
        recoveryCode: 'hash',
      );

      final updated = await dao.updateDisplayName(
        localId: _uid,
        displayName: 'New Name',
      );

      expect(updated, 1);
      final row = await dao.getPendingSignupByLocalId(_uid);
      expect(row!['display_name'], 'New Name');
      final other = await dao.getPendingSignupByLocalId('uid-2');
      expect(other!['display_name'], 'Other Name');
    });

    test('reports 0 rows for an account this device does not hold', () async {
      final updated = await dao.updateDisplayName(
        localId: 'unknown-uid',
        displayName: 'New Name',
      );

      expect(updated, 0);
    });
  });

  group('ProfilePage (cycle-37 P4)', () {
    late VersionCheckService service;
    late UpdateCubit cubit;

    setUp(() {
      service = VersionCheckService(
        source: _FakeVersionSource(),
        enabled: true,
      );
      cubit = UpdateCubit(service: service);
    });

    tearDown(() async {
      await cubit.close();
      service.dispose();
    });

    Future<void> pumpProfile(WidgetTester tester, ProfileDataGate gate) async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
            BlocProvider<UpdateCubit>.value(value: cubit),
          ],
          child: MaterialApp(
            home: ProfilePage(showBottomNav: false, dataGate: gate),
          ),
        ),
      );
      // The first frame shows the loading spinner; the load resolves in a
      // microtask, so a plain pump (not pumpAndSettle — the spinner
      // animates forever) is the right tool here.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the saved name is on screen again after the edit pops', (
      tester,
    ) async {
      final gate = _FakeProfileGate(
        user: const ProfileUser(id: _uid, email: _email),
        profileName: 'Old Name',
      );
      await pumpProfile(tester, gate);
      expect(find.text('Old Name'), findsOneWidget);

      // The user saves a new name in the edit screen.
      gate.profileName = 'New Name';

      await tester.tap(find.text('Edit Profile'));
      await _settle(tester);
      expect(find.byType(EditProfilePage), findsOneWidget);
      expect(find.text('Old Name'), findsNothing);

      // Leaving the edit screen reloads the profile.
      await tester.tap(find.byTooltip('Back'));
      await _settle(tester);

      expect(find.text('New Name'), findsOneWidget);
      expect(find.text('Old Name'), findsNothing);
      expect(gate.profileLoads, greaterThan(1));
    });

    testWidgets('the self-heal never overwrites an Auth name that is there', (
      tester,
    ) async {
      final gate = _FakeProfileGate(
        user: const ProfileUser(
          id: _uid,
          email: _email,
          metadata: {'display_name': '', 'full_name': 'Fresh Name'},
        ),
        profileName: 'Stale Db Name',
      );
      await pumpProfile(tester, gate);

      expect(gate.backfills, isEmpty);
    });

    testWidgets('the self-heal fills an Auth name that is missing', (
      tester,
    ) async {
      final gate = _FakeProfileGate(
        user: const ProfileUser(id: _uid, email: _email),
        profileName: 'Db Name',
      );
      await pumpProfile(tester, gate);

      expect(gate.backfills, ['Db Name']);
      expect(find.text('Db Name'), findsOneWidget);
    });
  });
}
