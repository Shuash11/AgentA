// Cycle 31 · phase P4 — offline password change for never-synced accounts.
//
// Test file name fixed by phase P4 (plan: plans/cycle-31-second-factor-password-change.md;
// P5 consumes this file name).
//
// What is exercised here:
//  * OfflinePasswordService.updateLocalPassword against the REAL
//    LocalUserDao (sqflite_common_ffi in-memory DB — the
//    local_user_dao_upgrade_test pattern): proof order, inherited
//    OfflineLoginGuard lockout/wipe semantics, CAS behaviour, and the new
//    hash verifying with PasswordHasher.verifyPassword — the exact call the
//    offline sign-in path makes, so the next offline sign-in accepts the
//    new password.
//  * The page's offline branch (ChangePasswordPage with no Supabase user):
//    the P3 pre-probe pattern, degrade + notice, failure copy mapping, and
//    that no online factor ever runs on this class.
//  * Zero connectivity: the page tests run with an OFFLINE connectivity
//    cubit (airplane-mode equivalent) and the service path touches no
//    network layer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:aiproject/core/utils/connectivity_service.dart';
import 'package:aiproject/cubit/connectivity/connectivity_cubit.dart';
import 'package:aiproject/cubit/theme/theme_cubit.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/local_user_dao.dart';
import 'package:aiproject/presentation/profile/change_pass_page.dart';
import 'package:aiproject/services/auth/offline_login_guard.dart';
import 'package:aiproject/services/auth/offline_password_service.dart';
import 'package:aiproject/services/auth/password_hasher.dart';

const MethodChannel _localAuthChannel = MethodChannel(
  'plugins.flutter.io/local_auth',
);

const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

// ── channel mock state (local_auth + secure storage) ──────────────────────

bool _deviceSupported = true;
List<String> _enrolledBiometrics = <String>['fingerprint'];
bool _authResult = true;
final List<MethodCall> _localAuthCalls = <MethodCall>[];

String? _sessionUid = 'row-1';
String _sessionEmail = 'user@example.com';

/// Installs the method-channel mocks: local_auth answers the pre-probe and
/// the prompt, secure storage serves a saved local session (the P2 test's
/// approach, extended with per-key values).
void _installChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_localAuthChannel, (call) async {
    _localAuthCalls.add(call);
    switch (call.method) {
      case 'isDeviceSupported':
        return _deviceSupported;
      // local_auth's `canCheckBiometrics` is derived from the enrolled
      // biometrics list, not a dedicated channel method:
      // local_auth_platform_interface default_method_channel_platform.dart
      // deviceSupportsBiometrics() -> 'getAvailableBiometrics' non-empty.
      case 'getAvailableBiometrics':
        return _enrolledBiometrics;
      case 'authenticate':
        return _authResult;
    }
    return null;
  });
  messenger.setMockMethodCallHandler(_secureStorageChannel, (call) async {
    if (call.method == 'read') {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      switch (args['key']) {
        case 'session_uid':
          return _sessionUid;
        case 'session_email':
          return _sessionEmail;
        case 'session_provider':
          return 'password';
      }
    }
    return null;
  });
}

void _removeChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_localAuthChannel, null);
  messenger.setMockMethodCallHandler(_secureStorageChannel, null);
}

// ── page fakes (the project's fake-service pattern) ───────────────────────

/// Fake [ConnectivityService] — the cubit emits [initial] at construction.
class _FakeConnectivity implements ConnectivityService {
  _FakeConnectivity({this.initial = InternetStatus.offline});

  final InternetStatus initial;
  final _controller = StreamController<InternetStatus>.broadcast();

  @override
  Stream<InternetStatus> get statusStream => _controller.stream;

  @override
  InternetStatus get lastStatus => initial;

  @override
  Future<void> init() async {}

  @override
  void dispose() => _controller.close();

  @override
  Future<bool> isOnline() async => initial == InternetStatus.online;

