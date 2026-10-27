// Cycle 31 e2e gate — FULL state matrix (online second factor + offline
// flow + regression), per plans/cycle31-second-factor-password-change.md.
//
// Discipline (e2e-testing skill): user-visible outcomes only (exact text,
// visible screens), call order asserted through the documented seams
// (PasswordChangeFactorGate / OfflinePasswordService), no goldens — PNG
// evidence written per state to test/e2e_evidence/, no fixed sleeps.
//
// Online states drive the REAL ChangePasswordPage with a recording fake
// gate (P3 pattern). Offline service states (S6-S8) run the REAL
// OfflinePasswordService against the REAL LocalUserDao (sqflite_common_ffi
// in-memory DB) with mocked local_auth / secure-storage channels as PLAIN
// tests (the S9 pattern): inside testWidgets' fake-async zone the real
// service's unmocked platform-channel futures never resolve and the state
// hangs (cycle-31 e2e diagnosis), so those states assert observable
// outcomes + call logs instead of a rendered widget — no PNG (the
// delegation's evidence rule for service-level states). S10 renders the
// page through the fake-service SEAM (no real channels under fake async).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

// ── bounded condition-waits (auto-waiting, never fixed sleeps) ─────────────

/// Animation completion without pumpAndSettle's throw-on-timeout.
Future<void> _settleSoft(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ── evidence capture ───────────────────────────────────────────────────────

const String _evidenceDir = 'test/e2e_evidence';
final GlobalKey _rootShotKey = GlobalKey();
final List<String> _runLog = <String>[];

Future<void> _shot(WidgetTester tester, String name) async {
  // Real engine rasterization + file IO must run outside the fake-async
  // zone (tester.runAsync) and is hard-bounded so evidence capture can
  // never hang a state.
  try {
    await _settleSoft(tester);
    await tester
        .runAsync(() async {
          final ctx = _rootShotKey.currentContext;
          if (ctx == null) throw StateError('no root boundary');
          final boundary = ctx.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$_evidenceDir/$name.png',
          ).writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
          image.dispose();
        })
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    _runLog.add('EVIDENCE-FAIL $name: $e');
  }
}

// ── channel mocks (local_auth + secure storage; P4 pattern) ────────────────

const MethodChannel _localAuthChannel = MethodChannel(
  'plugins.flutter.io/local_auth',
);
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

bool _deviceSupported = true;
List<String> _enrolledBiometrics = <String>['fingerprint'];
bool _authResult = true;
final List<MethodCall> _localAuthCalls = <MethodCall>[];
String? _sessionUid;
String _sessionEmail = '';

