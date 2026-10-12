import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../cubit/connectivity/connectivity_cubit.dart';
import '../../services/auth/auth_service.dart';
import '../shared/system_keyboard_text_field.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
    });

    try {
      final user = AuthService.currentUser;
      if (user == null) throw Exception('Not logged in');
      if (user.email == null) throw Exception('Email not available');

      await AuthService.reauthenticate(
        user.email!,
        _currentPasswordController.text,
      );
      await AuthService.updatePassword(_newPasswordController.text);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password changed!'),
            backgroundColor: Colors.amber,
          ),
        );
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      String errorMsg;
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('wrong password') ||
          errorString.contains('invalid-credential')) {
        errorMsg = 'Current password is incorrect';
      } else if (errorString.contains('no user') ||
          errorString.contains('not logged in')) {
        errorMsg = 'Session expired. Please log in again.';
      } else if (errorString.contains('network')) {
        errorMsg = 'Network error. Check your connection.';
      } else {
        errorMsg = 'Failed. Check current password.';
      }
      setState(() => _errorMessage = errorMsg);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Change Password', style: TextStyle(color: colors.text)),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colors.text,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Password',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 8),
                SystemKeyboardTextFormField(
                  controller: _currentPasswordController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(color: colors.text),
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    labelStyle: TextStyle(color: colors.subtext),
                    prefixIcon: Icon(Icons.lock, color: colors.amber),
                    filled: true,
                    fillColor: colors.input,
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 24),
                Text(
                  'New Password',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 8),
                SystemKeyboardTextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(color: colors.text),
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    labelStyle: TextStyle(color: colors.subtext),
                    prefixIcon: Icon(Icons.lock_outline, color: colors.amber),
                    filled: true,
                    fillColor: colors.input,
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 6) return 'At least 6 characters';
                    return null;
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _isSaving ? null : _submit,
                    child: SizedBox(
                      height: 22,
                      child: Center(
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Change Password'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
