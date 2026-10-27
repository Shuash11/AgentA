import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../cubit/connectivity/connectivity_cubit.dart';
import '../../services/auth/auth_service.dart';
import '../../services/auth/biometric_auth_service.dart';
import '../../services/auth/offline_password_service.dart';
import '../../theme/app_theme.dart';
import '../shared/system_keyboard_text_field.dart';

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
  /// Google-only account has none, so the Google factor replaces that step
  /// and the current-password field is hidden (cycle-31 plan, matrix row).
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
  /// Fail-closed (Adviser ruling): a typed [GoogleSignInFailure] (canceled /
  /// unsupported / email mismatch / plugin error — the P1 fallback triggers)
  /// or a null return (test seam only) is never a satisfied factor; the
  /// caller automatically falls back to the emailed OTP.
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

  /// Emails the step-up code to the session account (automatic fallback).
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
  /// confirmed (cancel or platform error) → the caller aborts.
  Future<bool> confirmDeviceCredential(String localizedReason) =>
      BiometricAuthService.confirmDeviceCredential(
        localizedReason: localizedReason,
      );
}

/// Internal abort signal: a canceled factor prompt ends the change with a
/// message and no password update.
class _FactorAborted implements Exception {
  const _FactorAborted(this.message);

  final String message;
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

/// UI stage of the change flow — the OTP fallback pauses on [otpCode].
enum _ChangeStage { form, otpCode }

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  /// Distinct step-up wording for the system prompt (P2 contract: step-up
  /// wording, not the enroll/unlock strings).
  static const String _devicePromptReason =
      'Confirm your identity to change your password';

  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  _ChangeStage _stage = _ChangeStage.form;

  /// Session facts captured when the page opens.
  PasswordChangeSession? _session;

  /// The session behind the pending OTP step-up (set when the fallback
  /// starts; cleared when the user goes back to the form).
  PasswordChangeSession? _otpSession;

  bool _isSaving = false;
  String? _errorMessage;
  String? _noticeMessage;

  /// The offline flow service (P4) — built once, overridable in tests.
  late final OfflinePasswordService _offlineService;

  /// The baseline current-password field is shown whenever a password can
  /// exist; a Google-only session has none (matrix row).
  bool get _showCurrentPassword => _session?.hasPassword ?? true;