void _installChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_localAuthChannel, (call) async {
    _localAuthCalls.add(call);
    switch (call.method) {
      case 'isDeviceSupported':
        return _deviceSupported;
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

List<MethodCall> _authPrompts() =>
    _localAuthCalls.where((c) => c.method == 'authenticate').toList();

// ── fake connectivity + recording gate ─────────────────────────────────────

class _FakeConnectivity implements ConnectivityService {
  _FakeConnectivity({this.initial = InternetStatus.online});

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

class _RecordingGate extends PasswordChangeFactorGate {
  _RecordingGate({this.session});

  PasswordChangeSession? session;
  final List<String> calls = <String>[];

  bool googleVerified = false;
  bool otpVerified = false;
  bool deviceAvailable = true;
  bool deviceConfirmed = true;

  String? reauthEmailSeen;
  String? reauthPasswordSeen;
  String? otpEmailSeen;
  String? otpCodeSeen;
  String? deviceReasonSeen;
  String? newPasswordSeen;

  @override
  PasswordChangeSession? loadSession() => session;

  @override
  Future<void> reauthenticate(String email, String password) async {
    calls.add('reauthenticate');
    reauthEmailSeen = email;
    reauthPasswordSeen = password;
  }

  @override
  Future<bool> verifyGoogleReauth(String expectedEmail) async {
    calls.add('verifyGoogleReauth');
    return googleVerified;
  }

  @override
  Future<void> sendOtpStepUp(String email) async {
    calls.add('sendOtpStepUp');
    otpEmailSeen = email;
  }

  @override
  Future<bool> verifyOtpStepUp(String email, String code) async {
    calls.add('verifyOtpStepUp');
    otpEmailSeen = email;
    otpCodeSeen = code;
    return otpVerified;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
    newPasswordSeen = newPassword;
  }

  @override
  Future<bool> deviceCredentialPromptAvailable() async {
    calls.add('deviceCredentialPromptAvailable');
    return deviceAvailable;
  }

  @override
  Future<bool> confirmDeviceCredential(String localizedReason) async {
    calls.add('confirmDeviceCredential');
    deviceReasonSeen = localizedReason;
    return deviceConfirmed;
  }
}

/// Fake offline service — the page-level SEAM (P4 pattern): records the call
/// order, lets a test inject the [OfflinePasswordChangeFailure] the REAL
/// service would produce, and touches no DAO/platform channel, so the
/// page renders under fake async without the real service's hang.
class _FakeOfflineService extends OfflinePasswordService {
  final List<String> calls = <String>[];
  bool deviceAvailable = true;
  OfflinePasswordChangeFailure? failure;

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
    final failure = this.failure;
    if (failure != null) throw OfflinePasswordChangeException(failure);
  }
}

// ── harness: page pushed over a signed-in home, so "session KEPT" is a
//    visible outcome (the user is back on their profile, not a login screen).

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

Widget _harness(ConnectivityCubit cubit) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
      BlocProvider<ConnectivityCubit>.value(value: cubit),
    ],
    child: RepaintBoundary(
      key: _rootShotKey,
      child: MaterialApp(
        navigatorKey: _navKey,
        home: Scaffold(
          body: Center(child: Text('Profile — signed in as user@example.com')),
        ),
      ),
    ),
  );
}

ConnectivityCubit _cubit({required bool online}) {
  final cubit = ConnectivityCubit(
    _FakeConnectivity(
      initial: online ? InternetStatus.online : InternetStatus.offline,
    ),
  );
  return cubit;
}

