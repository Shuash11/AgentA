import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/theme/theme_cubit.dart';
import 'change_pass_page.dart';
import '../../repositories/user_repository.dart';
import '../../theme/app_theme.dart';
import '../shared/system_keyboard_text_field.dart';

class RecoveryCodeService {
  static Future<bool> verifyCode(String enteredCode) async {
    return await UserRepository.verifyRecoveryCode(enteredCode);
  }
}

class RecoveryCodePage extends StatefulWidget {
  const RecoveryCodePage({super.key});

  @override
  State<RecoveryCodePage> createState() => _RecoveryCodePageState();
}

class _RecoveryCodePageState extends State<RecoveryCodePage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _verify() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final isValid = await RecoveryCodeService.verifyCode(_codeController.text);
    setState(() => _isVerifying = false);

    if (isValid && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
      );
    } else if (mounted) {
      setState(() {
        _errorMessage = 'Incorrect recovery code';
        _codeController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Recovery Code', style: TextStyle(color: colors.text)),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colors.text,
            size: 20,
          ),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.key_rounded, color: AppColors.accent, size: 48),
              const SizedBox(height: 24),
              Text(
                'Enter Recovery Code',
                style: AppTypography.title.copyWith(color: colors.text),
              ),
              const SizedBox(height: 32),
              SystemKeyboardTextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                style: AppTypography.body.copyWith(color: colors.text),
                decoration: InputDecoration(
                  labelText: 'Recovery Code (e.g., ABC-123)',
                  prefixIcon: Icon(Icons.key, color: colors.subtext, size: 20),
                  filled: true,
                  fillColor: colors.input,
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: AppTypography.label.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _verify,
                  child: _isVerifying
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onAccent,
                          ),
                        )
                      : const Text('Verify'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
