// Cycle 31 · phase P3 — online password-change factor gate (page states).
// Updated by cycle 41 P2 (the ratified redesign:
// designs/cycle-41-change-password-redesign.md):
//  * Email+password: NO code stage — the order pin is
//    [reauthenticate, deviceCredentialPromptAvailable, confirmDeviceCredential,
//    updatePassword, sendOtpStepUp] (the emailed code is a NON-BLOCKING
//    post-write security notification; a failed send is debug-logged and
//    never surfaced).
//  * Google-linked: the Google prompt runs on the FIRST submit (any
//    non-success is non-fatal → CP-13) and the emailed code STAYS the
//    decisive blocking verifier:
//    [verifyGoogleReauth, deviceCredentialPromptAvailable,
//    confirmDeviceCredential, sendOtpStepUp, verifyOtpStepUp, updatePassword].
//    Dual-provider sessions keep reauthenticate ahead of it (S2: nothing
//    removed — knowledge factor first, §3.4).
//  * A canceled device prompt renders the inline retry card (§7) — the
//    terminal dead-end string is retired; "Try again" re-runs ONLY
//    confirmDeviceCredential (no second reauthenticate, no consumed send).
//
// Test file name fixed by phase P3 (plan: plans/cycle-31-second-factor-password-change.md;
// P5 consumes this file name).
//
// What is exercised here:
//  * ChangePasswordPage's factor state machine through the documented page
//    seam (PasswordChangeFactorGate): the page never calls AuthService /
//    BiometricAuthService statics directly, so a fake subclass drives every
//    account class and every factor outcome. No test triggers a real email
//    send (S1 — the fake seam only).
//  * The real gate's fail-closed mapping for verifyGoogleReauth — a null
//    return (P2 test seam) and every typed failure stay unsatisfied.
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
  String? otpEmailSeen;
  String? newPasswordSeen;
  Object? reauthError;
  Object? googleError;
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
    if (googleError != null) throw googleError!;
    return googleVerified;
  }

  @override
  Future<void> sendOtpStepUp(String email) async {
    calls.add('sendOtpStepUp');
    otpEmailSeen = email;
    if (sendOtpError != null) throw sendOtpError!;
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

/// The retired dead-end string must never render again (cycle-41 §10.3).
final Finder _retiredDeadEnd = find.text(
  'Device confirmation was canceled. Your password was not changed.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AuthService.googleAccountEmailForTest = null;
  });

  group('ChangePasswordPage — Google-linked class (cycle-41 §3.3)', () {
    testWidgets('Google-only: the Google prompt runs FIRST on the first '
        'submit and is non-fatal when it does not confirm; device prompt, '
        'emailed code (blocking), verify → updatePassword', (tester) async {
      final gate = _FakeGate(
        session: _session(google: true, hasPassword: false),
      );
      await _pumpPage(tester, gate);

      // A Google-only account has no password: no current-password field,
      // no why-line about it; the class explainer names all three checks.
      expect(find.text('Current Password'), findsNothing);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(
        find.textContaining('email a code to user@example.com'),
        findsOneWidget,
      );
      expect(find.textContaining('current password'), findsNothing);

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      // Order pin (§3.3): Google prompt first (the default fake returns
      // false → CP-13, non-fatal), device credential, then the send.
      expect(gate.calls, [
        'verifyGoogleReauth',
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
        'sendOtpStepUp',
      ]);
      expect(gate.calls, isNot(contains('reauthenticate')));
      expect(
        gate.deviceReasonSeen,
        'Confirm your identity to change your password',
      );
      expect(
        find.text(
          "Google confirmation didn't go through. We'll confirm it's you "
          'with the emailed code instead.',
        ),
        findsOneWidget,
      );
      expect(find.text('Verify & Change Password'), findsOneWidget);
      expect(
        find.text(
          'Enter the 6-digit code we emailed to user@example.com to confirm '
          'this password change.',
        ),
        findsOneWidget,
      );
      expect(_retiredDeadEnd, findsNothing);

      // Correct code: the write tail only — no second device prompt.
      gate.otpVerified = true;
      await tester.enterText(find.byType(TextFormField), '222222');
      await _tapSubmit(tester, 'Verify & Change Password');
      await tester.pumpAndSettle();
      expect(gate.calls.sublist(gate.calls.length - 2), [
        'verifyOtpStepUp',
        'updatePassword',
      ]);
      expect(gate.otpCodeSeen, '222222');
      expect(
        gate.calls.where((c) => c == 'confirmDeviceCredential'),
        hasLength(1),
      );
      expect(find.text('Password changed!'), findsOneWidget);
      // Let the snackbar's auto-dismiss timer fire.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'Google-only: a send failure aborts retryably — no stage advance, no '
      'password update, no weaker fallback (cycle-34 Ruling 8 shape)',
      (tester) async {
        final gate = _FakeGate(
          session: _session(google: true, hasPassword: false),
        )..sendOtpError = Exception('send failed');
        await _pumpPage(tester, gate);

        await _fillForm(tester);
        await _tapSubmit(tester, 'Change Password');
        await tester.pumpAndSettle();

        // The send was attempted exactly once, after the device step.
        expect(gate.calls, [
          'verifyGoogleReauth',
          'deviceCredentialPromptAvailable',
          'confirmDeviceCredential',
          'sendOtpStepUp',
        ]);
        expect(gate.calls, isNot(contains('updatePassword')));
        expect(gate.calls, isNot(contains('verifyOtpStepUp')));
        // Cause-honest, retryable copy (CP-19).
        expect(
          find.text("We couldn't send the code right now — try again in a bit"),
          findsOneWidget,
        );
        // Still on the form — the OTP stage never opened.
        expect(find.text('Verify & Change Password'), findsNothing);
        expect(find.text('Change Password'), findsWidgets);
        expect(_retiredDeadEnd, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Google-only: canceling the device prompt shows the retry '
      'card, consumes NO send, and Try again re-calls only '
      'confirmDeviceCredential (no second Google prompt, no reauthenticate)',
      (tester) async {
        final gate = _FakeGate(
          session: _session(google: true, hasPassword: false),
        )..deviceConfirmed = false;
        await _pumpPage(tester, gate);

        await _fillForm(tester);
        await _tapSubmit(tester, 'Change Password');
        await tester.pumpAndSettle();

        // Quota discipline (retained): a canceled device prompt must NOT
        // consume an email send — and no stage advance.
        expect(gate.calls, [
          'verifyGoogleReauth',
          'deviceCredentialPromptAvailable',
          'confirmDeviceCredential',
        ]);
        expect(gate.calls, isNot(contains('sendOtpStepUp')));
        expect(find.text('Verify & Change Password'), findsNothing);

        // The retry card replaces the retired terminal dead-end (§7).
        expect(_retiredDeadEnd, findsNothing);
        expect(
          find.text("Your phone's screen lock didn't confirm"),
          findsOneWidget,
        );
        expect(
          find.text(
            'Your password was not changed. Nothing has been saved yet. '
            'Try again to continue.',
          ),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);

        // Still on the form — no navigation, values kept.
        expect(find.text('New Password'), findsWidgets);

        // The device prompt succeeds on the retry.
        gate.deviceConfirmed = true;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();

        // ONLY the failed step re-ran: a second confirmDeviceCredential, NO
        // second verifyGoogleReauth, no reauthenticate — then the send.
        expect(gate.calls, [
          'verifyGoogleReauth',
          'deviceCredentialPromptAvailable',
          'confirmDeviceCredential',
          'confirmDeviceCredential',
          'sendOtpStepUp',
        ]);
        expect(
          gate.calls.where((c) => c == 'verifyGoogleReauth'),
          hasLength(1),
        );
        expect(find.text('Verify & Change Password'), findsOneWidget);

        gate.otpVerified = true;
        await tester.enterText(find.byType(TextFormField), '333333');
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

    testWidgets('Google-only: no screen lock degrades (no prompt) and the '
        'change still completes after the emailed code', (tester) async {
      final gate = _FakeGate(
        session: _session(google: true, hasPassword: false),
      )..deviceAvailable = false;
      await _pumpPage(tester, gate);

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      // The device step was skipped (no prompt call) — fail-open — and the
      // blocking send still ran.
      expect(gate.calls, [
        'verifyGoogleReauth',
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
    });
  });

  group('ChangePasswordPage — email/password class (cycle-41 §3.2)', () {
    testWidgets('reauth → device prompt → write → post-write notification, '
        'in that order; NO code stage exists', (tester) async {
      final gate = _FakeGate(session: _session());
      await _pumpPage(tester, gate);

      // Section label + the field's own label.
      expect(find.text('Current Password'), findsWidgets);
      expect(find.byType(TextFormField), findsNWidgets(2));

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      // Order pin (§12.3): the notification send happens AFTER the write —
      // and the flow never pauses on a code stage.
      expect(gate.calls, [
        'reauthenticate',
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
        'updatePassword',
        'sendOtpStepUp',
      ]);
      expect(gate.newPasswordSeen, 'NewPass456!');
      // The notification goes to the SESSION account's address.
      expect(gate.otpEmailSeen, 'user@example.com');
      expect(find.text('Verify & Change Password'), findsNothing);
      expect(find.text('Password changed!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a wrong current password aborts before any other factor '
        'and renders INLINE under the field with values kept', (tester) async {
      final gate = _FakeGate(session: _session())
        ..reauthError = Exception('Wrong password');
      await _pumpPage(tester, gate);

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      expect(gate.calls, ['reauthenticate']);
      // CP-10 renders inline (the field's error channel), not chain-level.
      expect(find.text('Current password is incorrect'), findsOneWidget);
      expect(gate.calls, isNot(contains('updatePassword')));
      expect(gate.calls, isNot(contains('sendOtpStepUp')));

      // GOV.UK technique: both fields keep their values on error.
      final fields = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'OldPass123!',
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'NewPass456!',
      );
    });

    testWidgets('canceling the device prompt shows the retry card, consumes '
        'NO send, and Try again re-calls only confirmDeviceCredential (no '
        'second reauthenticate) before the write + notification', (
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
      expect(gate.calls, isNot(contains('sendOtpStepUp')));
      expect(_retiredDeadEnd, findsNothing);
      expect(
        find.text("Your phone's screen lock didn't confirm"),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);

      gate.deviceConfirmed = true;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      // Only the device step re-ran; then write, then the post-write
      // notification. Exactly ONE reauthenticate across both attempts.
      expect(gate.calls, [
        'reauthenticate',
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
        'confirmDeviceCredential',
        'updatePassword',
        'sendOtpStepUp',
      ]);
      expect(gate.calls.where((c) => c == 'reauthenticate'), hasLength(1));
      expect(find.text('Password changed!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a failed post-write notification is swallowed: the change '
        'still completes (§4.5 — fire-and-forget, debug-log only)', (
      tester,
    ) async {
      final gate = _FakeGate(session: _session())
        ..sendOtpError = Exception('smtp down');
      await _pumpPage(tester, gate);

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      // The write happened; the notification was attempted after it and
      // its failure never surfaced in-app.
      expect(gate.calls, [
        'reauthenticate',
        'deviceCredentialPromptAvailable',
        'confirmDeviceCredential',
        'updatePassword',
        'sendOtpStepUp',
      ]);
      expect(find.text('Password changed!'), findsOneWidget);
      expect(
        find.text("We couldn't send the code right now — try again in a bit"),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'dual-provider: reauthenticate runs ahead of the (additive, non-fatal) '
      'Google prompt — knowledge first (§3.4), nothing removed (S2)',
      (tester) async {
        final gate = _FakeGate(session: _session(google: true));
        await _pumpPage(tester, gate);

        // Section label + the field's own label.
        expect(find.text('Current Password'), findsWidgets);
        await _fillForm(tester);
        await _tapSubmit(tester, 'Change Password');
        await tester.pumpAndSettle();

        expect(gate.calls, [
          'reauthenticate',
          'verifyGoogleReauth',
          'deviceCredentialPromptAvailable',
          'confirmDeviceCredential',
          'sendOtpStepUp',
        ]);
        expect(
          find.text(
            "Google confirmation didn't go through. We'll confirm it's you "
            'with the emailed code instead.',
          ),
          findsOneWidget,
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
      final gate = _FakeGate(
        session: _session(google: true, hasPassword: false),
      );
      gate.googleVerified = true;
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
        // treats null as failure → the code still gates.
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