  @override
  Future<InternetStatus> checkInternetStatus() async => initial;
}

/// Fake online factor gate — records calls so a test can prove the online
/// path is never taken for a session with no Supabase user.
class _FakeGate extends PasswordChangeFactorGate {
  _FakeGate({this.session});

  final PasswordChangeSession? session;
  final List<String> calls = <String>[];

  @override
  PasswordChangeSession? loadSession() => session;

  @override
  Future<void> reauthenticate(String email, String password) async {
    calls.add('reauthenticate');
  }

  @override
  Future<bool> verifyGoogleReauth(String expectedEmail) async {
    calls.add('verifyGoogleReauth');
    return true;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
  }

  @override
  Future<bool> deviceCredentialPromptAvailable() async {
    calls.add('deviceCredentialPromptAvailable');
    return true;
  }

  @override
  Future<bool> confirmDeviceCredential(String localizedReason) async {
    calls.add('confirmDeviceCredential');
    return true;
  }
}

/// Fake offline service — records the call order and lets each test drive
/// every outcome. No method touches the DAO or the platform channels.
class _FakeOfflineService extends OfflinePasswordService {
  final List<String> calls = <String>[];
  bool deviceAvailable = true;
  OfflinePasswordChangeFailure? failure;
  Object? error;

  String? currentPasswordSeen;
  String? newPasswordSeen;
  String? reasonSeen;

  @override
  Future<bool> deviceCredentialPromptAvailable() async {
    calls.add('deviceCredentialPromptAvailable');
    return deviceAvailable;
  }

  @override
  Future<void> updateLocalPassword({
    required String currentPassword,
    required String newPassword,
    required String localizedReason,
  }) async {
    calls.add('updateLocalPassword');
    currentPasswordSeen = currentPassword;
    newPasswordSeen = newPassword;
    reasonSeen = localizedReason;
    if (error != null) throw error!;
    if (failure != null) throw OfflinePasswordChangeException(failure!);
  }
}

/// DAO whose compare-and-swap never matches — simulates a concurrent
/// change/sync landing between the verify and the write.
class _StaleRowDao extends LocalUserDao {
  _StaleRowDao({required this.storedHash});

  final String storedHash;

  @override
  Future<Map<String, dynamic>?> getUserByEmail(String email) async => {
    'local_id': 'row-1',
    'email': email,
    'password': storedHash,
    'password_salt': _legacySalt,
    'provider': 'password',
    'is_synced': 0,
  };

  @override
  Future<int> updateUnsyncedPasswordHash({
    required String localId,
    required String expectedHash,
    required String newHash,
  }) async => 0;
}

const String _legacySalt = 'AQIDBAUGBwgJCgsMDQ4PEA';

const String _promptReason = 'Confirm your identity to change your password';