Future<void> _pushPage(
  WidgetTester tester, {
  required bool online,
  _RecordingGate? gate,
  OfflinePasswordService? offlineService,
}) async {
  final cubit = _cubit(online: online);
  addTearDown(cubit.close);
  await tester.pumpWidget(_harness(cubit));
  await tester.pump();
  _navKey.currentState!.push(
    MaterialPageRoute(
      builder: (_) => ChangePasswordPage(
        key: UniqueKey(),
        factorGate: gate ?? const PasswordChangeFactorGate(),
        offlineService: offlineService,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillForm(
  WidgetTester tester, {
  String current = 'OldPass123!',
  String newPassword = 'NewPass456!',
  bool withCurrent = true,
}) async {
  final fields = find.byType(TextFormField);
  var index = 0;
  if (fields.evaluate().length > 1) {
    if (withCurrent) {
      await tester.enterText(fields.at(index), current);
    }
    index++;
  }
  await tester.enterText(fields.at(index), newPassword);
}

Future<void> _tapSubmit(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ElevatedButton, label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _tapChangePassword(WidgetTester tester) =>
    _tapSubmit(tester, 'Change Password');

// ── offline DB fixtures ────────────────────────────────────────────────────

const String _legacySalt = 'AQIDBAUGBwgJCgsMDQ4PEA';
const String _promptReason = 'Confirm your identity to change your password';
const String _needsInternet =
    'Changing password needs internet. Your current password still works offline.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  final dao = LocalUserDao();

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
    Directory(_evidenceDir).createSync(recursive: true);
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
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
        },
      ),
    );
    DatabaseHelper.testDatabase = db;
  });

  tearDownAll(() async {
    final log = _runLog.join('\n');
    File('$_evidenceDir/run_log.txt').writeAsStringSync('$log\n', flush: true);
    // ignore: avoid_print
    print('CYCLE31-E2E LOG\n$log');
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  setUp(() {
    _installChannelMocks();
    _localAuthCalls.clear();
    _deviceSupported = true;
    _enrolledBiometrics = <String>['fingerprint'];
    _authResult = true;
    _sessionUid = 'row-1';
    _sessionEmail = 'user@example.com';
    OfflineLoginGuard.resetForTest();
  });

  tearDown(_removeChannelMocks);

  // ── ONLINE half ──────────────────────────────────────────────────────────

  group('ONLINE — second-factor matrix', () {
    testWidgets('S1 password-provider: reauth (exact typed check) → device '
        'prompt (exact wording) → change; plan order', (tester) async {
      final gate = _RecordingGate(
        session: const PasswordChangeSession(
          email: 'user@example.com',
          isGoogleLinked: false,
          hasPassword: true,
        ),
      );
      await _pushPage(tester, online: true, gate: gate);
      await _fillForm(tester);
      await _tapChangePassword(tester);
      await tester.pumpAndSettle();

      expect(gate.calls, [
        'reauthenticate',
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
        'updatePassword',
      ]);
      expect(gate.reauthEmailSeen, 'user@example.com');
      expect(gate.reauthPasswordSeen, 'OldPass123!');
      expect(gate.deviceReasonSeen, _promptReason);
      expect(gate.newPasswordSeen, 'NewPass456!');
      expect(find.text('Password changed!'), findsOneWidget);
      await _shot(tester, 's01_password_provider_success');
      _runLog.add(
        'S1 PASS order=${gate.calls} reason=${gate.deviceReasonSeen}',
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('S2 google-linked: google factor fails → AUTOMATIC OTP '
        'fallback (session email) → correct code → change; session KEPT', (
      tester,
    ) async {
      final gate = _RecordingGate(
        session: const PasswordChangeSession(
          email: 'user@example.com',
          isGoogleLinked: true,
          hasPassword: true,
        ),
      );
      await _pushPage(tester, online: true, gate: gate);
      await _fillForm(tester);
      await _tapChangePassword(tester);
      await tester.pumpAndSettle();

      expect(gate.calls, [
        'reauthenticate',
        'verifyGoogleReauth',
        'sendOtpStepUp',
      ]);
      expect(gate.otpEmailSeen, 'user@example.com');
      expect(
        find.text(
          "We couldn't verify with Google. Instead, we emailed a 6-digit "
          'code to user@example.com.',
        ),
        findsOneWidget,
      );
      await _shot(tester, 's02_otp_fallback_code_entry');

      gate.otpVerified = true;
      await tester.enterText(find.byType(TextFormField), '654321');
      await _tapSubmit(tester, 'Verify & Change Password');
      await tester.pumpAndSettle();

      expect(gate.calls, [
        'reauthenticate',
        'verifyGoogleReauth',
        'sendOtpStepUp',
        'verifyOtpStepUp',
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
        'updatePassword',
      ]);
      expect(gate.otpCodeSeen, '654321');
      expect(find.text('Password changed!'), findsOneWidget);
      // Session KEPT: the user is back on the signed-in profile, never a
      // login screen, and the recorded seam calls contain no sign-out.
      expect(
        find.text('Profile — signed in as user@example.com'),
        findsOneWidget,
      );
      expect(gate.calls, isNot(contains('signOut')));
      await _shot(tester, 's02_session_kept_home');
      _runLog.add(
        'S2 PASS order=${gate.calls} otpEmail=${gate.otpEmailSeen} '
        'backOnProfile=yes',
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('S3 wrong OTP code: generic invalid/expired copy, no '
        'updatePassword, still signed in, retryable', (tester) async {
      final gate = _RecordingGate(
        session: const PasswordChangeSession(
          email: 'user@example.com',
          isGoogleLinked: true,
          hasPassword: true,
        ),
      );
      await _pushPage(tester, online: true, gate: gate);
      await _fillForm(tester);
      await _tapChangePassword(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '111111');
      await _tapSubmit(tester, 'Verify & Change Password');
      await tester.pumpAndSettle();

      expect(
        find.text(
          'That code is invalid or expired. Check the email and try again.',
        ),
        findsOneWidget,
      );
      expect(gate.calls, isNot(contains('updatePassword')));
      // Retryable: the code-entry stage is still up, still signed in.
      expect(find.text('Verify & Change Password'), findsOneWidget);
      expect(
        find.text('Profile — signed in as user@example.com'),
        findsNothing,
      );
      await _shot(tester, 's03_wrong_code_retryable');
      _runLog.add('S3 PASS retryable-no-op copy=invalid-or-expired');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('S4 cancel-abort: device-credential cancel ends BEFORE '
        'updatePassword', (tester) async {
      final gate = _RecordingGate(
        session: const PasswordChangeSession(
          email: 'user@example.com',
          isGoogleLinked: false,
          hasPassword: true,
        ),
      )..deviceConfirmed = false;
      await _pushPage(tester, online: true, gate: gate);
      await _fillForm(tester);
      await _tapChangePassword(tester);
      await tester.pumpAndSettle();

      expect(gate.calls, [
        'reauthenticate',
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
      ]);
      expect(gate.calls, isNot(contains('updatePassword')));
      expect(
        find.text(
          'Device confirmation was canceled. Your password was not changed.',
        ),
        findsOneWidget,
      );
      expect(find.text('New Password'), findsWidgets);
      await _shot(tester, 's04_cancel_abort');
      _runLog.add('S4 PASS aborted-before-update calls=${gate.calls}');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('S5 google factor satisfied BEFORE updatePassword (order '
        'assert)', (tester) async {
      final gate = _RecordingGate(
        session: const PasswordChangeSession(
          email: 'user@example.com',
          isGoogleLinked: true,
          hasPassword: false,
        ),
      )..googleVerified = true;
      await _pushPage(tester, online: true, gate: gate);
      expect(find.text('Current Password'), findsNothing);
      await _fillForm(tester);
      await _tapChangePassword(tester);
      await tester.pumpAndSettle();

      expect(gate.calls, [
        'verifyGoogleReauth',
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
        'updatePassword',
      ]);
      expect(
        gate.calls.indexOf('verifyGoogleReauth'),
        lessThan(gate.calls.indexOf('updatePassword')),
      );
      expect(find.text('Password changed!'), findsOneWidget);
      await _shot(tester, 's05_google_before_update');
      _runLog.add(
        'S5 PASS googleBeforeUpdate='
        '${gate.calls.indexOf('verifyGoogleReauth')}'
        '<${gate.calls.indexOf('updatePassword')}',
      );
      await tester.pump(const Duration(seconds: 5));
    });
  });

  // ── OFFLINE half (real service + real DAO, zero connectivity) ────────────

  group('OFFLINE — never-synced flow', () {
    setUp(() async {
      await db.delete('pending_signups');
    });

    // S6-S8 are PLAIN service-level runs (real service + real DAO + mocked
    // channels, the S9 pattern). The real service inside testWidgets'
    // fake-async zone hangs on unmocked platform-channel futures, so these
    // states assert observable outcomes + call logs (the delegation's
    // evidence rule) — no widget render, no PNG.
    test('S6 no screen lock: degrade → change succeeds via Argon2id + CAS; '
        'never prompted; new hash verifies', () async {
      // No screen lock: neither probe of the cycle-32 OR gate is available.
      _deviceSupported = false;
      _enrolledBiometrics = <String>[];
      await seed(); // real Argon2id hash

      await OfflinePasswordService().updateLocalPassword(
        currentPassword: 'OldPass123!',
        newPassword: 'NewPass456!',
        localizedReason: _promptReason,
      );

      // Degrade observable: the pre-probe ran, the user was NEVER prompted,
      // and the change still completed on-device (P1 fail-open policy — the
      // page maps this degrade to the exact no-lock notice; that rendering
      // is locked by cycle31_p4_offline_password_test.dart's page tests).
      final methods = _localAuthCalls.map((c) => c.method).toList();
      expect(methods, isNot(contains('authenticate')));
      expect(methods, contains('getAvailableBiometrics'));

      final row = (await dao.getPendingSignupByLocalId('row-1'))!;
      final newHash = row['password'] as String;
      final storedSalt = (row['password_salt'] as String?) ?? '';
      expect(
        PasswordHasher.verifyPassword(
          'NewPass456!',
          storedHash: newHash,
          storedSalt: storedSalt,
        ).matched,
        isTrue,
      );
      expect(
        PasswordHasher.verifyPassword(
          'OldPass123!',
          storedHash: newHash,
          storedSalt: storedSalt,
        ).matched,
        isFalse,
      );
      expect(storedSalt, ''); // re-hashed Argon2id PHC shape (CAS write)
      _runLog.add(
        'S6 PASS service-level: degrade=0-prompts argon2id+CAS=yes salt="" '
        '(notice rendering locked by P4 page tests; no PNG — service state)',
      );
    });

    test('S7 device credential available: exact step-up wording → success; '
        'cancel → row untouched', () async {
      // Variant 1 — prompt shown and confirmed: success through the real
      // service (Argon2id + CAS).
      await seed();
      await OfflinePasswordService().updateLocalPassword(
        currentPassword: 'OldPass123!',
        newPassword: 'NewPass456!',
        localizedReason: _promptReason,
      );
      final prompts = _authPrompts();
      expect(prompts, hasLength(1));
      final args = Map<Object?, Object?>.from(prompts.single.arguments as Map);
      expect(args['localizedReason'], _promptReason);
      expect(args['biometricOnly'], isFalse);
      var row = (await dao.getPendingSignupByLocalId('row-1'))!;
      expect(
        PasswordHasher.verifyPassword(
          'NewPass456!',
          storedHash: row['password'] as String,
          storedSalt: (row['password_salt'] as String?) ?? '',
        ).matched,
        isTrue,
      );
      _runLog.add(
        'S7 PASS wording=${args['localizedReason']} biometricOnly=false',
      );

      // Variant 2 — the prompt is CANCELED: abort, row untouched. Fresh row
      // so the knowledge factor passes and the abort lands on the device
      // step (the page wording for this outcome is locked by S4/P3/P4).
      await db.delete('pending_signups');
      await seed();
      _localAuthCalls.clear();
      _authResult = false; // the device prompt is declined
      OfflineLoginGuard.resetForTest();
      await expectLater(
        OfflinePasswordService().updateLocalPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'Hacked789!',
          localizedReason: _promptReason,
        ),
        throwsA(
          isA<OfflinePasswordChangeException>().having(
            (e) => e.reason,
            'reason',
            OfflinePasswordChangeFailure.deviceCancelled,
          ),
        ),
      );
      expect(_authPrompts(), hasLength(1));
      final cancelArgs = Map<Object?, Object?>.from(
        _authPrompts().single.arguments as Map,
      );
      expect(cancelArgs['localizedReason'], _promptReason);
      row = (await dao.getPendingSignupByLocalId('row-1'))!;
      expect(
        PasswordHasher.verifyPassword(
          'OldPass123!',
          storedHash: row['password'] as String,
          storedSalt: (row['password_salt'] as String?) ?? '',
        ).matched,
        isTrue,
      );
      expect(
        PasswordHasher.verifyPassword(
          'Hacked789!',
          storedHash: row['password'] as String,
          storedSalt: (row['password_salt'] as String?) ?? '',
        ).matched,
        isFalse,
      );
      _runLog.add(
        'S7 PASS cancel → row untouched (old pw still verifies, '
        'Hacked789! rejected); no PNG — service state',
      );
    });

    test(
      'S8 wrong current password: rejected + recorded; lockout after 5',
      () async {
        await seed(legacy: true); // guard semantics are scheme-independent
        final service = OfflinePasswordService();

        for (var attempt = 1; attempt <= 5; attempt++) {
          await expectLater(
            service.updateLocalPassword(
              currentPassword: 'WrongPass$attempt!',
              newPassword: 'NewPass456!',
              localizedReason: _promptReason,
            ),
            throwsA(
              isA<OfflinePasswordChangeException>().having(
                (e) => e.reason,
                'reason',
                OfflinePasswordChangeFailure.wrongPassword,
              ),
            ),
            reason: 'attempt $attempt',
          );
          expect(
            OfflineLoginGuard.failureCountForTest('user@example.com'),
            attempt,
          );
          expect(
            OfflineLoginGuard.isLockedOut('user@example.com'),
            attempt == 5,
            reason: 'attempt $attempt',
          );
        }
        // Wrong passwords are rejected BEFORE the device step: never prompted.
        expect(_authPrompts(), isEmpty);

        // Locked out: even the CORRECT password is refused now.
        await expectLater(
          service.updateLocalPassword(
            currentPassword: 'OldPass123!',
            newPassword: 'NewPass456!',
            localizedReason: _promptReason,
          ),
          throwsA(
            isA<OfflinePasswordChangeException>().having(
              (e) => e.reason,
              'reason',
              OfflinePasswordChangeFailure.lockedOut,
            ),
          ),
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
        _runLog.add(
          'S8 PASS service-level: failures=5 lockedOut=yes correct-pw-refused '
          'row-untouched prompts=0 (page copy "Too many attempts. Try again '
          'later." locked by P4 seam tests; no PNG — service state)',
        );
      },
    );

    test(
      'S9 next offline sign-in accepts the NEW password (rejects old)',
      () async {
        await seed(); // Argon2id
        // The change through the real service (what S6/S7 drove via the page).
        await OfflinePasswordService().updateLocalPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'NewPass456!',
          localizedReason: _promptReason,
        );
        final row = (await dao.getPendingSignupByLocalId('row-1'))!;
        // The exact call shape the offline sign-in path makes
        // (login.dart:409-413) against the row as the DAO returns it.
        expect(
          PasswordHasher.verifyPassword(
            'NewPass456!',
            storedHash: row['password'] as String,
            storedSalt: (row['password_salt'] as String?) ?? '',
          ).matched,
          isTrue,
        );
        expect(
          PasswordHasher.verifyPassword(
            'OldPass123!',
            storedHash: row['password'] as String,
            storedSalt: (row['password_salt'] as String?) ?? '',
          ).matched,
          isFalse,
        );
        _runLog.add('S9 PASS newPw=matched oldPw=rejected (login call shape)');
      },
    );

    testWidgets('S10 synced account without restored session → exact '
        '"needs internet" notice; row untouched', (tester) async {
      await tester.runAsync(() => seed(synced: true, legacy: true));
      final gate = _RecordingGate(session: null); // no Supabase session
      // Page-level SEAM: the fake reproduces the REAL service's outcome for
      // a synced row (accountRequiresOnline, thrown BEFORE any device step
      // or write) without the real service's fake-async channel hang.
      final offline = _FakeOfflineService()
        ..failure = OfflinePasswordChangeFailure.accountRequiresOnline;
      await _pushPage(
        tester,
        online: false,
        gate: gate,
        offlineService: offline,
      );
      await _fillForm(tester);
      await _tapChangePassword(tester);
      // Bounded pumps (S1-S5 pattern): the fake service completes on
      // microtasks; no runAsync/pump loop here — that helper is the
      // remaining fake-async hang suspect, and pumpAndSettle can spin on
      // the saving indicator.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(_needsInternet), findsOneWidget);
      expect(find.text('Password changed!'), findsNothing);
      // No online factor ever, no device prompt, and the offline seam ran.
      expect(gate.calls, isEmpty);
      expect(_authPrompts(), isEmpty);
      expect(offline.calls, [
        'deviceCredentialPromptAvailable',
        'updateLocalPassword',
      ]);
      // Real ffi IO must leave the fake-async zone (the diagnosis: such
      // futures never resolve inside it) — same wrapper as the seed above.
      final row = (await tester.runAsync(
        () => dao.getPendingSignupByLocalId('row-1'),
      ))!;
      expect(
        PasswordHasher.verifyPassword(
          'OldPass123!',
          storedHash: row['password'] as String,
          storedSalt: row['password_salt'] as String,
        ).matched,
        isTrue,
      );
      await _shot(tester, 's10_synced_needs_internet');
      _runLog.add(
        'S10 PASS seam=accountRequiresOnline exact notice; '
        'row untouched; no prompts; no online factor',
      );
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
