import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../theme/app_theme.dart';
import '../../presentation/auth/login.dart';
import 'securityservice.dart';

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  void _showRecoveryCode(BuildContext context) async {
    final colors = context.read<ThemeCubit>().state.colors;
    // H8: raw codes are shown once at creation only; only the hash is
    // stored, so there is nothing to "view" afterwards.
    if (!context.mounted) return;

    unawaited(
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: colors.card,
          title: Text("Recovery Code", style: TextStyle(color: colors.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.key_off, color: colors.subtext, size: 40),
              const SizedBox(height: 16),
              Text(
                'For your security, the raw code was shown once at sign-up and only its hash is stored. Use it on the recovery screen — it cannot be displayed again.',
                style: TextStyle(color: colors.subtext),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: colors.subtext)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final colors = context.read<ThemeCubit>().state.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('Delete Account?', style: TextStyle(color: colors.text)),
        content: Text(
          'This will permanently delete your account and all data. This action cannot be undone.',
          style: TextStyle(color: colors.subtext),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: colors.subtext)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await SecurityService.deleteAccount();
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deleted'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete account'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Security', style: TextStyle(color: colors.text)),
        backgroundColor: colors.surface,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colors.text,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showRecoveryCode(context),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.key, color: colors.amber),
                      const SizedBox(width: AppSpacing.base),
                      Expanded(
                        child: Text(
                          'View Recovery Code',
                          style: TextStyle(color: colors.text),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.subtext),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _deleteAccount(context),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: colors.error),
                      const SizedBox(width: AppSpacing.base),
                      Expanded(
                        child: Text(
                          'Delete Account',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
