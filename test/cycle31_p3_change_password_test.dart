// Cycle 31 · phase P3 — online password-change factor gate (page states).
//
// Test file name fixed by phase P3 (plan: plans/cycle-31-second-factor-password-change.md;
// P5 consumes this file name).
//
// What is exercised here:
//  * ChangePasswordPage's factor state machine through the documented page
//    seam (PasswordChangeFactorGate): the page never calls AuthService /
//    BiometricAuthService statics directly, so a fake subclass drives every
//    account class and every factor outcome.
//  * The real gate's fail-closed mapping for verifyGoogleReauth — retained
//    with zero invocation sites since cycle-34 ruling 3; a null return
//    (P2 test seam) and every typed failure stay unsatisfied.
//  * The offline-connectivity block kept from the pre-cycle-31 flow for
//    online sessions (the no-Supabase-user class routes to the P4 offline
//    flow, covered by cycle31_p4_offline_password_test.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiproject/core/utils/connectivity_service.dart';
import 'package:aiproject/cubit/connectivity/connectivity_cubit.dart';
import 'package:aiproject/cubit/theme/theme_cubit.dart';
import 'package:aiproject/presentation/profile/change_pass_page.dart';
import 'package:aiproject/services/auth/auth_service.dart';

/// Fake [ConnectivityService] — the cubit emits [initial] at construction.
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

/// Fake factor gate — records the call order and lets each test drive every
/// factor outcome. No method touches AuthService / the platform channels.
class _FakeGate extends PasswordChangeFactorGate {
  _FakeGate({this.session});

  PasswordChangeSession? session;

  /// Call order, e.g. ['reauthenticate', 'sendOtpStepUp', ...].
  final List<String> calls = <String>[];

  bool googleVerified = false;
  bool otpVerified = false;
  bool deviceAvailable = true;
  bool deviceConfirmed = true;
  String? deviceReasonSeen;
  String? otpCodeSeen;
  Object? reauthError;
  Object? sendOtpError;

  /// When set, [updatePassword] waits for it (lets a test observe the frame
  /// before the flow completes).
  Completer<void>? updateHold;

  @override
  PasswordChangeSession? loadSession() => session;

  @override
  Future<void> reauthenticate(String email, String password) async {
    calls.add('reauthenticate');
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<bool> verifyGoogleReauth(String expectedEmail) async {
    calls.add('verifyGoogleReauth');
    return googleVerified;
  }

  @override
  Future<void> sendOtpStepUp(String email) async {
    calls.add('sendOtpStepUp');
    if (sendOtpError != null) throw sendOtpError!;
  }

  @override
  Future<bool> verifyOtpStepUp(String email, String code) async {
    calls.add('verifyOtpStepUp');
    otpCodeSeen = code;
    return otpVerified;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
    if (updateHold != null) await updateHold!.future;
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

PasswordChangeSession _session({bool google = false, bool hasPassword = true}) {
  return PasswordChangeSession(
    email: 'user@example.com',
    isGoogleLinked: google,
    hasPassword: hasPassword,
  );
}

Widget _wrap(Widget home, ConnectivityCubit cubit) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
      BlocProvider<ConnectivityCubit>.value(value: cubit),
    ],
    child: MaterialApp(home: home),
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeGate gate, {
  bool online = true,
}) async {
  final cubit = ConnectivityCubit(
    _FakeConnectivity(
      initial: online ? InternetStatus.online : InternetStatus.offline,
    ),
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(_wrap(ChangePasswordPage(factorGate: gate), cubit));
  await tester.pump();
}

/// Fills the form fields (current first, then new) by index.
Future<void> _fillForm(
  WidgetTester tester, {
  String current = 'OldPass123!',
  String newPassword = 'NewPass456!',
}) async {
  final fields = find.byType(TextFormField);
  var index = 0;
  if (fields.evaluate().length > 1) {
    await tester.enterText(fields.at(index), current);
    index++;
  }
  await tester.enterText(fields.at(index), newPassword);
}

Future<void> _tapSubmit(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ElevatedButton, label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AuthService.googleAccountEmailForTest = null;
  });

