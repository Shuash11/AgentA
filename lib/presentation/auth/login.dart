// ignore_for_file: empty_catches
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../theme/app_theme.dart';
import '../../services/auth/auth_service.dart';
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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
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

    try {
      final cred = await AuthService.login(email, password);
      isOnline = true;

      if (cred.user != null) {
        final dao = LocalUserDao();
        await dao.savePendingSignup(
          localId: cred.user!.uid,
          email: email,
          password: password,
          displayName: cred.user!.displayName ?? 'User',
          recoveryCode: '',
          isSynced: true,
        );
      }
    } catch (e) {
      
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') || errorString.contains('socket')) {
        // Network error - try offline login
        isOnline = false;
      } else {
        // Auth error (wrong password, user not found, etc.) - show immediately
        if (mounted) {
          setState(() {
            _isLoading = false;
            String errorMsg = 'Login failed';
            if (errorString.contains('user-not-found') || errorString.contains('invalid-email')) {
              errorMsg = 'User not found';
            } else if (errorString.contains('wrong-password') || errorString.contains('invalid-credential')) {
              errorMsg = 'Invalid password';
            } else if (errorString.contains('too-many-requests')) {
              errorMsg = 'Too many attempts. Try again later.';
            }
            _errorMessage = errorMsg;
          });
        }
        return;
      }
    }

    if (isOnline) {
      setState(() => _isLoading = false);
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
              colors: colors,
              onTogglePassword: _togglePassword,
              onLogin: _login,
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
  final ThemeColors colors;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;

  const _LoginForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.showPassword,
    this.errorMessage,
    required this.isLoading,
    required this.colors,
    required this.onTogglePassword,
    required this.onLogin,
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