  @override
  void initState() {
    super.initState();
    _session = widget.factorGate.loadSession();
    _offlineService = widget.offlineService ?? OfflinePasswordService();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// Entry point for both stages: the form submit starts the factor chain;
  /// the OTP stage verifies the emailed code and resumes it.
  Future<void> _submit() async {
    if (_isSaving) return;
    if (_stage == _ChangeStage.otpCode) {
      await _verifyOtpCode();
      return;
    }

    if (!_formKey.currentState!.validate()) return;

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
      setState(() {
        _errorMessage =
            'Changing password needs internet. Your current password still works offline.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _noticeMessage = null;
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
      if (session.isGoogleLinked) {
        final googleVerified = await widget.factorGate.verifyGoogleReauth(
          session.email,
        );
        if (!googleVerified) {
          // P1 triggers (typed failure / account mismatch / null) →
          // automatic OTP fallback; the flow pauses on code entry.
          await _startOtpFallback(session);
          return;
        }
      }
      await _confirmDeviceThenUpdate();
    } on _FactorAborted catch (abort) {
      if (mounted) setState(() => _errorMessage = abort.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = _mapError(e, session));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Offline password change (cycle-31 P4) for a session with no Supabase
  /// user: the local row is the credential. [OfflinePasswordService] owns
  /// the proof order — current-password Argon2id verify, then the device
  /// credential when the device can show it — and the compare-and-swap hash
  /// write. Works with zero connectivity.
  Future<void> _submitOffline() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      // Pre-probe (P3 pattern): decides prompt-vs-degrade BEFORE any prompt
      // call; false means the device step degrades (fail-open) and the user
      // gets the notice while the change runs.
      final deviceAvailable = await _offlineService
          .deviceCredentialPromptAvailable();
      if (!deviceAvailable && mounted) {
        setState(() {
          _noticeMessage =
              "This phone has no screen lock, so it can't confirm it's you. Continuing with your current password check only.";
        });
      }

      await _offlineService.updateLocalPassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
        localizedReason: _devicePromptReason,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password changed!')));
      Navigator.popUntil(context, (route) => route.isFirst);
    } on OfflinePasswordChangeException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = _offlineErrorMessage(e.reason));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Something went wrong. Your password was not changed.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Offline failure wording. No message claims a recovery-code use and no
  /// message implies a network call — the offline change is fully on-device.
  String _offlineErrorMessage(OfflinePasswordChangeFailure reason) {
    switch (reason) {
      case OfflinePasswordChangeFailure.noSession:
      case OfflinePasswordChangeFailure.accountNotFound:
        return 'Session expired. Please log in again.';
      case OfflinePasswordChangeFailure.accountRequiresOnline:
        return 'Changing password needs internet. Your current password still works offline.';
      case OfflinePasswordChangeFailure.lockedOut:
        return 'Too many attempts. Try again later.';
      case OfflinePasswordChangeFailure.wrongPassword:
        return 'Current password is incorrect';
      case OfflinePasswordChangeFailure.deviceCancelled:
        return 'Device confirmation was canceled. Your password was not changed.';
      case OfflinePasswordChangeFailure.updateConflict:
        return 'Your account changed before the update finished. Your password was not changed.';
    }
  }

  /// Automatic fallback: emails the step-up code to the SESSION account's
  /// address and advances to code entry. A send failure aborts with a
  /// retryable message — no password update, no session change.
  Future<void> _startOtpFallback(PasswordChangeSession session) async {
    try {
      await widget.factorGate.sendOtpStepUp(session.email);
    } catch (_) {
      throw const _FactorAborted(
        "We couldn't send the code to your email. Check your connection and try again.",
      );
    }
    if (!mounted) return;
    setState(() {
      _otpSession = session;
      _stage = _ChangeStage.otpCode;
      _otpController.clear();
      _errorMessage = null;
      _noticeMessage =
          "We couldn't verify with Google. Instead, we emailed a 6-digit code to ${session.email}.";
    });
  }

  /// Verifies the emailed code and resumes the chain.
  ///
  /// Ruling: a wrong/expired code is a no-op — no session change, no
  /// password update, the user stays signed in, and code entry stays
  /// retryable.
  Future<void> _verifyOtpCode() async {
    final session = _otpSession;
    if (session == null) {
      _backToForm();
      return;
    }
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Enter the 6-digit code from your email.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final verified = await widget.factorGate.verifyOtpStepUp(
        session.email,
        code,
      );
      if (!verified) {
        if (mounted) {
          setState(
            () => _errorMessage =
                'That code is invalid or expired. Check the email and try again.',
          );
        }
        return;
      }
      await _confirmDeviceThenUpdate();
    } on _FactorAborted catch (abort) {
      if (mounted) setState(() => _errorMessage = abort.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = _mapError(e, session));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Device-credential step, then the actual password write.
  ///
  /// Plan policy: no screen lock → degrade (skip + notice), never block; a
  /// canceled prompt aborts with no password update. On success the session
  /// is KEPT — the fresh session the OTP step-up issued is OWASP's
  /// password-change token renewal; no sign-out on this path (Adviser
  /// ruling).
  Future<void> _confirmDeviceThenUpdate() async {
    if (await widget.factorGate.deviceCredentialPromptAvailable()) {
      final confirmed = await widget.factorGate.confirmDeviceCredential(
        _devicePromptReason,
      );
      if (!confirmed) {
        throw const _FactorAborted(
          'Device confirmation was canceled. Your password was not changed.',
        );
      }
    } else if (mounted) {
      setState(() {
        _noticeMessage =
            "This phone has no screen lock, so it can't confirm it's you. Continuing with the check you already passed.";
      });
    }

    await widget.factorGate.updatePassword(_newPasswordController.text);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Password changed!')));
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  /// Leaves the code-entry stage without any state change (canceling the
  /// fallback factor aborts the change).
  void _backToForm() {
    setState(() {
      _stage = _ChangeStage.form;
      _otpSession = null;
      _otpController.clear();
      _errorMessage = null;
      _noticeMessage = null;
    });
  }

  /// Error mapping kept from the pre-cycle-31 flow, extended with wording
  /// that fits a Google-only session (no password step exists there).
  String _mapError(Object e, PasswordChangeSession session) {
    final errorString = e.toString().toLowerCase();
    if (errorString.contains('wrong password') ||
        errorString.contains('invalid-credential')) {
      return 'Current password is incorrect';
    }
    if (errorString.contains('no user') ||
        errorString.contains('not logged in')) {
      return 'Session expired. Please log in again.';
    }
    if (errorString.contains('network')) {
      return 'Network error. Check your connection.';
    }
    return session.hasPassword
        ? 'Failed. Check current password.'
        : 'Failed. Check your connection and try again.';
  }

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
          padding: const EdgeInsets.all(24),
          child: _stage == _ChangeStage.form
              ? _buildFormStage(colors)
              : _buildOtpStage(colors),
        ),
      ),
    );
  }