  group('ChangePasswordPage — Google-linked session (cycle-31 P3)', () {
    testWidgets('Google-only: device prompt then the emailed code sent '
        'unconditionally (no Google call); verify → updatePassword', (
      tester,
    ) async {
      final gate = _FakeGate(
        session: _session(google: true, hasPassword: false),
      );
      await _pumpPage(tester, gate);

      // A Google-only account has no password: the baseline field is
      // hidden and the form announces the emailed-code step (cycle-34).
      expect(find.text('Current Password'), findsNothing);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(
        find.textContaining("We'll email a 6-digit code to user@example.com"),
        findsOneWidget,
      );

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      // Device credential first, then the mandatory send — the Google
      // factor is NEVER invoked (cycle-34 ruling 3).
      expect(gate.calls, [
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
        'sendOtpStepUp',
      ]);
      expect(gate.calls, isNot(contains('verifyGoogleReauth')));
      expect(
        gate.deviceReasonSeen,
        'Confirm your identity to change your password',
      );
      expect(find.text('Verify & Change Password'), findsOneWidget);
      expect(
        find.textContaining('emailed a 6-digit code to user@example.com'),
        findsOneWidget,
      );

      // Correct code: the write tail only — no second device prompt.
      gate.otpVerified = true;
      await tester.enterText(find.byType(TextFormField), '222222');
      await _tapSubmit(tester, 'Verify & Change Password');
      await tester.pumpAndSettle();
      expect(gate.calls.sublist(gate.calls.length - 2), [
        'verifyOtpStepUp',
        'updatePassword',
      ]);
      expect(
        gate.calls.where((c) => c == 'confirmDeviceCredential'),
        hasLength(1),
      );
      expect(find.text('Password changed!'), findsOneWidget);
      // Let the snackbar's auto-dismiss timer fire.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'dual-provider: baseline reauth, device prompt, then the mandatory '
      'emailed code; a failed code is a retryable no-op and a correct code '
      'completes the change',
      (tester) async {
        final gate = _FakeGate(session: _session(google: true));
        await _pumpPage(tester, gate);

        // Section label + the field's own label.
        expect(find.text('Current Password'), findsWidgets);
        await _fillForm(tester);
        await _tapSubmit(tester, 'Change Password');
        await tester.pumpAndSettle();

        // Baseline, device credential, then the unconditional send to the
        // session account's email (cycle-34 ruling 3: no Google call).
        expect(gate.calls, [
          'reauthenticate',
          'deviceCredentialPromptAvailable',
          'confirmDeviceCredential',
          'sendOtpStepUp',
        ]);
        expect(find.text('Verify & Change Password'), findsOneWidget);
        expect(
          find.textContaining('emailed a 6-digit code to user@example.com'),
          findsOneWidget,
        );

        // Wrong code: no session change, no password update, retryable.
        await tester.enterText(find.byType(TextFormField), '111111');
        await _tapSubmit(tester, 'Verify & Change Password');
        await tester.pumpAndSettle();
        expect(
          find.text(
            'That code is invalid or expired. Check the email and try again.',
          ),
          findsOneWidget,
        );
        expect(gate.otpCodeSeen, '111111');
        expect(gate.calls, isNot(contains('updatePassword')));
        expect(find.text('Verify & Change Password'), findsOneWidget);

        // Correct code: the write tail only — no second device prompt.
        gate.otpVerified = true;
        await tester.enterText(find.byType(TextFormField), '222222');
        await _tapSubmit(tester, 'Verify & Change Password');
        await tester.pumpAndSettle();
        expect(gate.otpCodeSeen, '222222');
        expect(gate.calls.sublist(gate.calls.length - 2), [
          'verifyOtpStepUp',
          'updatePassword',
        ]);
        expect(
          gate.calls.where((c) => c == 'confirmDeviceCredential'),
          hasLength(1),
        );
        expect(find.text('Password changed!'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      },
    );
  });

  group('ChangePasswordPage — email/password session (cycle-31 P3)', () {
    testWidgets(
      'baseline reauth + device prompt + emailed code run in plan order',
      (tester) async {
        final gate = _FakeGate(session: _session());
        await _pumpPage(tester, gate);

        // Section label + the field's own label.
        expect(find.text('Current Password'), findsWidgets);
        expect(find.byType(TextFormField), findsNWidgets(2));

        await _fillForm(tester);
        await _tapSubmit(tester, 'Change Password');
        await tester.pumpAndSettle();

        // Current password → device credential → OTP send → code entry →
        // update (cycle-34 ruling 3 matrix row).
        expect(gate.calls, [
          'reauthenticate',
          'deviceCredentialPromptAvailable',
          'confirmDeviceCredential',
          'sendOtpStepUp',
        ]);
        expect(
          gate.deviceReasonSeen,
          'Confirm your identity to change your password',
        );
        expect(find.text('Verify & Change Password'), findsOneWidget);

        gate.otpVerified = true;
        await tester.enterText(find.byType(TextFormField), '123456');
        await _tapSubmit(tester, 'Verify & Change Password');
        await tester.pumpAndSettle();
        expect(gate.calls.sublist(gate.calls.length - 2), [
          'verifyOtpStepUp',
          'updatePassword',
        ]);
        expect(find.text('Password changed!'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets('canceling the device prompt aborts with no password update', (
      tester,
    ) async {
      final gate = _FakeGate(session: _session())..deviceConfirmed = false;
      await _pumpPage(tester, gate);

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      expect(gate.calls, [
        'reauthenticate',
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
      ]);
      expect(gate.calls, isNot(contains('updatePassword')));
      // Quota discipline (cycle-34 P2): a canceled device prompt must NOT
      // consume an email send — no sendOtpStepUp, no stage advance.
      expect(gate.calls, isNot(contains('sendOtpStepUp')));
      expect(find.text('Verify & Change Password'), findsNothing);
      expect(
        find.text(
          'Device confirmation was canceled. Your password was not changed.',
        ),
        findsOneWidget,
      );
      // Still on the form — no navigation, no state change.
      expect(find.text('New Password'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wrong current password aborts before any other factor', (
      tester,
    ) async {
      final gate = _FakeGate(session: _session())
        ..reauthError = Exception('Wrong password');
      await _pumpPage(tester, gate);

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      expect(gate.calls, ['reauthenticate']);
      expect(find.text('Current password is incorrect'), findsOneWidget);
      expect(gate.calls, isNot(contains('updatePassword')));
    });

    testWidgets(
      'no screen lock degrades (no prompt) and the change still completes '
      'after the emailed code',
      (tester) async {
        final gate = _FakeGate(session: _session())..deviceAvailable = false;
        await _pumpPage(tester, gate);

        await _fillForm(tester);
        await _tapSubmit(tester, 'Change Password');
        await tester.pumpAndSettle();

        // The device step was skipped (no prompt call) — fail-open — and the
        // mandatory send still ran.
        expect(gate.calls, [
          'reauthenticate',
          'deviceCredentialPromptAvailable',
          'sendOtpStepUp',
        ]);
        expect(gate.calls, isNot(contains('confirmDeviceCredential')));

        gate.otpVerified = true;
        await tester.enterText(find.byType(TextFormField), '123456');
        await _tapSubmit(tester, 'Verify & Change Password');
        await tester.pumpAndSettle();
        expect(gate.calls.sublist(gate.calls.length - 2), [
          'verifyOtpStepUp',
          'updatePassword',
        ]);
        expect(find.text('Password changed!'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets('a send failure aborts retryably: no password update, no stage '
        'advance, no weaker-factor fallback', (tester) async {
      final gate = _FakeGate(session: _session())
        ..sendOtpError = Exception('send failed');
      await _pumpPage(tester, gate);

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      // The send was attempted exactly once, after the device step.
      expect(gate.calls, [
        'reauthenticate',
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
        'sendOtpStepUp',
      ]);
      expect(gate.calls, isNot(contains('updatePassword')));
      expect(gate.calls, isNot(contains('verifyOtpStepUp')));
      // Cause-honest, retryable copy (cycle-34 ruling 8).
      expect(
        find.text("We couldn't send the code right now — try again in a bit"),
        findsOneWidget,
      );
      // Still on the form — the OTP stage never opened.
      expect(find.text('Verify & Change Password'), findsNothing);
      expect(find.text('Change Password'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('ChangePasswordPage — routing and offline (cycle-31 P3)', () {
    // The no-Supabase-user class (offline-created, never synced) never
    // reaches this page's online chain: it routes to the P4 offline flow,
    // covered by cycle31_p4_offline_password_test.dart.

    testWidgets('offline device: the kept internet block fires for an online '
        'session', (tester) async {
      final gate = _FakeGate(session: _session());
      final cubit = ConnectivityCubit(
        _FakeConnectivity(initial: InternetStatus.offline),
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        _wrap(ChangePasswordPage(factorGate: gate), cubit),
      );
      await tester.pump();

      expect(find.byType(TextFormField), findsNWidgets(2));
      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');

      expect(
        find.text(
          'Changing password needs internet. '
          'Your current password still works offline.',
        ),
        findsOneWidget,
      );
      expect(gate.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving the code-entry stage aborts the change', (
      tester,
    ) async {
      final gate = _FakeGate(session: _session(google: true));
      await _pumpPage(tester, gate);

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();
      expect(find.text('Back to password form'), findsOneWidget);

      await tester.tap(find.text('Back to password form'));
      await tester.pumpAndSettle();

      expect(find.text('New Password'), findsWidgets);
      expect(find.text('Back to password form'), findsNothing);
      expect(gate.calls, isNot(contains('updatePassword')));
    });
  });

  group('PasswordChangeFactorGate fail-closed mapping (cycle-31 P3)', () {
    test(
      'a null verifyGoogleReauth return is never a satisfied factor',
      () async {
        // The P2 seam returns null for the seam-success path; the ruling
        // treats null as failure → OTP fallback.
        AuthService.googleAccountEmailForTest = () async => 'user@example.com';
        final verified = await const PasswordChangeFactorGate()
            .verifyGoogleReauth('user@example.com');
        expect(verified, isFalse);
      },
    );

    test('an account-email mismatch is never a satisfied factor', () async {
      AuthService.googleAccountEmailForTest = () async => 'other@example.com';
      final verified = await const PasswordChangeFactorGate()
          .verifyGoogleReauth('user@example.com');
      expect(verified, isFalse);
    });

    test('an unusable Google client is never a satisfied factor', () async {
      // No --dart-define GOOGLE_SERVER_CLIENT_ID in the test environment, so
      // the plugin path fails closed with a typed failure.
      final verified = await const PasswordChangeFactorGate()
          .verifyGoogleReauth('user@example.com');
      expect(verified, isFalse);
    });

    test('loadSession is null without a Supabase user (P4 hook source)', () {
      expect(const PasswordChangeFactorGate().loadSession(), isNull);
    });
  });
}
