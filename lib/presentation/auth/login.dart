import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_config.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../theme/app_theme.dart';
import '../../services/auth/auth_service.dart';
import '../../services/auth/biometric_auth_service.dart';
import '../../services/auth/session_manager.dart';
import '../../repositories/user_repository.dart';
import '../../data/local/local_user_dao.dart';
import '../shared/app_shell.dart';
import '../shared/system_keyboard_text_field.dart';
import 'register.dart';
import 'forgot_password.dart';

/// User-facing result of mapping a Google sign-in error.
class _GoogleSignInPresentation {
  final String message;
  final GoogleSignInFailure? failure;
  final bool isCancel;

  const _GoogleSignInPresentation({
    required this.message,
    this.failure,
    this.isCancel = false,
  });
}

/// Single label/value line inside the diagnostics dialog.
class _DiagnosticsRow extends StatelessWidget {
  final String label;
  final String value;

  const _DiagnosticsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Non-blocking warning shown at the top of login when
/// [AppConfig.googleConfigured] is false. Never blocks sign-in.
class _GoogleConfigBanner extends StatelessWidget {
  final ThemeColors colors;
  final String message;

  const _GoogleConfigBanner({required this.colors, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.withOpacity(colors.amber, 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.withOpacity(colors.amber, 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Google sign-in needs setup',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$message Check the setup docs for SHA-1 / OAuth / Supabase steps.',
                  style: TextStyle(color: colors.subtext, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _biometricReady = false;
  String? _errorMessage;

  // Google sign-in UX state: distinguishes genuine user-cancel from
  // repeated cancel (almost certainly a setup issue).
  int _consecutiveGoogleCancel = 0;
  GoogleSignInFailure? _lastGoogleFailure;
  bool _showGoogleFailureDetails = false;

  /// Android applicationId (must match SHA-1 registration in
  /// Google Cloud Console / Firebase). Kept as a constant so the
  /// diagnostics dialog never needs a new platform plugin.
  static const String _androidPackageName = 'com.agenta.AgentA';

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final ready = await BiometricAuthService.isSupported() &&
        await BiometricAuthService.isEnrolled();
    final lastEmail = await SessionManager.lastEmail();
    if (mounted) {
      setState(() => _biometricReady = ready);
      if (lastEmail != null &&
          lastEmail.isNotEmpty &&
          _emailController.text.isEmpty) {
        _emailController.text = lastEmail;
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    bool isOnline = false;
    String? onlineUid;

    try {
      final cred = await AuthService.login(email, password);
      isOnline = true;
      onlineUid = cred.uid;

      if (cred.uid.isNotEmpty) {
        try {
          final existing = await UserRepository.getUserProfile(cred.uid);
          if (existing == null) {
            await UserRepository.createUserProfile(
                cred.uid, email, cred.displayName ?? 'User', '');
          }
        } catch (e, stack) {
          if (kDebugMode) {
            debugPrint('[Login] _login ensure profile failed: $e | $stack');
          }
        }
        final dao = LocalUserDao();
        await dao.savePendingSignup(
          localId: cred.uid,
          email: email,
          password: SessionManager.hashPassword(password),
          displayName: cred.displayName ?? 'User',
          recoveryCode: '',
          isSynced: true,
          provider: 'password',
        );
        await SessionManager.stashPassword(cred.uid, password);
        await SessionManager.saveSession(
          uid: cred.uid,
          email: email,
          provider: 'password',
        );
      }
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[Login] _login online attempt failed: $e | $stack');
      }
      final errorString = e.toString().toLowerCase();
      if (!AuthService.isBackendReady ||
          errorString.contains('network') ||
          errorString.contains('socket')) {
        // Backend unreachable - try offline login
        isOnline = false;
      } else {
        // Auth error (wrong password, user not found, etc.) - show immediately
        if (mounted) {
          setState(() {
            _isLoading = false;
            String errorMsg = 'Login failed';
            if (errorString.contains('user-not-found') ||
                errorString.contains('invalid-email') ||
                errorString.contains('invalid login credentials')) {
              errorMsg = 'Invalid email or password';
            } else if (errorString.contains('wrong-password') ||
                errorString.contains('invalid-credential')) {
              errorMsg = 'Invalid password';
            } else if (errorString.contains('too-many-requests') ||
                errorString.contains('rate limit')) {
              errorMsg = 'Too many attempts. Try again later.';
            } else if (errorString.contains('email not confirmed')) {
              errorMsg = 'Please confirm your email first';
            }
            _errorMessage = errorMsg;
          });
        }
        return;
      }
    }

    if (isOnline) {
      setState(() => _isLoading = false);
      if (onlineUid != null) {
        await _offerBiometricEnroll(onlineUid);
      }
      _goToDashboard(isOnline: true);
      return;
    }

    try {
      final dao = LocalUserDao();
      final localUser = await dao.getUserByEmail(email);

      if (localUser != null) {
        final provider =
            (localUser['provider'] as String?) ?? 'password';
        if (provider == 'google') {
          await SessionManager.saveSession(
            uid: localUser['local_id'] as String,
            email: email,
            provider: 'google',
          );
          setState(() => _isLoading = false);
          _goToDashboard(isOnline: false);
          return;
        }
        final storedHash = localUser['password'] as String;
        if (storedHash.isNotEmpty &&
            storedHash == SessionManager.hashPassword(password)) {
          await SessionManager.saveSession(
            uid: localUser['local_id'] as String,
            email: email,
            provider: 'password',
          );
          setState(() => _isLoading = false);
          _goToDashboard(isOnline: false);
          return;
        }
      }
} catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[Login] _login offline fallback failed: $e | $stack');
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = 'Invalid email or password';
    });
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final cred = await AuthService.signInWithGoogle();
      if (cred.uid.isNotEmpty) {
        final dao = LocalUserDao();
        await dao.savePendingSignup(
          localId: cred.uid,
          email: cred.email ?? '',
          password: '',
          displayName: cred.displayName ?? 'User',
          recoveryCode: '',
          isSynced: true,
          provider: 'google',
        );
        await SessionManager.saveSession(
          uid: cred.uid,
          email: cred.email ?? '',
          provider: 'google',
        );
        try {
          final existing = await UserRepository.getUserProfile(cred.uid);
          if (existing == null) {
            await UserRepository.createUserProfile(
                cred.uid, cred.email ?? '', cred.displayName ?? 'User', '');
          }
        } catch (e, stack) {
          if (kDebugMode) {
            debugPrint('[Login] Google sign-in ensure profile failed: $e | $stack');
          }
        }
        await _offerBiometricEnroll(cred.uid);
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _consecutiveGoogleCancel = 0;
          _lastGoogleFailure = null;
          _showGoogleFailureDetails = false;
        });
      }
      _goToDashboard(isOnline: true);
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[Login] Google sign-in failed: $e | $stack');
      }
      if (!mounted) return;
      final presentation = _mapGoogleError(e);
      setState(() {
        _isLoading = false;
        if (presentation.isCancel) {
          _consecutiveGoogleCancel += 1;
        } else {
          _consecutiveGoogleCancel = 0;
        }
        _lastGoogleFailure = presentation.failure;
        _showGoogleFailureDetails = false;
        _errorMessage = presentation.message;
      });
    }
  }

