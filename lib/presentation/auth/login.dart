// ignore_for_file: empty_catches
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../theme/app_theme.dart';
import '../../services/auth/auth_service.dart';
import '../../services/auth/biometric_auth_service.dart';
import '../../repositories/user_repository.dart';
import '../../data/local/local_user_dao.dart';
import '../shared/app_shell.dart';
import '../shared/system_keyboard_text_field.dart';
import 'register.dart';
import 'forgot_password.dart';

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

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final ready = await BiometricAuthService.isSupported() &&
        await BiometricAuthService.isEnrolled();
    if (mounted) setState(() => _biometricReady = ready);
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
        final dao = LocalUserDao();
        await dao.savePendingSignup(
          localId: cred.uid,
          email: email,
          password: password,
          displayName: cred.displayName ?? 'User',
          recoveryCode: '',
          isSynced: true,
        );
      }
    } catch (e) {
      
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
        final storedPassword = localUser['password'] as String;
        if (storedPassword == password) {
          setState(() => _isLoading = false);
          _goToDashboard(isOnline: false);
          return;
        }
      }
} catch (e) {}

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
        );
        try {
          final existing = await UserRepository.getUserProfile(cred.uid);
          if (existing == null) {
            await UserRepository.createUserProfile(
                cred.uid, cred.email ?? '', cred.displayName ?? 'User', '');
          }
        } catch (_) {}
        await _offerBiometricEnroll(cred.uid);
      }
      if (mounted) setState(() => _isLoading = false);
      _goToDashboard(isOnline: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (e is GoogleSignInException &&
            e.code == GoogleSignInExceptionCode.canceled) {
          _errorMessage = 'Google sign-in cancelled';
        } else {
          final msg = e.toString().toLowerCase();
          if (msg.contains('cancelled by user') || msg.contains('code canceled')) {
            _errorMessage = 'Google sign-in cancelled';
          } else if (msg.contains('clientconfiguration') ||
              msg.contains('providerconfiguration') ||
              msg.contains('no id token')) {
            _errorMessage =
                'Google sign-in not configured. Check SHA-1 / OAuth setup.';
          } else if (msg.contains('network') || msg.contains('socket')) {
            _errorMessage = 'Google sign-in failed. Check your connection.';
          } else {
            _errorMessage = 'Google sign-in failed. Check your connection.';
          }
        }
      });
    }
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
              isLoading: _isLoading,
              showBiometric: _biometricReady,
              colors: colors,
              onTogglePassword: _togglePassword,
              onLogin: _login,
              onGoogleSignIn: _signInWithGoogle,
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
  final bool isLoading;
  final bool showBiometric;
  final ThemeColors colors;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onBiometricUnlock;
  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;

  const _LoginForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.showPassword,
    this.errorMessage,
    required this.isLoading,
    required this.showBiometric,
    required this.colors,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onGoogleSignIn,
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.error.withValues(alpha: 0.25)),
              ),
              child: Text(errorMessage!,
                  style: TextStyle(color: colors.error)),
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