/// Asserts that [run] throws [OfflinePasswordChangeException] with [expected]
/// as its reason.
Future<void> _expectFailure(
  Future<void> Function() run,
  OfflinePasswordChangeFailure expected,
) async {
  try {
    await run();
    fail('expected OfflinePasswordChangeFailure.$expected');
  } on OfflinePasswordChangeException catch (e) {
    expect(e.reason, expected);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  final dao = LocalUserDao();

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

  /// Seeds a local account row. [legacy] stores a salted-SHA256 hash instead
  /// of Argon2id so the hammer tests stay fast; the guard semantics do not
  /// depend on the scheme.
  Future<void> seed({
    String localId = 'row-1',
    String email = 'user@example.com',
    String password = 'OldPass123!',
    bool synced = false,
    String provider = 'password',
    bool legacy = false,
  }) async {
    final isGoogle = provider == 'google';
    final hash = isGoogle
        ? ''
        : legacy
        ? PasswordHasher.hashWithSalt(password, _legacySalt)
        : PasswordHasher.hashPassword(password);
    await dao.savePendingSignup(
      localId: localId,
      email: email,
      password: hash,
      displayName: 'User',
      recoveryCode: '',
      isSynced: synced,
      provider: provider,
      passwordSalt: legacy ? _legacySalt : '',
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
    _installChannelMocks();
    _localAuthCalls.clear();
    _deviceSupported = true;
    _enrolledBiometrics = <String>['fingerprint'];
    _authResult = true;
    _sessionUid = 'row-1';
    _sessionEmail = 'user@example.com';
    OfflineLoginGuard.resetForTest();
    await db.delete('pending_signups');
  });

  tearDown(_removeChannelMocks);

  group('OfflinePasswordService.updateLocalPassword (cycle-31 P4)', () {
    test('changes the never-synced password; the new hash verifies and the '
        'old one does not', () async {
      await seed();
      final service = OfflinePasswordService();

      await service.updateLocalPassword(
        currentPassword: 'OldPass123!',
        newPassword: 'NewPass456!',
        localizedReason: _promptReason,
      );

      final row = (await dao.getPendingSignupByLocalId('row-1'))!;
      final newHash = row['password'] as String;
      final storedSalt = (row['password_salt'] as String?) ?? '';
      // The exact call shape the offline sign-in path makes
      // (login.dart:409-413): with the row's new hash the next offline
      // sign-in accepts the new password...
      expect(
        PasswordHasher.verifyPassword(
          'NewPass456!',
          storedHash: newHash,
          storedSalt: storedSalt,
        ).matched,
        isTrue,
      );
      // ...and rejects the old one.
      expect(
        PasswordHasher.verifyPassword(
          'OldPass123!',
          storedHash: newHash,
          storedSalt: storedSalt,
        ).matched,
        isFalse,
      );
      expect(storedSalt, '');

      // The device prompt ran exactly once, with the step-up wording.
      final prompts = _localAuthCalls
          .where((c) => c.method == 'authenticate')
          .toList();
      expect(prompts, hasLength(1));
      final args = Map<Object?, Object?>.from(prompts.single.arguments as Map);
      expect(args['localizedReason'], _promptReason);
      expect(args['biometricOnly'], isFalse);
    });

    test('a canceled device prompt aborts with the row untouched', () async {
      await seed(legacy: true);
      _authResult = false;

      await _expectFailure(
        () => OfflinePasswordService().updateLocalPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'NewPass456!',
          localizedReason: _promptReason,
        ),
        OfflinePasswordChangeFailure.deviceCancelled,
      );

      // The prompt WAS shown (cancel is not a degrade)...
      expect(
        _localAuthCalls.where((c) => c.method == 'authenticate'),
        hasLength(1),
      );
      // ...and the row still holds the old credential.
      final row = (await dao.getPendingSignupByLocalId('row-1'))!;
      expect(
        PasswordHasher.verifyPassword(
          'OldPass123!',
          storedHash: row['password'] as String,
          storedSalt: row['password_salt'] as String,
        ).matched,
        isTrue,
      );
    });

    test('no screen lock degrades: the change completes with no prompt '
        'call', () async {
      await seed(legacy: true);
      // No screen lock: neither probe of the cycle-32 OR gate is available
      // (no enrolled biometrics AND no device credential) — the pre-probe
      // degrades (fail-open).
      _deviceSupported = false;
      _enrolledBiometrics = <String>[];

      await OfflinePasswordService().updateLocalPassword(
        currentPassword: 'OldPass123!',
        newPassword: 'NewPass456!',
        localizedReason: _promptReason,
      );

      expect(_localAuthCalls.where((c) => c.method == 'authenticate'), isEmpty);
      final row = (await dao.getPendingSignupByLocalId('row-1'))!;
      expect(
        PasswordHasher.verifyPassword(
          'NewPass456!',
          storedHash: row['password'] as String,
          storedSalt: '',
        ).matched,
        isTrue,
      );
    });

    test(
      'a wrong current password is rejected, recorded, and never prompts',
      () async {
        await seed(legacy: true);

        await _expectFailure(
          () => OfflinePasswordService().updateLocalPassword(
            currentPassword: 'WrongPass!',
            newPassword: 'NewPass456!',
            localizedReason: _promptReason,
          ),
          OfflinePasswordChangeFailure.wrongPassword,
        );

        expect(OfflineLoginGuard.failureCountForTest('user@example.com'), 1);
        expect(
          _localAuthCalls.where((c) => c.method == 'authenticate'),
          isEmpty,
        );
        final row = (await dao.getPendingSignupByLocalId('row-1'))!;
        expect(
          PasswordHasher.verifyPassword(
            'OldPass123!',
            storedHash: row['password'] as String,
            storedSalt: row['password_salt'] as String,
          ).matched,
          isTrue,
        );
      },
    );

    test('five failures lock the account out (inherited guard '
        'semantics)', () async {
      await seed(legacy: true);
      final service = OfflinePasswordService();

      for (var attempt = 0; attempt < 5; attempt++) {
        await _expectFailure(
          () => service.updateLocalPassword(
            currentPassword: 'WrongPass!',
            newPassword: 'NewPass456!',
            localizedReason: _promptReason,
          ),
          OfflinePasswordChangeFailure.wrongPassword,
        );
      }
      expect(OfflineLoginGuard.isLockedOut('user@example.com'), isTrue);

      // Even the correct password is refused while the window is active.
      await _expectFailure(
        () => service.updateLocalPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'NewPass456!',
          localizedReason: _promptReason,
        ),
        OfflinePasswordChangeFailure.lockedOut,
      );
      expect(_localAuthCalls.where((c) => c.method == 'authenticate'), isEmpty);
    });

    test('a successful change clears the recorded failures', () async {
      await seed(legacy: true);
      final service = OfflinePasswordService();

      // Two wrong attempts are recorded...
      for (var attempt = 0; attempt < 2; attempt++) {
        await _expectFailure(
          () => service.updateLocalPassword(
            currentPassword: 'WrongPass!',
            newPassword: 'NewPass456!',
            localizedReason: _promptReason,
          ),
          OfflinePasswordChangeFailure.wrongPassword,
        );
      }
      expect(OfflineLoginGuard.failureCountForTest('user@example.com'), 2);

      // ...and a successful change clears the window (the offline sign-in
      // contract). Note: the guard's 5-attempt lockout means its 10-failure
      // wipe threshold is not reachable by hammering one screen — the wipe
      // call site is inherited verbatim from the offline sign-in path.
      await service.updateLocalPassword(
        currentPassword: 'OldPass123!',
        newPassword: 'NewPass456!',
        localizedReason: _promptReason,
      );
      expect(OfflineLoginGuard.failureCountForTest('user@example.com'), 0);
    });

    test('a synced row is refused offline (its credential lives '
        'online)', () async {
      await seed(synced: true);
      await _expectFailure(
        () => OfflinePasswordService().updateLocalPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'NewPass456!',
          localizedReason: _promptReason,
        ),
        OfflinePasswordChangeFailure.accountRequiresOnline,
      );
    });

    test('a google-provider row is refused offline', () async {
      await seed(provider: 'google', password: '');
      await _expectFailure(
        () => OfflinePasswordService().updateLocalPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'NewPass456!',
          localizedReason: _promptReason,
        ),
        OfflinePasswordChangeFailure.accountRequiresOnline,
      );
    });

    test('no local session reports noSession', () async {
      _sessionUid = null;
      _sessionEmail = '';
      await _expectFailure(
        () => OfflinePasswordService().updateLocalPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'NewPass456!',
          localizedReason: _promptReason,
        ),
        OfflinePasswordChangeFailure.noSession,
      );
    });

    test('a missing row reports accountNotFound', () async {
      await _expectFailure(
        () => OfflinePasswordService().updateLocalPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'NewPass456!',
          localizedReason: _promptReason,
        ),
        OfflinePasswordChangeFailure.accountNotFound,
      );
    });

    test('a lost compare-and-swap race reports updateConflict', () async {
      final staleDao = _StaleRowDao(
        storedHash: PasswordHasher.hashWithSalt('OldPass123!', _legacySalt),
      );
      await _expectFailure(
        () => OfflinePasswordService(userDao: staleDao).updateLocalPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'NewPass456!',
          localizedReason: _promptReason,
        ),
        OfflinePasswordChangeFailure.updateConflict,
      );
    });
  });

  group('LocalUserDao.updateUnsyncedPasswordHash (cycle-31 P4)', () {
    test('writes the new hash for an unsynced row and clears '
        'password_salt', () async {
      await seed();
      final before = (await dao.getPendingSignupByLocalId('row-1'))!;

      final updated = await dao.updateUnsyncedPasswordHash(
        localId: 'row-1',
        expectedHash: before['password'] as String,
        newHash: 'replacement-hash',
      );

      expect(updated, 1);
      final after = (await dao.getPendingSignupByLocalId('row-1'))!;
      expect(after['password'], 'replacement-hash');
      expect(after['password_salt'], '');
    });

    test('a stale expected hash is a no-op (compare-and-swap)', () async {
      await seed(legacy: true);

      final updated = await dao.updateUnsyncedPasswordHash(
        localId: 'row-1',
        expectedHash: 'deadbeef' * 8, // no longer the stored value
        newHash: 'replacement-hash',
      );

      expect(updated, 0);
      final after = (await dao.getPendingSignupByLocalId('row-1'))!;
      expect(after['password'], isNot('replacement-hash'));
      expect(after['password_salt'], _legacySalt);
    });

    test('a synced row is a no-op even with the matching expected '
        'hash', () async {
      await seed(legacy: true, synced: true);
      final before = (await dao.getPendingSignupByLocalId('row-1'))!;

      final updated = await dao.updateUnsyncedPasswordHash(
        localId: 'row-1',
        expectedHash: before['password'] as String,
        newHash: 'replacement-hash',
      );

      expect(updated, 0);
      final after = (await dao.getPendingSignupByLocalId('row-1'))!;
      expect(after['password'], before['password']);
    });
  });

  group('ChangePasswordPage offline branch (cycle-31 P4)', () {
    testWidgets('airplane mode: the offline flow changes the password with no '
        'connectivity and no online factor', (tester) async {
      final gate = _FakeGate(session: null);
      final service = _FakeOfflineService();
      // The cubit reports OFFLINE — the flow must not need the network.
      await _pumpOfflinePage(tester, gate, service);

      expect(find.byType(TextFormField), findsNWidgets(2));
      await _fillForm(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(service.calls, [
        'deviceCredentialPromptAvailable',
        'updateLocalPassword',
      ]);
      expect(service.currentPasswordSeen, 'OldPass123!');
      expect(service.newPasswordSeen, 'NewPass456!');
      expect(service.reasonSeen, _promptReason);
      expect(gate.calls, isEmpty);
      expect(find.text('Password changed!'), findsOneWidget);
      // Let the snackbar's auto-dismiss timer fire.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('no screen lock degrades with the notice and the change still '
        'completes', (tester) async {
      final gate = _FakeGate(session: null);
      final service = _FakeOfflineService()..deviceAvailable = false;
      await _pumpOfflinePage(tester, gate, service);

      await _fillForm(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(service.calls, [
        'deviceCredentialPromptAvailable',
        'updateLocalPassword',
      ]);
      expect(find.textContaining('no screen lock'), findsOneWidget);
      expect(find.text('Password changed!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'every offline failure maps to its copy without claiming success',
      (tester) async {
        const cases = <(OfflinePasswordChangeFailure, String)>[
          (
            OfflinePasswordChangeFailure.noSession,
            'Session expired. Please log in again.',
          ),
          (
            OfflinePasswordChangeFailure.accountNotFound,
            'Session expired. Please log in again.',
          ),
          (
            OfflinePasswordChangeFailure.accountRequiresOnline,
            'Changing password needs internet. '
                'Your current password still works offline.',
          ),
          (
            OfflinePasswordChangeFailure.lockedOut,
            'Too many attempts. Try again later.',
          ),
          (
            OfflinePasswordChangeFailure.wrongPassword,
            'Current password is incorrect',
          ),
          (
            OfflinePasswordChangeFailure.deviceCancelled,
            'Device confirmation was canceled. Your password was not changed.',
          ),
          (
            OfflinePasswordChangeFailure.updateConflict,
            'Your account changed before the update finished. '
                'Your password was not changed.',
          ),
        ];

        for (final (failure, copy) in cases) {
          final gate = _FakeGate(session: null);
          final service = _FakeOfflineService()..failure = failure;
          await _pumpOfflinePage(tester, gate, service);

          await _fillForm(tester);
          await _tapSubmit(tester);
          await tester.pumpAndSettle();

          expect(find.text(copy), findsOneWidget, reason: 'copy for $failure');
          expect(
            find.text('Password changed!'),
            findsNothing,
            reason: 'no success for $failure',
          );
        }
      },
    );

    testWidgets(
      'no Supabase user on a connected device still routes offline (no '
      'online factor)',
      (tester) async {
        final gate = _FakeGate(session: null);
        final service = _FakeOfflineService();
        // Connected device: the no-session class must not fall into (or
        // block on) the online chain — routing happens before the
        // connectivity gate.
        await _pumpOfflinePage(tester, gate, service, online: true);

        await _fillForm(tester);
        await _tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(service.calls, [
          'deviceCredentialPromptAvailable',
          'updateLocalPassword',
        ]);
        expect(gate.calls, isEmpty);
        expect(find.text('Password changed!'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets('an unexpected failure never claims success', (tester) async {
      final gate = _FakeGate(session: null);
      final service = _FakeOfflineService()..error = Exception('boom');
      await _pumpOfflinePage(tester, gate, service);

      await _fillForm(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Something went wrong. Your password was not changed.'),
        findsOneWidget,
      );
      expect(find.text('Password changed!'), findsNothing);
    });

    testWidgets(
      'an online session still takes the factor chain, never the offline '
      'flow',
      (tester) async {
        const session = PasswordChangeSession(
          email: 'user@example.com',
          isGoogleLinked: false,
          hasPassword: true,
        );
        final gate = _FakeGate(session: session);
        final service = _FakeOfflineService();
        await _pumpOfflinePage(tester, gate, service, online: true);

        await _fillForm(tester);
        await _tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(gate.calls, [
          'reauthenticate',
          'deviceCredentialPromptAvailable',
          'confirmDeviceCredential',
          'updatePassword',
        ]);
        expect(service.calls, isEmpty);
        expect(find.text('Password changed!'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      },
    );
  });
}

// ── page test helpers ──────────────────────────────────────────────────────

Widget _wrap(Widget home, ConnectivityCubit cubit) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
      BlocProvider<ConnectivityCubit>.value(value: cubit),
    ],
    child: MaterialApp(home: home),
  );
}

Future<void> _pumpOfflinePage(
  WidgetTester tester,
  _FakeGate gate,
  _FakeOfflineService service, {
  bool online = false,
}) async {
  final cubit = ConnectivityCubit(
    _FakeConnectivity(
      initial: online ? InternetStatus.online : InternetStatus.offline,
    ),
  );
  addTearDown(cubit.close);
  // A unique key per pump makes every call a fresh State (a keyless
  // same-type pump would reuse the State and its first service).
  await tester.pumpWidget(
    _wrap(
      ChangePasswordPage(
        key: UniqueKey(),
        factorGate: gate,
        offlineService: service,
      ),
      cubit,
    ),
  );
  await tester.pump();
}

/// Fills the form fields (current first, then new) by index.
Future<void> _fillForm(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'OldPass123!');
  await tester.enterText(fields.at(1), 'NewPass456!');
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