  /// Maps a sign-in error to user-facing copy.
  ///
  /// Prefers the typed [GoogleSignInFailure] contract
  /// (`code` / `detail` / `hint`) from [AuthService]; falls back to
  /// legacy string matching only for unknown exception shapes.
  /// `failure.code == 'canceled'` is the single source of truth for
  /// genuine user-cancel — no substring checks on the typed path.
  _GoogleSignInPresentation _mapGoogleError(Object e) {
    if (e is GoogleSignInFailure) {
      if (e.code == 'canceled') {
        if (_consecutiveGoogleCancel >= 1) {
          return _GoogleSignInPresentation(
            message:
                'Repeated cancel — almost certainly a setup issue (SHA-1 / OAuth / Supabase). '
                'If you kept cancelling by hand, just try again.',
            failure: e,
            isCancel: true,
          );
        }
        return _GoogleSignInPresentation(
          message: 'You cancelled — try again.',
          failure: e,
          isCancel: true,
        );
      }
      switch (e.code) {
        case 'not_configured':
        case 'init_failed':
        case 'no_id_token':
          return _GoogleSignInPresentation(
            message: 'Google sign-in not configured. Check SHA-1 / OAuth setup.',
            failure: e,
          );
        case 'supabase_rejected':
        case 'no_user':
          return _GoogleSignInPresentation(
            message:
                'Google sign-in was rejected. Check the Supabase Google provider setup.',
            failure: e,
          );
        default:
          final detail = (e.detail ?? '').trim();
          return _GoogleSignInPresentation(
            message: detail.isEmpty
                ? 'Google sign-in failed (${e.code}).'
                : 'Google sign-in failed: $detail',
            failure: e,
          );
      }
    }

    // Legacy fallback for non-typed exceptions (old plugin shapes).
    final msg = e.toString().toLowerCase();
    if (msg.contains('cancelled by user') ||
        msg.contains('canceled') ||
        msg.contains('code canceled')) {
      if (_consecutiveGoogleCancel >= 1) {
        return const _GoogleSignInPresentation(
          message:
              'Repeated cancel — almost certainly a setup issue (SHA-1 / OAuth / Supabase). '
              'If you kept cancelling by hand, just try again.',
          isCancel: true,
        );
      }
      return const _GoogleSignInPresentation(
        message: 'You cancelled — try again.',
        isCancel: true,
      );
    }
    if (msg.contains('clientconfiguration') ||
        msg.contains('providerconfiguration') ||
        msg.contains('no id token') ||
        msg.contains('not configured') ||
        msg.contains('serverclientid') ||
        msg.contains('sha-1') ||
        msg.contains('oauth')) {
      return const _GoogleSignInPresentation(
        message: 'Google sign-in not configured. Check SHA-1 / OAuth setup.',
      );
    }
    if (msg.contains('network') || msg.contains('socket')) {
      return const _GoogleSignInPresentation(
        message: 'Google sign-in failed. Check your connection.',
      );
    }
    return _GoogleSignInPresentation(
      message:
          'Google sign-in failed: ${e.toString().replaceAll('Exception: ', '')}',
    );
  }

