import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/connectivity/connectivity_cubit.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../services/auth/auth_service.dart';
import '../../services/auth/biometric_auth_service.dart';
import '../../services/auth/offline_password_service.dart';
import '../../theme/app_theme.dart';
import '../shared/system_keyboard_text_field.dart';
import 'device_retry_card.dart';
import 'password_field.dart';

/// Session facts the password-change factor chain needs (cycle-31 matrix).
///
/// A small view over the signed-in Supabase user so the page never touches
/// gotrue types directly; [PasswordChangeFactorGate] builds it.
class PasswordChangeSession {
  const PasswordChangeSession({
    required this.email,
    required this.isGoogleLinked,
    required this.hasPassword,
  });

  final String email;

  /// True when [AuthService.isGoogleLinked] classifies the session.
  final bool isGoogleLinked;

  /// True when the account holds an email/password identity, i.e. the OWASP
  /// baseline reauthentication has a current password to verify. A
  /// Google-only account has none, so the current-password field is hidden
  /// and the emailed code stays that class's decisive blocking verifier
  /// (cycle-41 ruling; cycle-31 plan, matrix row).
  final bool hasPassword;
}

/// The page's seam onto the cycle-31 factor layer (P2 APIs).
///
/// Production uses [AuthService] / [BiometricAuthService] directly; tests
/// subclass and override (the project's fake-service pattern). Stateless —
/// every method is a pass-through.
class PasswordChangeFactorGate {
  const PasswordChangeFactorGate();

  /// Loads the signed-in Supabase session, or null when there is no Supabase
  /// user (offline-created / never-synced account → the P4 routing hook).
  PasswordChangeSession? loadSession() {
    final user = AuthService.currentUser;
    if (user == null) return null;
    final email = user.email;
    if (email == null || email.trim().isEmpty) return null;

    // Identity scan mirroring AuthService.isGoogleLinked: 'email'/'password'
    // identities mean the account has a password. Unknown identity data keeps
    // the baseline step (fail-closed).
    final identities = user.identities;
    var hasPassword = true;
    if (identities != null && identities.isNotEmpty) {
      hasPassword = false;
      for (final identity in identities) {
        final provider = identity.provider;
        if (provider == 'email' || provider == 'password') {
          hasPassword = true;
          break;
        }
      }
    }
    return PasswordChangeSession(
      email: email,
      isGoogleLinked: AuthService.isGoogleLinked(user),
      hasPassword: hasPassword,
    );
  }

  /// Google factor — true only when the device-confirmed Google account is
  /// the session account.
  ///
  /// Cycle-41 restores the cycle-31 pairing on the Google-linked class: the
  /// prompt runs on the FIRST submit per page visit, ahead of the device
  /// step. It is additive — any non-success (a typed [GoogleSignInFailure]:
  /// canceled / unsupported / email mismatch / plugin error, or a null
  /// return from the test seam) is non-fatal and the emailed code still
  /// gates the change, so a failed Google check weakens nothing.
  Future<bool> verifyGoogleReauth(String expectedEmail) async {
    try {
      final account = await AuthService.verifyGoogleReauth(expectedEmail);
      return account != null;
    } on GoogleSignInFailure {
      return false;
    }
  }

  /// OWASP baseline: verifies the current password (kept wherever the account
  /// has a password — the second factor stacks on top).
  Future<void> reauthenticate(String email, String password) =>
      AuthService.reauthenticate(email, password);

  /// Sends the step-up code to the session account's email.
  ///
  /// Per-class role since the cycle-41 ruling (design §4): on the
  /// Google-linked class this is the decisive BLOCKING verifier's send (the
  /// code must be typed before the write); on the email+password class it is
  /// a best-effort NON-BLOCKING security notification fired after the
  /// successful write (nothing consumes the code — the inbox is pinged at
  /// the verified channel); local (never-synced) accounts never invoke it.
  Future<void> sendOtpStepUp(String email) =>
      AuthService.sendOtpForStepUp(email);

  /// Verifies the emailed code; false = wrong/expired → caller no-ops.
  Future<bool> verifyOtpStepUp(String email, String code) =>
      AuthService.verifyOtpStepUp(email, code);

  /// The password write — called only after every factor passed.
  Future<void> updatePassword(String newPassword) =>
      AuthService.updatePassword(newPassword);

  /// True when this device can show a device-credential prompt (biometric or
  /// the phone's PIN/pattern/passcode). Uses the device-credential OR
  /// predicate (biometrics OR any secure lock, so PIN-only devices pass);
  /// false → the device step degrades (plan policy: no screen lock is
  /// fail-open, never a block).
  Future<bool> deviceCredentialPromptAvailable() =>
      BiometricAuthService.isDeviceCredentialPromptAvailable();

