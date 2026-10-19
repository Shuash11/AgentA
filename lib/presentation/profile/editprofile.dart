import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../services/auth/auth_service.dart';
import '../../repositories/user_repository.dart';
import '../../theme/app_theme.dart';
import '../shared/system_keyboard_text_field.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = AuthService.currentUser;
    if (user != null) {
      final meta = user.userMetadata;
      final displayName =
          (meta == null
                  ? ''
                  : (meta['display_name'] ??
                        meta['full_name'] ??
                        meta['name'] ??
                        ''))
              as String;
      final parts = displayName.split(' ');
      _firstNameController.text = parts.isNotEmpty ? parts.first : '';
      _lastNameController.text = parts.length > 1 ? parts.last : '';
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final newDisplayName =
          '${_firstNameController.text} ${_lastNameController.text}';
      final uid = AuthService.currentUser?.id;
      if (uid == null) {
        throw Exception('No user logged in');
      }
      await UserRepository.updateDisplayName(uid, newDisplayName);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile saved')));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EditProfile] save failed: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your profile. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return Scaffold(
      backgroundColor: colors.base,
      appBar: AppBar(
        title: Text('Edit Profile', style: TextStyle(color: colors.ink)),
        backgroundColor: colors.base,
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
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Center(
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.pressed,
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: colors.base,
                      child: Text(
                        _firstNameController.text.isNotEmpty
                            ? _firstNameController.text[0].toUpperCase()
                            : 'U',
                        style: AppTypography.display.copyWith(
                          color: colors.accentInk,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.inputRadius,
                    boxShadow: AppShadows.well,
                  ),
                  child: SystemKeyboardTextFormField(
                    controller: _firstNameController,
                    textCapitalization: TextCapitalization.words,
                    style: AppTypography.body.copyWith(color: colors.ink),
                    decoration: InputDecoration(
                      labelText: 'First Name',
                      prefixIcon: Icon(
                        Icons.person,
                        color: colors.subtext,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: colors.base,
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.inputRadius,
                    boxShadow: AppShadows.well,
                  ),
                  child: SystemKeyboardTextFormField(
                    controller: _lastNameController,
                    textCapitalization: TextCapitalization.words,
                    style: AppTypography.body.copyWith(color: colors.ink),
                    decoration: InputDecoration(
                      labelText: 'Last Name',
                      prefixIcon: Icon(
                        Icons.person,
                        color: colors.subtext,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: colors.base,
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.buttonRadius,
                    boxShadow: AppShadows.raised,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onAccent,
                              ),
                            )
                          : const Text('Save'),
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
