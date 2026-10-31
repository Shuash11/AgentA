// Cycle 41 · P2 — the change-password redesign: new coverage per the ratified
// spec (designs/cycle-41-change-password-redesign.md §12.3).
//
//  * Copy table verbatim (§10): the new strings (CP-01/02/05/24/25/26/27)
//    and the retained ones (CP-00/03/04/07/23/28/29/30) render exactly as
//    written; the retired strings (§10.3) render nowhere.
//  * F6 show/hide toggle: independent state per field, state-swapped
//    semantics labels (CP-06), values preserved across toggles.
//  * F3 keyboard regression: on the code stage, the field AND the CTA sit
//    above a simulated keyboard inset with zero scrolling (§8.3).
//  * Resend window: the 60 s window after the initial send and after each
//    resend; CP-25 on success; CP-19 on failure (pumped clocks).
//
// All through the fake-gate seam — no test triggers a real email send (S1).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiproject/core/utils/connectivity_service.dart';
import 'package:aiproject/cubit/connectivity/connectivity_cubit.dart';
import 'package:aiproject/cubit/theme/theme_cubit.dart';
import 'package:aiproject/presentation/profile/change_pass_page.dart';
import 'package:aiproject/services/auth/auth_service.dart';
import 'package:aiproject/theme/app_theme.dart';

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

/// Fake factor gate — records the call order; no real sends (S1).
class _FakeGate extends PasswordChangeFactorGate {
  _FakeGate({this.session});

  PasswordChangeSession? session;
  final List<String> calls = <String>[];

