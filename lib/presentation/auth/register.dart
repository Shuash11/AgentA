import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../core/utils/connectivity_service.dart';
import '../../services/auth/auth_service.dart';
import '../../services/auth/password_hasher.dart';
import '../../services/auth/recovery_code_hasher.dart';
import '../../services/auth/session_manager.dart';
import '../../repositories/user_repository.dart';
import '../../data/local/local_user_dao.dart';
import '../../presentation/shared/app_shell.dart';
import '../../theme/app_theme.dart';
import '../shared/system_keyboard_text_field.dart';
import 'dart:math';
import 'package:uuid/uuid.dart';

/// M16: trims and collapses whitespace so display names are never stored
/// with leading/trailing/double spaces. Shared by register + profile edits.
String normalizeDisplayName(String raw) {
  return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
}

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
    final code = List.generate(
      6,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }

  void _register() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final displayName = normalizeDisplayName(
      '${_firstNameController.text} ${_lastNameController.text}',
    );
    final recoveryCode = _generateRecoveryCode();
    // Normalize once: Supabase lowercases addresses, and the local row must
    // match on offline sign-in regardless of how the user typed it.
    final email = AuthService.normalizeEmail(_emailController.text);
    final password = _passwordController.text;

    final localUserDao = LocalUserDao();

    // Bug 3: check connectivity before the online attempt — when the device
    // is offline, go straight to savePendingSignup instead of letting the
    // request fail with AuthRetryableFetchException.
    final deviceOnline = await ConnectivityService.instance.isOnline();

    bool isOnline = false;
    String? onlineUid;
    bool emailConfirmationPending = false;

    if (!deviceOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You're offline. Creating account offline..."),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      try {
        final cred = await AuthService.register(email, password, displayName);
        onlineUid = cred.uid;
        try {
          await UserRepository.createUserProfile(
            cred.uid,
            email,
            displayName,
            recoveryCode,
          );
          isOnline = true;
        } catch (_) {
          // signUp succeeded — only the profile write failed.
          // Keep the dialog states mutually consistent: the account is
          // online (no offline warning), only the email note is shown.
          emailConfirmationPending = true;
          isOnline = true;
        }
      } on AuthException catch (e) {
        final isRetryable = AuthService.isRetryable(e);
        if (!isRetryable) {
          setState(() {
            _isLoading = false;
            _errorMessage = _friendlyAuthError(e.message);
          });
          return;
        }

        // Retryable (network/server) — fall through to savePendingSignup.
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
              content: Text(
                'Online registration failed. Registering offline...',
              ),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }

    final localId = onlineUid ?? const Uuid().v4();
    await localUserDao.savePendingSignup(
      localId: localId,
      email: email,
      password: PasswordHasher.hashPassword(password),
      displayName: displayName,
      recoveryCode: RecoveryCodeHasher.hash(recoveryCode),
      isSynced: isOnline,
      provider: 'password',
    );
    await SessionManager.saveSession(
      uid: localId,
      email: email,
      provider: 'password',
    );

    setState(() => _isLoading = false);

    if (mounted) {
      await _showRecoveryCodeDialog(
        recoveryCode,
        isOffline: !isOnline,
        confirmEmail: emailConfirmationPending,
      );
    }
  }

  String _friendlyAuthError(String message) {
    if (message.contains('already registered') ||
        message.contains('already exists') ||
        message.contains('already in use')) {
      return 'This email is already registered. Please sign in.';
    }
    if (message.contains('rate limit') ||
        message.contains('429') ||
        message.contains('too many') ||
        message.contains('over_email_send_rate_limit')) {
      return 'Too many attempts. Email limit reached — try again in an hour.';
    }
    if (message.contains('email_address_invalid') ||
        message.contains('invalid email') ||
        message.contains('invalid-email')) {
      return 'The email address is not valid.';
    }
    if (message.contains('password')) {
      return 'Password is too weak. Use at least 8 characters with letters + numbers.';
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

  Future<void> _showRecoveryCodeDialog(
    String recoveryCode, {
    bool isOffline = false,
    bool confirmEmail = false,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecoveryCodeDialog(
        recoveryCode: recoveryCode,
        isOffline: isOffline,
        confirmEmail: confirmEmail,
        colors: _colors,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _colors = context.select((ThemeCubit c) => c.state.colors);

    return SafeArea(
      child: Scaffold(
        backgroundColor: _colors.base,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 100),
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
            child: Text(
              "AgentA",
              style: AppTypography.display.copyWith(color: colors.ink),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              "Fill in your details to get started",
              style: AppTypography.subtitle.copyWith(color: colors.subtext),
            ),
          ),
          const SizedBox(height: 36),
          _fieldLabel("Full Name", colors.ink),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: firstNameController,
                  hint: "First name",
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: lastNameController,
                  hint: "Last name",
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _fieldLabel("Email", colors.ink),
          const SizedBox(height: 8),
          _buildTextField(
            controller: emailController,
            hint: "Enter your email",
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: AuthService.validateEmail,
          ),
          const SizedBox(height: 20),
          _fieldLabel("Password", colors.ink),
          const SizedBox(height: 8),
          _buildPasswordField(
            controller: passwordController,
            hint: "Create a password",
            show: showPassword,
            onToggle: onTogglePassword,
            validator: AuthService.validatePassword,
          ),
          const SizedBox(height: 20),
          _fieldLabel("Confirm Password", colors.ink),
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
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: colors.base,
                borderRadius: AppRadius.bannerRadius,
                boxShadow: AppShadows.raised,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.error_outline,
                      color: AppColors.errorText,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: AppTypography.label.copyWith(
                        color: colors.errorText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.buttonRadius,
              boxShadow: AppShadows.raised,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading ? null : onRegister,
                child: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onAccent,
                        ),
                      )
                    : const Text("Create Account"),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Divider(color: colors.base, thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  "or",
                  style: AppTypography.labelSm.copyWith(color: colors.subtext),
                ),
              ),
              Expanded(child: Divider(color: colors.base, thickness: 1)),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: InkWell(
              onTap: onSignIn,
              borderRadius: AppRadius.chipRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 14,
                ),
                child: RichText(
                  text: TextSpan(
                    text: "Already have an account? ",
                    style: AppTypography.body.copyWith(color: colors.subtext),
                    children: [
                      TextSpan(
                        text: "Sign In",
                        style: AppTypography.body.copyWith(
                          color: colors.accentInk,
                          fontWeight: FontWeight.w600,
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
      style: AppTypography.label.copyWith(
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.inputRadius,
        boxShadow: AppShadows.well,
      ),
      child: SystemKeyboardTextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        style: AppTypography.body.copyWith(color: colors.ink),
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTypography.body.copyWith(color: colors.subtext),
          prefixIcon: Icon(icon, color: colors.subtext, size: 20),
          filled: true,
          fillColor: colors.base,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.inputRadius,
        boxShadow: AppShadows.well,
      ),
      child: SystemKeyboardTextFormField(
        controller: controller,
        obscureText: !show,
        autocorrect: false,
        enableSuggestions: false,
        style: AppTypography.body.copyWith(color: colors.ink),
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTypography.body.copyWith(color: colors.subtext),
          prefixIcon: Icon(Icons.lock_outline, color: colors.subtext, size: 20),
          filled: true,
          fillColor: colors.base,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: colors.subtext,
              size: 20,
            ),
            tooltip: show ? 'Hide password' : 'Show password',
            onPressed: onToggle,
          ),
        ),
      ),
    );
  }
}

class _RecoveryCodeDialog extends StatelessWidget {
  final String recoveryCode;
  final bool isOffline;
  final bool confirmEmail;
  final ThemeColors colors;

  const _RecoveryCodeDialog({
    required this.recoveryCode,
    required this.isOffline,
    this.confirmEmail = false,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: colors.base,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.dialogRadius),
      title: Text(
        "Save Your Recovery Code",
        style: AppTypography.title.copyWith(color: colors.ink),
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.key_rounded, color: AppColors.accent, size: 28),
          const SizedBox(height: AppSpacing.md),
          Text(
            "Store this code somewhere safe.\nYou'll need it to change your password.",
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: colors.subtext),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: colors.base,
              borderRadius: AppRadius.bannerRadius,
              boxShadow: AppShadows.well,
            ),
            child: Text(
              recoveryCode,
              style: AppTypography.title.copyWith(
                fontFamily: 'monospace',
                fontSize: 24,
                letterSpacing: 4,
                color: colors.accentInk,
              ),
            ),
          ),
          if (isOffline) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.base,
                borderRadius: AppRadius.bannerRadius,
                boxShadow: AppShadows.raised,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.cloud_off,
                      color: AppColors.warningText,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Account created offline. We\'ll sync when you\'re back online.',
                      style: AppTypography.label.copyWith(color: colors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (confirmEmail) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.base,
                borderRadius: AppRadius.bannerRadius,
                boxShadow: AppShadows.raised,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.mark_email_read_outlined,
                      color: AppColors.accentInk,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Check your email for a confirmation link, then sign in.',
                      style: AppTypography.label.copyWith(
                        color: colors.accentInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            "This will only be shown once.",
            style: AppTypography.labelSm.copyWith(color: colors.errorText),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => AppShell(offlineMode: isOffline),
                ),
                (route) => false,
              );
            },
            child: const Text("I've saved it — Continue"),
          ),
        ),
      ],
    );
  }
}
