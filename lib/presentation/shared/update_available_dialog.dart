import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubit/theme/theme_cubit.dart';
import '../../cubit/update/update_cubit.dart';
import '../../theme/app_theme.dart';

/// App-level "new version has arrived" dialog (Adviser contract):
///  - current version → new version;
///  - release notes (trimmed, scrollable when long);
///  - Update → `launchUrl` on the APK asset URL (fallback release page);
///  - Later → only when the status is available (forced = non-dismissible).
///
/// Reactive: builds from the [UpdateCubit]'s current state, so a newer
/// release arriving while the dialog is open updates the content live, and a
/// forced transition renders Update-only.
class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);
    return BlocBuilder<UpdateCubit, UpdateState>(
      builder: (context, state) => _buildDialog(context, state, colors),
    );
  }

  Widget _buildDialog(
    BuildContext context,
    UpdateState state,
    ThemeColors colors,
  ) {
    final remote = state.remote;
    final isForced = state.isForced;
    final current = state.currentVersion.isEmpty ? '—' : state.currentVersion;
    final next = remote?.version ?? '—';

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.dialogRadius),
      titlePadding: EdgeInsets.zero,
      buttonPadding: EdgeInsets.zero,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Icon(
              isForced
                  ? Icons.system_security_update_warning_rounded
                  : Icons.system_update_alt_rounded,
              color: AppColors.accent,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              isForced ? 'Update required' : 'New version available',
              style: AppTypography.title.copyWith(color: colors.text),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              isForced
                  ? 'You must update to continue using AgentA.'
                  : 'A new version of AgentA has arrived.',
              style: AppTypography.body.copyWith(color: colors.subtext),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '$current → $next',
              style: AppTypography.subtitle.copyWith(color: colors.text),
            ),
          ),
          const SizedBox(height: 16),
          _ReleaseNotes(notes: remote?.notes, colors: colors),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _onUpdateTap(context),
              child: const Text('Update'),
            ),
          ),
          if (!isForced) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Update → launch the APK asset URL (fallback release page) externally.
  /// Launch failure → snackbar fallback with the URL; the dialog stays open.
  /// Forced updates stay open even on a successful launch until the new
  /// version is installed; otherwise the host's post-close handler dismisses.
  Future<void> _onUpdateTap(BuildContext context) async {
    final cubit = context.read<UpdateCubit>();
    final remote = cubit.state.remote;
    final url = remote?.downloadUrl ?? remote?.releaseUrl;
    final uri = url == null || url.isEmpty ? null : Uri.tryParse(url);

    if (uri == null) {
      _showLaunchFailed(context, url);
      return;
    }

    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      launched = false;
    }
    if (!context.mounted) return;
    if (!launched) {
      _showLaunchFailed(context, url);
      return;
    }
    if (cubit.state.isForced) return;
    Navigator.pop(context);
  }

  void _showLaunchFailed(BuildContext context, String? url) {
    final message = url == null || url.isEmpty
        ? 'Could not open the update — no download link is available for this release.'
        : 'Could not open the update. Open this link in a browser: $url';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }
}

/// Release notes — trimmed, scrollable when long (capped height).
class _ReleaseNotes extends StatelessWidget {
  final String? notes;
  final ThemeColors colors;

  const _ReleaseNotes({required this.notes, required this.colors});

  @override
  Widget build(BuildContext context) {
    final text = (notes ?? '').trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: colors.input,
        borderRadius: AppRadius.bannerRadius,
        border: Border.all(color: colors.border),
      ),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: AppTypography.body.copyWith(color: colors.text),
        ),
      ),
    );
  }
}