  /// The password form: baseline current-password field (only when the
  /// account has a password), the new password, and the submit button.
  Widget _buildFormStage(ThemeColors colors) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showCurrentPassword) ...[
            Text(
              'Current Password',
              style: AppTypography.label.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.inputRadius,
                boxShadow: AppShadows.well,
              ),
              child: SystemKeyboardTextFormField(
                controller: _currentPasswordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                style: AppTypography.body.copyWith(color: colors.ink),
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  prefixIcon: Icon(Icons.lock, color: colors.subtext, size: 20),
                  filled: true,
                  fillColor: colors.base,
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text(
            'New Password',
            style: AppTypography.label.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.inputRadius,
              boxShadow: AppShadows.well,
            ),
            child: SystemKeyboardTextFormField(
              controller: _newPasswordController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              style: AppTypography.body.copyWith(color: colors.ink),
              decoration: InputDecoration(
                labelText: 'New Password',
                prefixIcon: Icon(
                  Icons.lock_outline,
                  color: colors.subtext,
                  size: 20,
                ),
                filled: true,
                fillColor: colors.base,
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v.length < 6) return 'At least 6 characters';
                return null;
              },
            ),
          ),
          _noticeBox(colors),
          _errorBox(colors),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.buttonRadius,
              boxShadow: AppShadows.raised,
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submit,
                child: _isSaving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onAccent,
                        ),
                      )
                    : const Text('Change Password'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The OTP fallback stage: code entry for the emailed step-up code. The
  /// copy states which factor is being requested.
  Widget _buildOtpStage(ThemeColors colors) {
    final email = _otpSession?.email ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verification Code',
          style: AppTypography.label.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-digit code we emailed to $email to confirm this password change.',
          style: AppTypography.body.copyWith(color: colors.subtext),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.inputRadius,
            boxShadow: AppShadows.well,
          ),
          child: SystemKeyboardTextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autocorrect: false,
            enableSuggestions: false,
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
              filled: true,
              fillColor: colors.base,
              counterText: '',
            ),
          ),
        ),
        _noticeBox(colors),
        _errorBox(colors),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.buttonRadius,
            boxShadow: AppShadows.raised,
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onAccent,
                      ),
                    )
                  : const Text('Verify & Change Password'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: _isSaving ? null : _backToForm,
            child: Text(
              'Back to password form',
              style: AppTypography.body.copyWith(color: colors.accentInk),
            ),
          ),
        ),
      ],
    );
  }

  /// Error line (pre-cycle-31 style).
  Widget _errorBox(ThemeColors colors) {
    final message = _errorMessage;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        message,
        style: AppTypography.label.copyWith(color: colors.errorText),
      ),
    );
  }

  /// Explanatory notice (automatic OTP fallback / degraded device step).
  /// Status ink only — icon + text, never surface decoration.
  Widget _noticeBox(ThemeColors colors) {
    final message = _noticeMessage;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
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