  bool googleVerified = false;
  bool otpVerified = false;
  bool deviceAvailable = true;
  bool deviceConfirmed = true;
  Object? reauthError;
  Object? sendOtpError;

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
    return otpVerified;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
  }

  @override
  Future<bool> deviceCredentialPromptAvailable() async {
    calls.add('deviceCredentialPromptAvailable');
    return deviceAvailable;
  }

  @override
  Future<bool> confirmDeviceCredential(String localizedReason) async {
    calls.add('confirmDeviceCredential');
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

Widget _wrap(
  Widget home,
  ConnectivityCubit cubit, {
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
      BlocProvider<ConnectivityCubit>.value(value: cubit),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: home,
      // Simulated keyboard inset (F3): the Scaffold consumes it exactly as
      // it consumes the platform's.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: viewInsets),
        child: child!,
      ),
    ),
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeGate gate, {
  bool online = true,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  final cubit = ConnectivityCubit(
    _FakeConnectivity(
      initial: online ? InternetStatus.online : InternetStatus.offline,
    ),
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(
    _wrap(ChangePasswordPage(factorGate: gate), cubit, viewInsets: viewInsets),
  );
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

/// Drives a Google-only session to the code stage (Google confirmed).
Future<void> _openCodeStage(WidgetTester tester, _FakeGate gate) async {
  gate.googleVerified = true;
  await _pumpPage(tester, gate);
  await _fillForm(tester);
  await _tapSubmit(tester, 'Change Password');
  await tester.pumpAndSettle();
  expect(find.text('Verification Code'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AuthService.googleAccountEmailForTest = null;
  });

  group('Copy table verbatim (cycle-41 §10)', () {
    testWidgets('email+password form: CP-00/02/03/04/05/07 render verbatim '
        'and no code stage exists', (tester) async {
      await _pumpPage(tester, _FakeGate(session: _session()));

      // CP-00 app bar title + CP-07 CTA share the string.
      expect(find.text('Change Password'), findsNWidgets(2));
      // CP-02 — the why-line.
      expect(
        find.text(
          "We ask for your current password to make sure it's really "
          'you.',
        ),
        findsOneWidget,
      );
      // CP-03/CP-04 — labels (outer label + decoration label).
      expect(find.text('Current Password'), findsWidgets);
      expect(find.text('New Password'), findsWidgets);
      // CP-05 — the recorded minimum, stated up front.
      expect(find.text('At least 6 characters'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Change Password'),
        findsOneWidget,
      );
      expect(find.text('Verify & Change Password'), findsNothing);
      expect(
        find.text(
          'Device confirmation was canceled. '
          'Your password was not changed.',
        ),
        findsNothing,
      );
    });

    testWidgets('Google form: CP-01 names all three checks; the '
        'current-password why-line is absent; the old email explainer is '
        'retired', (tester) async {
      await _pumpPage(
        tester,
        _FakeGate(session: _session(google: true, hasPassword: false)),
      );

      expect(
        find.text(
          "This account signs in with Google. To confirm it's you, "
          "we'll check your Google account and phone lock, then email a "
          'code to user@example.com.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('current password'), findsNothing);
      expect(find.textContaining("We'll email a 6-digit code"), findsNothing);
      expect(find.text('Current Password'), findsNothing);
      expect(find.text('New Password'), findsWidgets);
    });

    testWidgets('Google code stage: CP-30/23/24/28/29/27/26 render verbatim; '
        'the old stage-advance notice is retired', (tester) async {
      final gate = _FakeGate(
        session: _session(google: true, hasPassword: false),
      );
      await _openCodeStage(tester, gate);

      expect(find.text('Verification Code'), findsOneWidget);
      expect(
        find.text(
          'Enter the 6-digit code we emailed to user@example.com to '
          'confirm this password change.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "This is the final check that it's you before your "
          'password changes.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Verify & Change Password'),
        findsOneWidget,
      );
      expect(find.text('Back to password form'), findsOneWidget);
      expect(find.text('Resend code'), findsOneWidget);
      expect(find.text('You can request a new code in 60s'), findsOneWidget);
      expect(find.textContaining('We emailed a 6-digit code'), findsNothing);
    });

    testWidgets('an unmapped failure lands on CP-22 — the guessing fallbacks '
        'are retired (§10.3)', (tester) async {
      final gate = _FakeGate(session: _session())
        ..reauthError = Exception('boom');
      await _pumpPage(tester, gate);

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      expect(
        find.text('Something went wrong. Your password was not changed.'),
        findsOneWidget,
      );
      expect(find.text('Failed. Check current password.'), findsNothing);
      expect(
        find.text('Failed. Check your connection and try again.'),
        findsNothing,
      );
      // Values kept (GOV.UK technique).
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
  });

  group('F6 — show/hide toggle (cycle-41 §5.3)', () {
    testWidgets('independent state per field; values preserved across '
        'toggles', (tester) async {
      await _pumpPage(tester, _FakeGate(session: _session()));
      await _fillForm(tester);

      // Both fields hidden at rest.
      expect(find.byIcon(Icons.visibility), findsNWidgets(2));
      expect(find.byIcon(Icons.visibility_off), findsNothing);

      // Show the CURRENT password — the new field stays hidden. (Pump past
      // the toggle's quick icon-swap so the outgoing icon subtree is gone.)
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller!
            .text,
        'OldPass123!',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        'NewPass456!',
      );

      // Hide it again.
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byIcon(Icons.visibility), findsNWidgets(2));

      // Show the NEW password — the current field stays hidden.
      await tester.tap(find.byTooltip('Show new password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller!
            .text,
        'OldPass123!',
      );
    });

    testWidgets('semantics labels state the action and swap with the state '
        '(CP-06, §11.2)', (tester) async {
      final semantics = tester.ensureSemantics();

      await _pumpPage(tester, _FakeGate(session: _session()));

      expect(find.bySemanticsLabel('Show password'), findsOneWidget);
      expect(find.bySemanticsLabel('Show new password'), findsOneWidget);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
      expect(find.bySemanticsLabel('Show password'), findsNothing);
      // The other field's label is untouched (distinct labels per field).
      expect(find.bySemanticsLabel('Show new password'), findsOneWidget);

      await tester.tap(find.byTooltip('Show new password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.bySemanticsLabel('Hide new password'), findsOneWidget);
      expect(find.bySemanticsLabel('Show new password'), findsNothing);

      // This flutter_test verifies handle disposal before addTearDown runs.
      semantics.dispose();
    });
  });

  group('F3 — keyboard regression (cycle-41 §8.3)', () {
    // The layout assertion is meaningless under the test binding's 1-em-wide
    // fallback font (every glyph renders one em wide, doubling line counts),
    // so the group loads the app's real Roboto metrics from the Flutter SDK
    // cache before rendering.
    setUpAll(() async {
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      final fontFiles = <String>[
        'roboto-regular.ttf',
        'roboto-medium.ttf',
        'roboto-bold.ttf',
      ];
      for (final file in fontFiles) {
        final path = file;
        final fontFile = File(
          flutterRoot == null
              ? path
              : '$flutterRoot/bin/cache/artifacts/material_fonts/$file',
        );
        if (!fontFile.existsSync()) {
          fail(
            'F3 regression needs real Roboto metrics; missing $fontFile '
            '(FLUTTER_ROOT=${flutterRoot ?? '<unset>'})',
          );
        }
        final bytes = fontFile.readAsBytesSync();
        final loader = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
      }
    });

    testWidgets('code stage: field and CTA both above a simulated keyboard '
        'inset with zero scrolling', (tester) async {
      // A standard phone viewport; the numeric keyboard inset simulated.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const keyboardInset = 300.0;
      final gate = _FakeGate(
        session: _session(google: true, hasPassword: false),
      );
      await _pumpPage(
        tester,
        gate,
        viewInsets: const EdgeInsets.only(bottom: keyboardInset),
      );

      await _fillForm(tester);
      await _tapSubmit(tester, 'Change Password');
      await tester.pumpAndSettle();

      final viewportBottom = 844.0 - keyboardInset;
      final codeFieldRect = tester.getRect(find.byType(TextFormField));
      final ctaRect = tester.getRect(
        find.widgetWithText(ElevatedButton, 'Verify & Change Password'),
      );
      expect(codeFieldRect.bottom, lessThanOrEqualTo(viewportBottom));
      expect(ctaRect.bottom, lessThanOrEqualTo(viewportBottom));
      // Zero scrolling: the stage fits with the keyboard open. (The
      // SingleChildScrollView's own Scrollable is the first in its subtree.)
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.pixels, 0);
    });
  });

  group('Resend window (cycle-41 §6.3)', () {
    testWidgets('the 60 s window runs after the initial send; the countdown '
        'is live; a resend re-arms it with CP-25', (tester) async {
      final gate = _FakeGate(
        session: _session(google: true, hasPassword: false),
      );
      await _openCodeStage(tester, gate);

      // The initial send counts as the first request: the button starts
      // disabled and no extra send fired.
      expect(gate.calls.where((c) => c == 'sendOtpStepUp'), hasLength(1));
      final resend = find.widgetWithText(TextButton, 'Resend code');
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      expect(find.text('You can request a new code in 60s'), findsOneWidget);

      // The countdown is a live-updating label.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('You can request a new code in 59s'), findsOneWidget);

      // The window expires: the helper disappears, the button re-enables.
      await tester.pump(const Duration(seconds: 60));
      expect(find.textContaining('You can request a new code'), findsNothing);
      expect(tester.widget<TextButton>(resend).onPressed, isNotNull);

      // A resend fires the send again and re-arms the window (CP-25).
      await tester.tap(resend);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(gate.calls.where((c) => c == 'sendOtpStepUp'), hasLength(2));
      expect(
        find.text('A new code is on its way to user@example.com.'),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      expect(find.text('You can request a new code in 60s'), findsOneWidget);

      // Expire the restarted window so no timer outlives the test.
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('a failed resend renders CP-19, does NOT restart the window, '
        'and the next attempt succeeds', (tester) async {
      final gate = _FakeGate(
        session: _session(google: true, hasPassword: false),
      );
      await _openCodeStage(tester, gate);
      await tester.pump(const Duration(seconds: 61));
      final resend = find.widgetWithText(TextButton, 'Resend code');
      expect(tester.widget<TextButton>(resend).onPressed, isNotNull);

      gate.sendOtpError = Exception('send failed');
      await tester.tap(resend);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Cause-honest, retryable (CP-19); the window stays expired — a
      // failed send never consumed it.
      expect(
        find.text("We couldn't send the code right now — try again in a bit"),
        findsOneWidget,
      );
      expect(find.textContaining('You can request a new code'), findsNothing);
      expect(tester.widget<TextButton>(resend).onPressed, isNotNull);
      expect(gate.calls.where((c) => c == 'sendOtpStepUp'), hasLength(2));

      // The retry succeeds: CP-25, the window restarts.
      gate.sendOtpError = null;
      await tester.tap(resend);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text('A new code is on its way to user@example.com.'),
        findsOneWidget,
      );
      expect(gate.calls.where((c) => c == 'sendOtpStepUp'), hasLength(3));
      expect(find.text('You can request a new code in 60s'), findsOneWidget);
      expect(tester.widget<TextButton>(resend).onPressed, isNull);

      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('a resend keeps the entered code for editing', (tester) async {
      final gate = _FakeGate(
        session: _session(google: true, hasPassword: false),
      );
      await _openCodeStage(tester, gate);
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.pump(const Duration(seconds: 61));

      await tester.tap(find.widgetWithText(TextButton, 'Resend code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('A new code is on its way to user@example.com.'),
        findsOneWidget,
      );
      // GOV.UK technique: user input is never destroyed.
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '123456',
      );

      await tester.pump(const Duration(seconds: 61));
    });
  });
}