  /// The device-credential factor ("the phone's password"); false = not
  /// confirmed (cancel or platform error) → the caller offers the inline
  /// retry card (cycle-41 §7).
  Future<bool> confirmDeviceCredential(String localizedReason) =>
      BiometricAuthService.confirmDeviceCredential(
        localizedReason: localizedReason,
      );
}

/// Internal abort signal: the device-credential prompt was shown and not
/// confirmed. The change stops with the inline retry card (cycle-41 §7) —
/// never a terminal dead-end, and no email send is ever consumed (the send
/// happens only after this step passes — the no-waste rule).
class _DeviceCancelled implements Exception {
  const _DeviceCancelled();
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    this.factorGate = const PasswordChangeFactorGate(),
    this.offlineService,
  });

  /// Test seam onto the factor layer; production keeps the default.
  final PasswordChangeFactorGate factorGate;

  /// Test seam onto the P4 offline flow; production builds the default
  /// [OfflinePasswordService] in the state.
  final OfflinePasswordService? offlineService;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

/// UI stage of the change flow — [otpCode] is reached ONLY by the
/// Google-linked class, whose emailed code stays the decisive blocking
/// verifier (cycle-41 §4.2); the email+password class has no code stage.
enum _ChangeStage { form, otpCode }

class _ChangePasswordPageState extends State<ChangePasswordPage>
    with WidgetsBindingObserver {
  // ── Copy of record (designs/cycle-41-change-password-redesign.md §10) ────

  /// CP-32 — the system prompt's distinct step-up wording (unchanged).
  static const String _devicePromptReason =
      'Confirm your identity to change your password';

  /// CP-02 — the why-line under the title on current-password classes.
  static const String _whyCurrentPassword =
      "We ask for your current password to make sure it's really you.";

  /// CP-03/CP-04 — field labels.
  static const String _currentPasswordLabel = 'Current Password';
  static const String _newPasswordLabel = 'New Password';

  /// CP-05/CP-09 — the app's recorded minimum, stated up front and used as
  /// the new-password validator message.
  static const String _atLeastSix = 'At least 6 characters';

  /// CP-08 — the field empty validator.
  static const String _required = 'Required';

  /// CP-06 — state-swapped toggle labels (states the action, distinct per
  /// field — the GOV.UK two-toggles rule).
  static const String _showPassword = 'Show password';
  static const String _hidePassword = 'Hide password';
  static const String _showNewPassword = 'Show new password';
  static const String _hideNewPassword = 'Hide new password';

  /// CP-07/CP-28 — CTA labels.
  static const String _formCtaLabel = 'Change Password';
  static const String _codeCtaLabel = 'Verify & Change Password';

  /// CP-10 — inline wrong-current-password error.
  static const String _incorrectCurrentPassword =
      'Current password is incorrect';

  /// CP-11 — online class on an offline device (and the offline service's
  /// accountRequiresOnline mapping).
  static const String _needsInternet =
      'Changing password needs internet. Your current password still works '
      'offline.';

  /// CP-12 — session gone (noSession / accountNotFound map here too).
  static const String _sessionExpired = 'Session expired. Please log in again.';

  /// CP-12a — current-password lockout.
  static const String _lockedOut = 'Too many attempts. Try again later.';

  /// CP-13 — Google prompt non-success (non-fatal; the flow continues).
  static const String _googleFallbackNotice =
      "Google confirmation didn't go through. We'll confirm it's you with "
      'the emailed code instead.';

  /// CP-14 — degrade notice (online).
  static const String _noScreenLockOnline =
      "This phone has no screen lock, so it can't confirm it's you. "
      'Continuing with the check you already passed.';

  /// CP-14a — degrade notice (offline).
  static const String _noScreenLockOffline =
      "This phone has no screen lock, so it can't confirm it's you. "
      'Continuing with your current password check only.';

  /// CP-18 — success SnackBar.
  static const String _passwordChanged = 'Password changed!';

  /// CP-19 — code send failure (initial + resend, Google class only).
  static const String _sendFailed =
      "We couldn't send the code right now — try again in a bit";

  /// CP-20 — empty code (inline on the code field).
  static const String _emptyCode = 'Enter the 6-digit code from your email.';

  /// CP-21 — wrong/expired code (chain-level, retryable no-op).
  static const String _invalidCode =
      'That code is invalid or expired. Check the email and try again.';

  /// CP-22 — generic failure (also the retired `_mapError` fallbacks'
  /// replacement — the fallback must not guess).
  static const String _genericFailure =
      'Something went wrong. Your password was not changed.';

  /// CP-29 — code-stage back link.
  static const String _backToFormLabel = 'Back to password form';

  /// CP-30 — code-stage header.
  static const String _codeStageTitle = 'Verification Code';

  /// CP-31 — CAS conflict.
  static const String _updateConflict =
      'Your account changed before the update finished. '
      'Your password was not changed.';

  /// Network error (retained).
  static const String _networkError = 'Network error. Check your connection.';

  /// CP-27 — resend button.
  static const String _resendLabel = 'Resend code';

  /// §11.2 — the code field's accessibility label.
  static const String _codeFieldSemanticsLabel = '6-digit verification code';

  /// The Supabase per-user resend window (cycle-34 Rulings 8–9); the initial
  /// send counts as the first request.
  static const int _resendWindowSeconds = 60;

  // ── State ────────────────────────────────────────────────────────────────

  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  final _currentPasswordFocus = FocusNode();
  final _newPasswordFocus = FocusNode();
  final _codeFocus = FocusNode();

  /// §8.2 — the primary CTA of each stage; a focused field brings the
  /// action with it above the keyboard.
  final GlobalKey _formCtaKey = GlobalKey();
  final GlobalKey _codeCtaKey = GlobalKey();

  _ChangeStage _stage = _ChangeStage.form;

  /// Session facts captured when the page opens.
  PasswordChangeSession? _session;

  /// The session behind the pending OTP step-up (set when the emailed-code
  /// step starts; cleared when the user goes back to the form).
  PasswordChangeSession? _otpSession;

  bool _isSaving = false;

  /// True only while a Try-again attempt (the retry card's re-run of the
  /// failed step) is in flight — drives the card's button spinner (§9).
  bool _retryInFlight = false;

  /// Chain-level error box (CP-11/12/12a/19/21/22/31, network).
  String? _errorMessage;

  /// Notice box (CP-13/14/14a/25) — icon + warningText, never a panel.
  String? _noticeMessage;

  /// CP-10 — the current-password field's inline service error. Displayed
  /// through the field's validator channel so the errorBorder/errorStyle
  /// announce it with the field (§5.5).
  String? _currentFieldError;

  /// CP-20 — the code field's inline empty error (decoration errorText).
  String? _codeFieldError;

  /// The retry card (§7) replaces the retired terminal dead-end.
  bool _deviceCancelPending = false;

  /// Independent show/hide state per field (§5.3).
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  /// The Google prompt runs on the FIRST submit per page visit (§3.3);
  /// retries never re-invoke it.
  bool _googlePromptAttempted = false;

  /// Live re-validation per keystroke begins after the first failed submit
  /// (§5.4 error timing).
  bool _formSubmitAttempted = false;

  /// The 60 s resend window (§6.3) — running while > 0.
  int _resendCountdown = 0;
  Timer? _resendTimer;

  /// The offline flow service (P4) — built once, overridable in tests.
  late final OfflinePasswordService _offlineService;

  /// The baseline current-password field is shown whenever a password can
  /// exist; a Google-only session has none (matrix row).
  bool get _showCurrentPassword => _session?.hasPassword ?? true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.factorGate.loadSession();
    _offlineService = widget.offlineService ?? OfflinePasswordService();
    _currentPasswordFocus.addListener(_onFieldFocusChanged);
    _newPasswordFocus.addListener(_onFieldFocusChanged);
    _codeFocus.addListener(_onFieldFocusChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resendTimer?.cancel();
    _currentPasswordFocus.dispose();
    _newPasswordFocus.dispose();
    _codeFocus.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ── Keyboard handling (cycle-41 §8) ─────────────────────────────────────

  /// §8.2 — when a field gains focus, the focused field AND the primary CTA
  /// are scrolled into the visible viewport, bottom-aligned.
  void _onFieldFocusChanged() {
    final hasFieldFocus =
        _currentPasswordFocus.hasFocus ||
        _newPasswordFocus.hasFocus ||
        _codeFocus.hasFocus;
    if (!hasFieldFocus) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensurePrimaryCtaVisible(),
    );
  }

  /// §8 — the keyboard animates in over several metrics updates; every
  /// metrics change while a field holds focus re-brings the CTA above it.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final focus = FocusManager.instance.primaryFocus;
    final isFieldFocus =
        focus == _currentPasswordFocus ||
        focus == _newPasswordFocus ||
        focus == _codeFocus;
    if (!isFieldFocus) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensurePrimaryCtaVisible(),
    );
  }

  /// The CTA is the last element of every stage's content; aligning its
  /// trailing edge with the (inset-shrunk) viewport's trailing edge keeps it
  /// visible while typing. A no-op when it already fits.
  void _ensurePrimaryCtaVisible() {
    if (!mounted) return;
    final ctaKey = _stage == _ChangeStage.form ? _formCtaKey : _codeCtaKey;
    final ctaContext = ctaKey.currentContext;
    if (ctaContext == null) return;
    Scrollable.ensureVisible(
      ctaContext,
      duration: AppDurations.standard,
      curve: AppDurations.standardCurve,
      alignment: 1.0,
    );
  }

  /// §6.1 — the code field auto-focuses on stage entry (the stage has one
  /// job); the keyboard rules above keep the CTA visible.
  void _focusCodeField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _codeFocus.requestFocus();
      _ensurePrimaryCtaVisible();
    });
  }

  // ── Submit paths ─────────────────────────────────────────────────────────

  /// Entry point for both stages: the form submit starts the factor chain;
  /// the OTP stage (Google class only) verifies the emailed code and
  /// resumes it.
  Future<void> _submit() async {
    if (_isSaving) return;
    if (_stage == _ChangeStage.otpCode) {
      await _verifyOtpCode();
      return;
    }

    final valid = _formKey.currentState!.validate();
    if (!valid) {
      // §5.4 — after a failed submit, the form re-validates per keystroke
      // so an error clears the moment the input satisfies the rule.
      setState(() => _formSubmitAttempted = true);
      return;
    }

    final session = _session;
    if (session == null) {
      // No Supabase user: an offline-created, never-synced account (or no
      // session at all). The P4 offline flow runs fully on-device — the
      // connectivity block below applies to the online factor chain only.
      await _submitOffline();
      return;
    }

    final isOnline = context.read<ConnectivityCubit>().state.isOnline;
    if (!isOnline) {
      setState(() => _errorMessage = _needsInternet);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _noticeMessage = null;
      _currentFieldError = null;
      _deviceCancelPending = false;
    });

    try {
      if (session.hasPassword) {
        // OWASP baseline — kept wherever a password exists; the second
        // factor stacks on top of it, it never replaces this step.
        await widget.factorGate.reauthenticate(
          session.email,
          _currentPasswordController.text,
        );
      }
      if (session.isGoogleLinked && !_googlePromptAttempted) {
        // Cycle-41 §3.3 — the Google prompt first (the cycle-31 pairing
        // restored), on the first submit per page visit. Any non-success
        // (canceled / unsupported / email mismatch / error) is non-fatal:
        // inline notice CP-13 and the flow continues.
        _googlePromptAttempted = true;
        var confirmed = false;
        try {
          confirmed = await widget.factorGate.verifyGoogleReauth(session.email);
        } catch (_) {
          confirmed = false;
        }
        if (!confirmed && mounted) {
          setState(() => _noticeMessage = _googleFallbackNotice);
        }
      }
      // One prompt per submit, in this order (§3.4): knowledge (the typed
      // current password above) → the additive Google prompt → possession
      // (device) → write. A canceled device prompt must never consume an
      // email send.
      await _confirmDeviceOrAbort();
      if (session.isGoogleLinked) {
        await _sendOtpAndAdvanceStage(session);
      } else {
        // Cycle-41 §3.2 — no code stage on the email+password class: the
        // typed current password IS the user-visible verification; the
        // emailed code becomes a post-write notification.
        await _writeAndFinish(session, notifyByEmail: true);
      }
    } on _DeviceCancelled {
      if (mounted) setState(() => _deviceCancelPending = true);
    } catch (e) {
      if (mounted) _presentOnlineError(e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Offline password change (cycle-31 P4) for a session with no Supabase
  /// user: the local row is the credential. [OfflinePasswordService] owns
  /// the proof order — current-password Argon2id verify, then the device
  /// credential when the device can show it — and the compare-and-swap hash
  /// write. Works with zero connectivity. NO email exists on this path.
  Future<void> _submitOffline() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _noticeMessage = null;
      _currentFieldError = null;
      _deviceCancelPending = false;
    });

    try {
      // Pre-probe (P3 pattern): decides prompt-vs-degrade BEFORE any prompt
      // call; false means the device step degrades (fail-open) and the user
      // gets the notice while the change runs.
      final deviceAvailable = await _offlineService
          .deviceCredentialPromptAvailable();
      if (!deviceAvailable && mounted) {
        setState(() => _noticeMessage = _noScreenLockOffline);
      }

      await _offlineService.updateLocalPassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
        localizedReason: _devicePromptReason,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(_passwordChanged)));
      Navigator.popUntil(context, (route) => route.isFirst);
    } on OfflinePasswordChangeException catch (e) {
      if (mounted) _presentOfflineError(e.reason);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = _genericFailure);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _retryInFlight = false;
        });
      }
    }
  }

  /// Offline failure wording. No message claims a recovery-code use and no
  /// message implies a network call — the offline change is fully on-device.
  /// CP-10 is a FIELD error (inline under the current field); a canceled
  /// device prompt lands on the retry card (§7), never the retired
  /// terminal dead-end.
  void _presentOfflineError(OfflinePasswordChangeFailure reason) {
    switch (reason) {
      case OfflinePasswordChangeFailure.noSession:
      case OfflinePasswordChangeFailure.accountNotFound:
        setState(() => _errorMessage = _sessionExpired);
      case OfflinePasswordChangeFailure.accountRequiresOnline:
        setState(() => _errorMessage = _needsInternet);
      case OfflinePasswordChangeFailure.lockedOut:
        setState(() => _errorMessage = _lockedOut);
      case OfflinePasswordChangeFailure.wrongPassword:
        _showCurrentPasswordError();
      case OfflinePasswordChangeFailure.deviceCancelled:
        setState(() => _deviceCancelPending = true);
      case OfflinePasswordChangeFailure.updateConflict:
        setState(() => _errorMessage = _updateConflict);
    }
  }

  /// The device-credential step — runs ONCE per submit, BEFORE the OTP send
  /// on the Google class and before the write on the email+password class.
  ///
  /// Plan policy: no screen lock → degrade (skip + notice), never block; a
  /// canceled prompt raises [_DeviceCancelled] — no password update and no
  /// email consumed (the no-waste rule, `:246` generalized).
  Future<void> _confirmDeviceOrAbort() async {
    if (await widget.factorGate.deviceCredentialPromptAvailable()) {
      final confirmed = await widget.factorGate.confirmDeviceCredential(
        _devicePromptReason,
      );
      if (!confirmed) {
        throw const _DeviceCancelled();
      }
    } else if (mounted) {
      setState(() => _noticeMessage = _noScreenLockOnline);
    }
  }

  /// The emailed-code step for the Google-linked class ONLY (cycle-41 §4.2):
  /// emails the step-up code to the SESSION account's address and advances
  /// to code entry. A send failure is a retryable, cause-honest chain error
  /// — no password update, no stage advance, and no fallback to a weaker
  /// factor (cycle-34 Ruling 8: no silent path, no skip).
  Future<void> _sendOtpAndAdvanceStage(PasswordChangeSession session) async {
    try {
      await widget.factorGate.sendOtpStepUp(session.email);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = _sendFailed);
      return;
    }
    if (!mounted) return;
    setState(() {
      _otpSession = session;
      _stage = _ChangeStage.otpCode;
      _otpController.clear();
      _codeFieldError = null;
      _errorMessage = null;
      _resendCountdown = _resendWindowSeconds;
    });
    _startResendTimer();
    _focusCodeField();
  }

  /// Verifies the emailed code and resumes the chain (Google class only).
  ///
  /// Ruling: a wrong/expired code is a retryable no-op — no session change,
  /// no password update, the user stays signed in, the value stays for
  /// editing, CP-21 renders chain-level. The empty-field case is CP-20,
  /// inline on the code field (§9).
  Future<void> _verifyOtpCode() async {
    final session = _otpSession;
    if (session == null) {
      _backToForm();
      return;
    }
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      setState(() => _codeFieldError = _emptyCode);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _codeFieldError = null;
    });

    try {
      final verified = await widget.factorGate.verifyOtpStepUp(
        session.email,
        code,
      );
      if (!verified) {
        if (mounted) setState(() => _errorMessage = _invalidCode);
        return;
      }
      await _writeAndFinish(session, notifyByEmail: false);
    } catch (e) {
      if (mounted) _presentOnlineError(e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// The password write tail — runs only after every factor passed; no
  /// second device prompt (cycle-34, Ruling 3).
  ///
  /// On success the session is KEPT — the fresh session the OTP step-up
  /// issued is OWASP's password-change token renewal; no sign-out on this
  /// path (Adviser ruling).
  ///
  /// [notifyByEmail] — cycle-41 §4.5: the email+password path fires a
  /// best-effort security notification AFTER the successful write,
  /// fire-and-forget; the success surface never waits on SMTP and never
  /// promises the email. The Google class already sent its (blocking) code.
  Future<void> _writeAndFinish(
    PasswordChangeSession session, {
    required bool notifyByEmail,
  }) async {
    await widget.factorGate.updatePassword(_newPasswordController.text);
    if (notifyByEmail) {
      _sendPostWriteNotification(session.email);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(_passwordChanged)));
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  /// §4.5 — the post-write security notification: the user's own successful
  /// submit is the only trigger; the send is fire-and-forget with a
  /// debug-log swallow — a failed notification is never surfaced in-app.
  void _sendPostWriteNotification(String email) {
    unawaited(
      widget.factorGate.sendOtpStepUp(email).catchError((Object error) {
        debugPrint(
          '[ChangePasswordPage] post-write security notification failed: '
          '$error',
        );
      }),
    );
  }

  // ── Retry card (cycle-41 §7) ─────────────────────────────────────────────

  /// "Try again" re-runs ONLY the failed step, never the whole chain:
  /// online — [confirmDeviceCredential] alone (the typed current-password
  /// proof already passed this submit; the Google prompt already had its
  /// first-submit attempt); offline — the local proof re-runs with the
  /// still-held values. No send is ever consumed by a retry (no-waste).
  Future<void> _retryFailedStep() async {
    if (_isSaving) return;
    final session = _session;
    if (session == null) {
      await _submitOffline();
      return;
    }

    setState(() {
      _isSaving = true;
      _retryInFlight = true;
      _deviceCancelPending = false;
      _errorMessage = null;
    });

    try {
      // §7.1 — re-run ONLY the failed step: confirmDeviceCredential ALONE.
      // The pre-probe already gated the first prompt (the card is only
      // reachable after a real cancel, so the device demonstrably has a
      // lock), and the typed current-password proof already passed this
      // submit — re-asking would be punitive.
      final confirmed = await widget.factorGate.confirmDeviceCredential(
        _devicePromptReason,
      );
      if (!confirmed) {
        throw const _DeviceCancelled();
      }
      if (session.isGoogleLinked) {
        await _sendOtpAndAdvanceStage(session);
      } else {
        await _writeAndFinish(session, notifyByEmail: true);
      }
    } on _DeviceCancelled {
      // No loop limit: canceling is user intent — the card reappears with
      // the same explanation (§7.1).
      if (mounted) setState(() => _deviceCancelPending = true);
    } catch (e) {
      if (mounted) _presentOnlineError(e);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _retryInFlight = false;
        });
      }
    }
  }

  /// "Back" returns to the form state with both fields intact and every
  /// chain state cleared (§7.1).
  void _backFromRetryCard() {
    setState(() {
      _deviceCancelPending = false;
      _errorMessage = null;
      _noticeMessage = null;
    });
  }

  /// Leaves the code-entry stage without any state change (canceling the
  /// emailed-code factor aborts the change).
  void _backToForm() {
    _resendTimer?.cancel();
    setState(() {
      _stage = _ChangeStage.form;
      _otpSession = null;
      _otpController.clear();
      _codeFieldError = null;
      _errorMessage = null;
      _noticeMessage = null;
      _resendCountdown = 0;
    });
  }

  // ── Resend window (cycle-41 §6.3) ────────────────────────────────────────

  /// Each tap fires [PasswordChangeFactorGate.sendOtpStepUp] again
  /// (quota-governed, user-action-triggered), restarts the window, clears
  /// the previous code error, and shows notice CP-25. A failed resend
  /// renders CP-19 — no weaker fallback, no silent skip; the running window
  /// is not restarted by a failed send.
  Future<void> _resendCode() async {
    final session = _otpSession;
    if (session == null || _isSaving || _resendCountdown > 0) return;

    setState(() {
      _errorMessage = null;
      _codeFieldError = null;
      _noticeMessage = null;
    });

    try {
      await widget.factorGate.sendOtpStepUp(session.email);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = _sendFailed);
      return;
    }
    if (!mounted) return;
    setState(() {
      _noticeMessage = 'A new code is on its way to ${session.email}.';
      _resendCountdown = _resendWindowSeconds;
    });
    _startResendTimer();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCountdown -= 1;
        if (_resendCountdown <= 0) {
          _resendCountdown = 0;
          timer.cancel();
        }
      });
    });
  }

  // ── Error presentation ───────────────────────────────────────────────────

  /// True when [error] is the typed current-password rejection — the ONLY
  /// producer of the inline CP-10 field error on the online path.
  bool _isCurrentPasswordError(Object error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('wrong password') ||
        errorString.contains('invalid-credential');
  }

  /// Chain-level errors render in the error box; the current-password
  /// rejection renders inline under its field (§5.5's channel rule).
  void _presentOnlineError(Object error) {
    if (_isCurrentPasswordError(error)) {
      _showCurrentPasswordError();
      return;
    }
    setState(() => _errorMessage = _mapError(error));
  }

  /// CP-10 inline under the current field; both values keep their content
  /// and focus moves to the current field (§5.4).
  void _showCurrentPasswordError() {
    setState(() {
      _currentFieldError = _incorrectCurrentPassword;
      _formSubmitAttempted = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _currentPasswordFocus.requestFocus();
      // The field's validator channel surfaces [_currentFieldError]; a
      // validate pass (re)renders it with the theme's error border/style.
      _formKey.currentState?.validate();
    });
  }

  /// Error mapping kept from the pre-cycle-31 flow; the guessing fallbacks
  /// are retired — every unmapped failure lands on CP-22 (§10.3).
  String _mapError(Object e) {
    final errorString = e.toString().toLowerCase();
    if (errorString.contains('no user') ||
        errorString.contains('not logged in')) {
      return _sessionExpired;
    }
    if (errorString.contains('network')) {
      return _networkError;
    }
    return _genericFailure;
  }

  // ── Field wiring ─────────────────────────────────────────────────────────

  /// Current password: empty → CP-08; otherwise the service's CP-10 (when
  /// set) surfaces through the same validator channel (§5.5).
  String? _validateCurrentPassword(String? value) {
    if (value == null || value.isEmpty) return _required;
    return _currentFieldError;
  }

  /// New password: empty → CP-08, < 6 chars → CP-09. No maxLength cap —
  /// the ≥6 rule is a validator, never a truncation (§5.2).
  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) return _required;
    if (value.length < 6) return _atLeastSix;
    return null;
  }

  void _onCurrentPasswordChanged(String value) {
    // An edit invalidates the stored CP-10 verdict; clear it immediately.
    if (_currentFieldError != null) {
      setState(() => _currentFieldError = null);
    }
    if (_formSubmitAttempted) {
      _formKey.currentState?.validate();
    }
  }

  void _onNewPasswordChanged(String value) {
    if (_formSubmitAttempted) {
      _formKey.currentState?.validate();
    }
  }

  void _onOtpChanged(String value) {
    if (_codeFieldError != null) {
      setState(() => _codeFieldError = null);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return Scaffold(
      backgroundColor: colors.base,
      appBar: AppBar(
        backgroundColor: colors.base,
        title: Text('Change Password', style: TextStyle(color: colors.ink)),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colors.ink,
            size: 20,
          ),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: _stage == _ChangeStage.form
              ? _buildFormStage(colors)
              : _buildOtpStage(colors),
        ),
      ),
    );
  }

  /// The progressive form (§5): one layout for all classes — the class only
  /// decides which fields exist and which prompts follow. Order top→bottom:
  /// class explainer (Google only) → why-line (current-password classes) →
  /// Current Password group → New Password group → notice → retry card →
  /// error box → CTA.
  Widget _buildFormStage(ThemeColors colors) {
    final session = _session;
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CP-01 — the Google class explainer names all three checks up
            // front (§5.1 row 2).
            if (session != null && session.isGoogleLinked) ...[
              Text(
                "This account signs in with Google. To confirm it's you, "
                "we'll check your Google account and phone lock, then email "
                'a code to ${session.email}.',
                style: AppTypography.body.copyWith(color: colors.subtext),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            // CP-02 — the why-line (§5.1 row 3); shown where the
            // current-password field exists.
            if (_showCurrentPassword) ...[
              Text(
                _whyCurrentPassword,
                style: AppTypography.body.copyWith(color: colors.subtext),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (_showCurrentPassword) ...[
              Text(
                _currentPasswordLabel,
                style: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              PasswordField(
                colors: colors,
                controller: _currentPasswordController,
                focusNode: _currentPasswordFocus,
                label: _currentPasswordLabel,
                prefixIcon: Icons.lock,
                obscured: _obscureCurrent,
                visibilityLabel: _obscureCurrent
                    ? _showPassword
                    : _hidePassword,
                onToggleVisibility: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _newPasswordFocus.requestFocus(),
                validator: _validateCurrentPassword,
                onChanged: _onCurrentPasswordChanged,
                enabled: !_isSaving,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            Text(
              _newPasswordLabel,
              style: AppTypography.label.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            PasswordField(
              colors: colors,
              controller: _newPasswordController,
              focusNode: _newPasswordFocus,
              label: _newPasswordLabel,
              prefixIcon: Icons.lock_outline,
              obscured: _obscureNew,
              visibilityLabel: _obscureNew
                  ? _showNewPassword
                  : _hideNewPassword,
              onToggleVisibility: () =>
                  setState(() => _obscureNew = !_obscureNew),
              helperText: _atLeastSix,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: _validateNewPassword,
              onChanged: _onNewPasswordChanged,
              enabled: !_isSaving,
            ),
            _noticeBox(colors),
            _retryCard(colors),
            _errorBox(colors),
            const SizedBox(height: AppSpacing.xxl),
            _primaryCta(
              colors: colors,
              ctaKey: _formCtaKey,
              label: _formCtaLabel,
              onPressed: _isSaving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  /// The emailed-code stage — Google-linked class ONLY (cycle-41 §6). Same
  /// machinery, honest copy, fixed keyboard behavior, a retry-safe resend.
  Widget _buildOtpStage(ThemeColors colors) {
    final email = _otpSession?.email ?? '';
    final canResend = _resendCountdown == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CP-30 — a stage header, not a field label.
        Text(
          _codeStageTitle,
          style: AppTypography.title.copyWith(color: colors.ink),
        ),
        const SizedBox(height: AppSpacing.sm),
        // CP-23 — names the exact address (retained verbatim).
        Text(
          'Enter the 6-digit code we emailed to $email to confirm this '
          'password change.',
          style: AppTypography.body.copyWith(color: colors.subtext),
        ),
        const SizedBox(height: AppSpacing.sm),
        // CP-24 — the code stage's why-line.
        Text(
          "This is the final check that it's you before your password "
          'changes.',
          style: AppTypography.body.copyWith(color: colors.subtext),
        ),
        const SizedBox(height: AppSpacing.base),
        Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.inputRadius,
            boxShadow: AppShadows.well,
          ),
          child: Semantics(
            label: _codeFieldSemanticsLabel,
            child: SystemKeyboardTextFormField(
              controller: _otpController,
              focusNode: _codeFocus,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              onChanged: _onOtpChanged,
              style: AppTypography.title.copyWith(
                color: colors.ink,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                hintText: '000000',
                hintStyle: AppTypography.body.copyWith(
                  color: colors.subtext,
                  letterSpacing: 8,
                ),
                prefixIcon: Icon(
                  Icons.password_rounded,
                  color: colors.subtext,
                  size: 20,
                ),
                errorText: _codeFieldError,
                filled: true,
                fillColor: colors.base,
                counterText: '',
              ),
            ),
          ),
        ),
        _noticeBox(colors),
        _errorBox(colors),
        const SizedBox(height: AppSpacing.xxl),
        _primaryCta(
          colors: colors,
          ctaKey: _codeCtaKey,
          label: _codeCtaLabel,
          onPressed: _isSaving ? null : _submit,
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextButton(
                onPressed: canResend && !_isSaving ? _resendCode : null,
                // Theme resolves accentInk (enabled) / disabledText.
                child: Text(_resendLabel, style: AppTypography.body),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: _resendCountdown > 0
                    ? Text(
                        'You can request a new code in ${_resendCountdown}s',
                        style: AppTypography.labelSm.copyWith(
                          color: colors.subtext,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: _isSaving ? null : _backToForm,
            // Theme resolves accentInk (enabled) / disabledText.
            child: Text(_backToFormLabel, style: AppTypography.body),
          ),
        ),
      ],
    );
  }

  /// The full-width primary CTA (§5.1 row 10 / §9): accent fill + `raised`
  /// shadow at rest, `flat` + the theme's disabled style while saving,
  /// 20 px spinner in `onAccent` while loading.
  Widget _primaryCta({
    required ThemeColors colors,
    required GlobalKey ctaKey,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Container(
      key: ctaKey,
      decoration: BoxDecoration(
        borderRadius: AppRadius.buttonRadius,
        boxShadow: _isSaving ? AppShadows.flat : AppShadows.raised,
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed,
          child: _isSaving
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onAccent,
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }

  /// The retry card (§7) — inline in the status stack: after the notice
  /// box, above the error box and CTA; enters at [AppDurations.entrance],
  /// disappears on success or when "Back" is taken.
  Widget _retryCard(ThemeColors colors) {
    return AnimatedSwitcher(
      duration: AppDurations.entrance,
      switchInCurve: AppDurations.standardCurve,
      switchOutCurve: AppDurations.standardCurve,
      child: _deviceCancelPending
          ? DeviceRetryCard(
              key: const ValueKey('device-retry-card'),
              colors: colors,
              isBusy: _isSaving,
              showSpinner: _isSaving && _retryInFlight,
              onTryAgain: _retryFailedStep,
              onBack: _backFromRetryCard,
            )
          : const SizedBox.shrink(key: ValueKey('device-retry-hidden')),
    );
  }

  /// Chain-level error line — icon + text in the semantic ink (§11.4's
  /// established icon+text pattern for chain errors). Field-level errors
  /// never render here (§5.5's channel rule).
  Widget _errorBox(ThemeColors colors) {
    final message = _errorMessage;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.base),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, color: colors.errorText, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.label.copyWith(color: colors.errorText),
            ),
          ),
        ],
      ),
    );
  }

  /// Explanatory notice (degraded device step / Google fallback / resend
  /// confirmation). Status ink only — icon + text, never surface decoration.
  Widget _noticeBox(ThemeColors colors) {
    final message = _noticeMessage;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.base),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline,
              color: colors.warningText,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.label.copyWith(color: colors.warningText),
            ),
          ),
        ],
      ),
    );
  }
}
