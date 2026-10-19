import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../services/auth/auth_service.dart';
import '../../theme/app_theme.dart';
import '../shared/system_keyboard_text_field.dart';

enum _ResetStage { email, otp, done }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _ResetStage _stage = _ResetStage.email;
  bool _isLoading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _errorMessage;

  /// Email captured when the email form validates — the OTP stage has no
  /// email form mounted, so resend must work from this stored value.
  String? _submittedEmail;

  String get _email => (_submittedEmail ?? _emailController.text).trim();

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    // Fix: must not depend on the email form being mounted — in the OTP
    // stage only _otpFormKey is in the tree, so resend works from the
    // stored [_submittedEmail].
    final isEmailStage = _stage == _ResetStage.email;
    if (isEmailStage) {
      if (_emailFormKey.currentState == null ||
          !_emailFormKey.currentState!.validate()) {
        return;
      }
      _submittedEmail = _emailController.text.trim();
    }
    final email = _submittedEmail;
    if (email == null || email.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.sendOtpForReset(email);
      if (!mounted) return;
      if (isEmailStage) {
        setState(() {
          _stage = _ResetStage.otp;
          _isLoading = false;
        });
      } else {
        // Resend from the OTP stage: show feedback instead of a silent no-op.
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Code sent again! Check your Gmail inbox (and spam folder).',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Failed to send the code. Please check the email and try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_otpFormKey.currentState == null ||
        !_otpFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.resetPasswordWithOtp(
        email: _email,
        otp: _otpController.text.trim(),
        newPassword: _passwordController.text,
      );
      // The email-OTP verify persists a session (gotrue fires `signedIn`), so
      // AuthGate would auto-login beneath the DoneStep and "Back to Login"
      // would land on the dashboard. Sign the auto-created session out so
      // the user lands on the login screen and immediately signs in with
      // their new password. Failures are logged inside [signOutOnly]; the
      // password reset itself already succeeded.
      await AuthService.signOutOnly();
      if (!mounted) return;
      setState(() {
        _stage = _ResetStage.done;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Invalid or expired code. Check the code and try again.';
        _isLoading = false;
      });
    }
  }

  void _togglePassword() => setState(() => _showPassword = !_showPassword);

  void _toggleConfirmPassword() =>
      setState(() => _showConfirmPassword = !_showConfirmPassword);

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return SafeArea(
      child: Scaffold(
        backgroundColor: colors.base,
        appBar: AppBar(
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
            child: _stage == _ResetStage.email
                ? _EmailStep(
                    formKey: _emailFormKey,
                    emailController: _emailController,
                    isLoading: _isLoading,
                    errorMessage: _errorMessage,
                    colors: colors,
                    onSendOtp: _sendOtp,
                  )
                : _stage == _ResetStage.otp
                ? _OtpStep(
                    formKey: _otpFormKey,
                    email: _email,
                    otpController: _otpController,
                    passwordController: _passwordController,
                    confirmPasswordController: _confirmPasswordController,
                    showPassword: _showPassword,
                    showConfirmPassword: _showConfirmPassword,
                    isLoading: _isLoading,
                    errorMessage: _errorMessage,
                    colors: colors,
                    onTogglePassword: _togglePassword,
                    onToggleConfirmPassword: _toggleConfirmPassword,
                    onResendOtp: _sendOtp,
                    onResetPassword: _resetPassword,
                  )
                : _DoneStep(
                    colors: colors,
                    onBackToLogin: () => Navigator.pop(context),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Step 1: enter the email, send the OTP.
class _EmailStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final bool isLoading;
  final String? errorMessage;
  final ThemeColors colors;
  final VoidCallback onSendOtp;

  const _EmailStep({
    required this.formKey,
    required this.emailController,
    required this.isLoading,
    this.errorMessage,
    required this.colors,
    required this.onSendOtp,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const _ResetHeader(),
          const SizedBox(height: 44),
          Text(
            "Email",
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
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: AppTypography.body.copyWith(color: colors.ink),
              validator: AuthService.validateEmail,
              decoration: InputDecoration(
                hintText: "Email",
                hintStyle: AppTypography.body.copyWith(color: colors.subtext),
                prefixIcon: Icon(
                  Icons.email_outlined,
                  color: colors.subtext,
                  size: 20,
                ),
                filled: true,
                fillColor: colors.base,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (errorMessage != null)
            _ErrorBox(message: errorMessage!, colors: colors),
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
                onPressed: isLoading ? null : onSendOtp,
                child: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onAccent,
                        ),
                      )
                    : const Text("Send Code"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2: enter the emailed OTP and set the new password.
class _OtpStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final String email;
  final TextEditingController otpController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool showPassword;
  final bool showConfirmPassword;
  final bool isLoading;
  final String? errorMessage;
  final ThemeColors colors;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmPassword;
  final VoidCallback onResendOtp;
  final VoidCallback onResetPassword;

  const _OtpStep({
    required this.formKey,
    required this.email,
    required this.otpController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.showPassword,
    required this.showConfirmPassword,
    required this.isLoading,
    this.errorMessage,
    required this.colors,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onResendOtp,
    required this.onResetPassword,
  });

  String? _validateOtp(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter the 6-digit code';
    final digits = v.trim().replaceAll(' ', '');
    if (digits.length != 6 || int.tryParse(digits) == null) {
      return 'The code is 6 digits';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const _ResetHeader(),
          const SizedBox(height: 44),
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
                    Icons.mark_email_read_outlined,
                    color: AppColors.successText,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    "OTP sent! Check your Gmail inbox (and spam folder) for the 6-digit code sent to $email.",
                    style: AppTypography.label.copyWith(
                      color: colors.successText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Verification Code",
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
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autocorrect: false,
              enableSuggestions: false,
              style: AppTypography.title.copyWith(
                color: colors.ink,
                letterSpacing: 8,
              ),
              validator: _validateOtp,
              decoration: InputDecoration(
                hintText: "000000",
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
                counterText: "",
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : onResendOtp,
              child: Text(
                "Didn't get it? Resend code",
                style: AppTypography.body.copyWith(color: colors.accentInk),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "New Password",
            style: AppTypography.label.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 8),
          _PasswordField(
            controller: passwordController,
            hint: "Create a new password",
            show: showPassword,
            colors: colors,
            onToggle: onTogglePassword,
            validator: AuthService.validatePassword,
          ),
          const SizedBox(height: 20),
          Text(
            "Confirm New Password",
            style: AppTypography.label.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 8),
          _PasswordField(
            controller: confirmPasswordController,
            hint: "Re-enter your new password",
            show: showConfirmPassword,
            colors: colors,
            onToggle: onToggleConfirmPassword,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v != passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          if (errorMessage != null)
            _ErrorBox(message: errorMessage!, colors: colors),
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
                onPressed: isLoading ? null : onResetPassword,
                child: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onAccent,
                        ),
                      )
                    : const Text("Reset Password"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 3: success — back to login.
class _DoneStep extends StatelessWidget {
  final ThemeColors colors;
  final VoidCallback onBackToLogin;

  const _DoneStep({required this.colors, required this.onBackToLogin});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        const Center(
          child: Icon(
            Icons.check_circle_outline_rounded,
            color: AppColors.successText,
            size: 48,
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            "Password Updated",
            style: AppTypography.display.copyWith(color: colors.ink),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            "Sign in with your new password",
            style: AppTypography.body.copyWith(color: colors.subtext),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 44),
        Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.buttonRadius,
            boxShadow: AppShadows.raised,
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onBackToLogin,
              child: const Text("Back to Login"),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResetHeader extends StatelessWidget {
  const _ResetHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_reset_rounded,
              color: AppColors.accent,
              size: 24,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              "Reset Password",
              style: AppTypography.display.copyWith(color: colors.ink),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            "We'll email you a 6-digit code to set a new password",
            style: AppTypography.body.copyWith(color: colors.subtext),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final ThemeColors colors;

  const _ErrorBox({required this.message, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              message,
              style: AppTypography.label.copyWith(color: colors.errorText),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool show;
  final ThemeColors colors;
  final VoidCallback onToggle;
  final String? Function(String?)? validator;

  const _PasswordField({
    required this.controller,
    required this.hint,
    required this.show,
    required this.colors,
    required this.onToggle,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
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
        autofillHints: const [AutofillHints.newPassword],
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