  /// Hidden diagnostics: long-press on the Google button.
  /// Shows package name + client-ID suffix + backend flag.
  /// Never shows the full client ID or any token.
  Future<void> _showGoogleDiagnostics() async {
    if (kDebugMode) {
      debugPrint(
          '[Login] Google diagnostics opened | suffix: ...${AppConfig.googleIdSuffixForLog} '
          '| configured: ${AppConfig.googleConfigured} '
          '| backendReady: ${AuthService.isBackendReady}');
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google sign-in diagnostics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DiagnosticsRow(
                label: 'Package', value: _androidPackageName),
            _DiagnosticsRow(
                label: 'Client ID suffix',
                value: '...${AppConfig.googleIdSuffixForLog}'),
            _DiagnosticsRow(
                label: 'Configured',
                value: AppConfig.googleConfigured ? 'yes' : 'no'),
            _DiagnosticsRow(
                label: 'Backend ready',
                value: AuthService.isBackendReady ? 'yes' : 'no'),
            if (AppConfig.googleConfigError != null) ...[
              const SizedBox(height: 8),
              Text(
                AppConfig.googleConfigError!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Full client ID and tokens are never shown here.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _unlockWithBiometrics() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final uid = await BiometricAuthService.unlock();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (uid != null) {
      final dao = LocalUserDao();
      final row = await dao.getPendingSignupByLocalId(uid);
      await SessionManager.saveSession(
        uid: uid,
        email: (row?['email'] as String?) ?? '',
        provider: (row?['provider'] as String?) ?? 'password',
      );
      _goToDashboard(isOnline: false);
    }
  }

  Future<void> _offerBiometricEnroll(String uid) async {
    if (!mounted) return;
    if (!await BiometricAuthService.isSupported()) return;
    if (await BiometricAuthService.isEnrolled()) return;
    if (!mounted) return;
    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick unlock?'),
        content: const Text(
            'Use your fingerprint to get back in quickly, even offline if you forget your password.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (enable == true && mounted) {
      await BiometricAuthService.enroll(uid);
      _checkBiometric();
    }
  }

  void _goToDashboard({required bool isOnline}) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AppShell(offlineMode: !isOnline),
      ),
    );
  }

