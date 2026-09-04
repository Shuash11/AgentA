import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../services/auth/auth_service.dart';
import '../../repositories/user_repository.dart';
import '../../data/local/local_user_dao.dart';
import '../../presentation/shared/app_shell.dart';
import '../../theme/app_theme.dart';
import '../shared/system_keyboard_text_field.dart';
import 'dart:math';
import 'package:uuid/uuid.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  late ThemeColors _colors;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _errorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final code = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }

  void _register() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final displayName = '${_firstNameController.text} ${_lastNameController.text}';
    final recoveryCode = _generateRecoveryCode();
    final email = _emailController.text;
    final password = _passwordController.text;

    final localUserDao = LocalUserDao();

    bool isOnline = false;

    try {
      final cred = await AuthService.register(email, password, displayName);
      final uid = cred.uid;
      await UserRepository.createUserProfile(uid, email, displayName, recoveryCode);
      isOnline = true;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      final isNetwork = msg.contains('network') ||
          msg.contains('socket') ||
          msg.contains('failed host') ||
          e.statusCode == '408';
      if (!isNetwork) {
        setState(() {
          _isLoading = false;
          _errorMessage = _friendlyAuthError(msg);
        });
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error. Registering offline...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Online registration failed. Registering offline...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    final localId = const Uuid().v4();
    await localUserDao.savePendingSignup(
      localId: localId,
      email: email,
      password: password,
      displayName: displayName,
      recoveryCode: recoveryCode,
      isSynced: isOnline,
    );

    setState(() => _isLoading = false);

    if (mounted) {
      await _showRecoveryCodeDialog(recoveryCode, isOffline: !isOnline);
    }
  }

  String _friendlyAuthError(String message) {
    if (message.contains('already registered') ||
        message.contains('already exists') ||
        message.contains('already in use')) {
      return 'This email is already registered. Please sign in.';
    }
    if (message.contains('invalid email') || message.contains('invalid-email')) {
      return 'The email address is not valid.';
    }
    if (message.contains('password')) {
      return 'Password is too weak. Use at least 6 characters.';
    }
    if (message.contains('signups not allowed') ||
        message.contains('not enabled')) {
      return 'Sign-up is not enabled. Contact support.';
    }
    return 'Registration failed. Please try again.';
  }

  void _togglePassword() {
    setState(() {
      _showPassword = !_showPassword;
    });
  }

  void _toggleConfirmPassword() {
    setState(() {
      _showConfirmPassword = !_showConfirmPassword;
    });
  }

  Future<void> _showRecoveryCodeDialog(String recoveryCode, {bool isOffline = false}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecoveryCodeDialog(
        recoveryCode: recoveryCode,
        isOffline: isOffline,
        colors: _colors,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _colors = context.select((ThemeCubit c) => c.state.colors);

    return SafeArea(
      child: Scaffold(
        backgroundColor: _colors.background,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 100),
            child: _RegisterForm(
              formKey: _formKey,
              firstNameController: _firstNameController,
              lastNameController: _lastNameController,
              emailController: _emailController,
              passwordController: _passwordController,
              confirmPasswordController: _confirmPasswordController,
              showPassword: _showPassword,
              showConfirmPassword: _showConfirmPassword,
              errorMessage: _errorMessage,
              isLoading: _isLoading,
              colors: _colors,
              onTogglePassword: _togglePassword,
              onToggleConfirmPassword: _toggleConfirmPassword,
              onRegister: _register,
              onSignIn: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegisterForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool showPassword;
  final bool showConfirmPassword;
  final String? errorMessage;
  final bool isLoading;
  final ThemeColors colors;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmPassword;
  final VoidCallback onRegister;
  final VoidCallback onSignIn;

  const _RegisterForm({
    required this.formKey,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.showPassword,
    required this.showConfirmPassword,
    this.errorMessage,
    required this.isLoading,
    required this.colors,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onRegister,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.withOpacity(colors.amber, 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bolt_rounded,
                color: colors.amber,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              "Create Account",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colors.text,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              "Fill in your details to get started",
              style: TextStyle(color: colors.subtext, fontSize: 15),
            ),
          ),
          const SizedBox(height: 36),
          _fieldLabel("Full Name", colors.text),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: firstNameController,
                  hint: "First name",
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Required'
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: lastNameController,
                  hint: "Last name",
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Required'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _fieldLabel("Email", colors.text),
          const SizedBox(height: 8),
          _buildTextField(
            controller: emailController,
            hint: "Enter your email",
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: AuthService.validateEmail,
          ),
          const SizedBox(height: 20),
          _fieldLabel("Password", colors.text),
          const SizedBox(height: 8),
          _buildPasswordField(
            controller: passwordController,
            hint: "Create a password",
            show: showPassword,
            onToggle: onTogglePassword,
            validator: AuthService.validatePassword,
          ),
          const SizedBox(height: 20),
          _fieldLabel("Confirm Password", colors.text),
          const SizedBox(height: 8),
          _buildPasswordField(
            controller: confirmPasswordController,
            hint: "Re-enter your password",
            show: showConfirmPassword,
            onToggle: onToggleConfirmPassword,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v != passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.withOpacity(colors.error, 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.withOpacity(colors.error, 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: TextStyle(color: colors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.amber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: isLoading ? null : onRegister,
              child: SizedBox(
                height: 22,
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Create Account",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Divider(color: colors.border, thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text("or", style: TextStyle(color: colors.subtext)),
              ),
              Expanded(child: Divider(color: colors.border, thickness: 1)),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: InkWell(
              onTap: onSignIn,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: RichText(
                  text: TextSpan(
                    text: "Already have an account? ",
                    style: TextStyle(color: colors.subtext),
                    children: [
                      TextSpan(
                        text: "Sign In",
                        style: TextStyle(
                          color: colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label, Color textColor) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return SystemKeyboardTextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: TextStyle(color: colors.text),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.subtext),
        prefixIcon: Icon(icon, color: colors.amber, size: 20),
        filled: true,
        fillColor: colors.input,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.amber, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool show,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return SystemKeyboardTextFormField(
      controller: controller,
      obscureText: !show,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(color: colors.text),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.subtext),
        prefixIcon: Icon(Icons.lock_outline, color: colors.amber, size: 20),
        filled: true,
        fillColor: colors.input,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.amber, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        suffixIcon: IconButton(
          icon: Icon(
            show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: colors.subtext,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class _RecoveryCodeDialog extends StatelessWidget {
  final String recoveryCode;
  final bool isOffline;
  final ThemeColors colors;

  const _RecoveryCodeDialog({
    required this.recoveryCode,
    required this.isOffline,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(
        "Save Your Recovery Code",
        style: TextStyle(fontWeight: FontWeight.bold, color: colors.text),
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.key_rounded, color: colors.amber, size: 40),
          const SizedBox(height: 12),
          Text(
            "Store this code somewhere safe.\nYou'll need it to change your password.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: colors.subtext),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: colors.withOpacity(colors.amber, 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.withOpacity(colors.amber, 0.4)),
            ),
            child: Text(
              recoveryCode,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: colors.amber,
              ),
            ),
          ),
          if (isOffline) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.withOpacity(colors.warning, 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.withOpacity(colors.warning, 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, color: colors.warning, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Account created offline. We\'ll sync when you\'re back online.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            "This will only be shown once.",
            style: TextStyle(
              fontSize: 12,
              color: colors.error,
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => AppShell(offlineMode: isOffline)),
                (route) => false,
              );
            },
            child: const Text(
              "I've saved it — Continue",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
