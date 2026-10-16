import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../theme/app_theme.dart';
import '../../services/auth/auth_service.dart';
import '../../repositories/user_repository.dart';
import '../../presentation/auth/login.dart';
import '../shared/bottomnavbar.dart';
import 'editprofile.dart';
import 'confirmation.dart';
import 'securitypage.dart';

class ProfilePage extends StatefulWidget {
  final bool showBottomNav;

  const ProfilePage({super.key, this.showBottomNav = true});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _displayName;
  String? _email;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    try {
      final user = AuthService.currentUser;
      if (user != null) {
        final meta = user.userMetadata;
        _displayName = meta == null
            ? null
            : (meta['display_name'] ?? meta['full_name'] ?? meta['name'])
                  as String?;
        _email = user.email;

        if (_displayName == null || _displayName!.isEmpty) {
          final profile = await UserRepository.getUserProfile(user.id);
          if (profile != null) {
            _displayName = profile.displayName;
            try {
              await AuthService.updateDisplayName(_displayName!);
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[Profile] display-name backfill failed: $e');
              }
            }
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: const Text('Profile'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: colors.accentContainer,
                    child: Text(
                      _displayName?.isNotEmpty == true
                          ? _displayName![0].toUpperCase()
                          : 'U',
                      style: AppTypography.display.copyWith(
                        color: colors.onAccentContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _displayName ?? 'User',
                    style: AppTypography.title.copyWith(color: colors.text),
                  ),
                  Text(_email ?? '', style: TextStyle(color: colors.subtext)),
                  const SizedBox(height: 32),
                  _tile(
                    Icons.person,
                    'Edit Profile',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EditProfilePage(),
                      ),
                    ),
                    colors,
                  ),
                  const SizedBox(height: 12),
                  _tile(
                    Icons.lock,
                    'Change Password',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RecoveryCodePage(),
                      ),
                    ),
                    colors,
                  ),
                  const SizedBox(height: 12),
                  _tile(
                    Icons.security,
                    'Security',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SecurityPage()),
                    ),
                    colors,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        side: BorderSide(color: colors.error),
                      ),
                      onPressed: () async {
                        final colors = context.read<ThemeCubit>().state.colors;
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: colors.card,
                            title: Text(
                              'Sign Out?',
                              style: AppTypography.title.copyWith(
                                color: colors.text,
                              ),
                            ),
                            content: Text(
                              'Any unsynced data will be preserved and uploaded when you sign back in.',
                              style: AppTypography.body.copyWith(
                                color: colors.subtext,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(
                                  'Sign Out',
                                  style: TextStyle(color: colors.error),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;

                        await AuthService.logout();
                        if (context.mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                            (route) => false,
                          );
                        }
                      },
                      child: const Text('Sign Out'),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: widget.showBottomNav
          ? const BottomNav1(selectedIndex: 1)
          : null,
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    VoidCallback onTap,
    ThemeColors colors,
  ) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.tileRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: AppRadius.tileRadius,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: colors.subtext),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.subtitle.copyWith(color: colors.text),
                ),
              ),
              Icon(Icons.chevron_right, color: colors.subtext),
            ],
          ),
        ),
      ),
    );
  }
}