  void _togglePassword() {
    setState(() {
      _showPassword = !_showPassword;
    });
  }

@override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return SafeArea(
      child: Scaffold(
        backgroundColor: colors.background,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 100),
            child: _LoginForm(
              formKey: _formKey,
              emailController: _emailController,
              passwordController: _passwordController,
              showPassword: _showPassword,
              errorMessage: _errorMessage,
              googleFailure: _lastGoogleFailure,
              showGoogleFailureDetails: _showGoogleFailureDetails,
              isLoading: _isLoading,
              showBiometric: _biometricReady,
              colors: colors,
              onTogglePassword: _togglePassword,
              onToggleGoogleDetails: () => setState(
                  () => _showGoogleFailureDetails = !_showGoogleFailureDetails),
              onLogin: _login,
              onGoogleSignIn: _signInWithGoogle,
              onGoogleLongPress: _showGoogleDiagnostics,
              onBiometricUnlock: _unlockWithBiometrics,
              onForgotPassword: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              ),
              onCreateAccount: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterPage()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool showPassword;
  final String? errorMessage;
  final GoogleSignInFailure? googleFailure;
  final bool showGoogleFailureDetails;
  final bool isLoading;
  final bool showBiometric;
  final ThemeColors colors;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleGoogleDetails;
  final VoidCallback onLogin;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onGoogleLongPress;
  final VoidCallback onBiometricUnlock;
  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;

  const _LoginForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.showPassword,
    this.errorMessage,
    this.googleFailure,
    this.showGoogleFailureDetails = false,
    required this.isLoading,
    required this.showBiometric,
    required this.colors,
    required this.onTogglePassword,
    required this.onToggleGoogleDetails,
    required this.onLogin,
    required this.onGoogleSignIn,
    required this.onGoogleLongPress,
    required this.onBiometricUnlock,
    required this.onForgotPassword,
    required this.onCreateAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          if (!AppConfig.googleConfigured)
            _GoogleConfigBanner(
              colors: colors,
              message: AppConfig.googleConfigError ??
                  'Google sign-in is not configured.',
            ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.withOpacity(colors.amber, 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bolt_rounded, color: colors.amber, size: 48),
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text("Welcome Back",
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: colors.text)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text("Sign in to continue",
                style: TextStyle(color: colors.subtext, fontSize: 15)),
          ),
          const SizedBox(height: 44),
          Text("Email",
              style: TextStyle(fontWeight: FontWeight.w600, color: colors.subtext)),
          const SizedBox(height: 8),
          SystemKeyboardTextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: colors.text),
            validator: AuthService.validateEmail,
            decoration: InputDecoration(
              hintText: "Email",
              hintStyle: TextStyle(color: colors.subtext),
              prefixIcon: Icon(Icons.email_outlined, color: colors.amber),
              filled: true,
              fillColor: colors.input,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.amber, width: 1.2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.error, width: 1.2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text("Password",
              style: TextStyle(fontWeight: FontWeight.w600, color: colors.subtext)),
          const SizedBox(height: 8),
          SystemKeyboardTextFormField(
            controller: passwordController,
            obscureText: !showPassword,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: colors.text),
            validator: AuthService.validatePassword,
            decoration: InputDecoration(
              hintText: "Password",
              hintStyle: TextStyle(color: colors.subtext),
              prefixIcon: Icon(Icons.lock_outline, color: colors.amber),
              filled: true,
              fillColor: colors.input,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.amber, width: 1.2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.error, width: 1.2),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                    showPassword ? Icons.visibility_off : Icons.visibility,
                    color: colors.subtext),
                onPressed: onTogglePassword,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onForgotPassword,
              child: Text("Forgot Password?",
                  style: TextStyle(color: colors.amber, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 30),
          if (errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.error.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(errorMessage!,
                      style: TextStyle(color: colors.error)),
                  if (googleFailure != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onToggleGoogleDetails,
                        child: Text(
                          showGoogleFailureDetails
                              ? 'Hide details'
                              : 'Show details',
                          style: TextStyle(
                              color: colors.error,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (showGoogleFailureDetails)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          'code: ${googleFailure!.code}\n'
                          'detail: ${googleFailure!.detail ?? '(none)'}\n'
                          'hint: ${googleFailure!.hint}',
                          style: TextStyle(
                            color: colors.error,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: isLoading ? null : onLogin,
              child: SizedBox(
                height: 22,
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text("Sign In",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : onGoogleSignIn,
              onLongPress: onGoogleLongPress,
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: const Text("Continue with Google"),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.text,
                side: BorderSide(color: colors.border),
              ),
            ),
          ),
          if (showBiometric) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton.icon(
                onPressed: isLoading ? null : onBiometricUnlock,
                icon: Icon(Icons.fingerprint, color: colors.amber),
                label: const Text("Unlock with fingerprint"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.text,
                  side: BorderSide(color: colors.border),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: onCreateAccount,
              icon: const Icon(Icons.person_add),
              label: const Text("Create Account"),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.text,
                side: BorderSide(color: colors.border),
              ),
            ),
          ),
        ],
      ),
    );  

    
  }
}
