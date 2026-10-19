import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubit/theme/theme_cubit.dart';
import '../../cubit/update/update_cubit.dart';
import '../../services/update/install_failure_reason.dart';
import '../../theme/app_theme.dart';

/// App-level update dialog (Adviser contract; cycle-28 P5):
///  - available/forced → release info + [Update] / [Later];
///  - [Update] starts the IN-APP flow (contract §4: download → verify →
///    PackageInstaller) and the dialog morphs through downloading →
///    readyToInstall → installing → installed, with per-reason failure copy;
///  - the browser survives ONLY as the manual fallback (signatureMismatch /
///    a release without an in-app download URL) — the sanctioned exception,
///    never the default path;
///  - Later → only when available (forced = non-dismissible). The host's
///    post-close dismissal is a no-op while the flow is active (§4).
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
    switch (state.status) {
      case UpdateStatus.downloading:
        return _downloadingState(context, state, colors);
      case UpdateStatus.readyToInstall:
        return _readyToInstallState(context, colors);
      case UpdateStatus.installing:
        return _installingState(context, colors);
      case UpdateStatus.installed:
        return _installedState(context, colors);
      case UpdateStatus.installFailed:
        return _installFailedState(context, state, colors);
      case UpdateStatus.checking:
        return _shell(
          context,
          colors,
          icon: Icons.system_update_alt_rounded,
          iconColor: AppColors.accent,
          title: 'Checking for updates…',
          actions: const [],
        );
      case UpdateStatus.idle:
      case UpdateStatus.available:
      case UpdateStatus.forced:
        return _availableState(context, state, colors);
    }
  }

  // ---------------------------------------------------------------------------
  // State: available / forced — release info + Update / Later.
  // ---------------------------------------------------------------------------

  Widget _availableState(
    BuildContext context,
    UpdateState state,
    ThemeColors colors,
  ) {
    final remote = state.remote;
    final isForced = state.isForced;
    final current = state.currentVersion.isEmpty ? '—' : state.currentVersion;
    final next = remote?.version ?? '—';
    // In-app flow only when the release carries a downloadable APK; otherwise
    // Update falls back to the browser (the sanctioned manual exception).
    final canDownloadInApp = (remote?.downloadUrl ?? '').isNotEmpty;

    return _shell(
      context,
      colors,
      icon: isForced
          ? Icons.system_security_update_warning_rounded
          : Icons.system_update_alt_rounded,
      iconColor: AppColors.accent,
      title: isForced ? 'Update required' : 'New version available',
      body: isForced
          ? 'You must update to continue using AgentA.'
          : 'A new version of AgentA has arrived.',
      detail: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Text(
              '$current → $next',
              style: AppTypography.subtitle.copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 16),
          _ReleaseNotes(notes: remote?.notes, colors: colors),
          const SizedBox(height: 24),
          _primaryButton(
            Text(canDownloadInApp ? 'Update' : 'Download manually'),
            onPressed: canDownloadInApp
                ? () => context.read<UpdateCubit>().downloadUpdate()
                : () => _launchManualDownload(context, state),
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

  // ---------------------------------------------------------------------------
  // State: downloading — progress on the inset track + Cancel.
  // ---------------------------------------------------------------------------

  Widget _downloadingState(
    BuildContext context,
    UpdateState state,
    ThemeColors colors,
  ) {
    return _shell(
      context,
      colors,
      icon: Icons.system_update_alt_rounded,
      iconColor: AppColors.accent,
      title: 'Updating AgentA',
      detail: _progressDetail(state, colors),
      actions: [
        Center(
          child: TextButton(
            onPressed: () => context.read<UpdateCubit>().cancelDownload(),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  /// Progress = `accent` bar on the inset track (spec §5), percentage in the
  /// status copy (§1.7).
  Widget _progressDetail(UpdateState state, ThemeColors colors) {
    final percent = (state.downloadProgress * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            boxShadow: AppShadows.well,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            child: LinearProgressIndicator(
              value: state.downloadProgress,
              minHeight: 10,
              backgroundColor: colors.base,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Downloading update… $percent%',
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.subtext),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // State: readyToInstall — verified APK on hand; Install now.
  // ---------------------------------------------------------------------------

  Widget _readyToInstallState(BuildContext context, ThemeColors colors) {
    return _shell(
      context,
      colors,
      icon: Icons.system_update_alt_rounded,
      iconColor: AppColors.accent,
      title: 'Ready to install',
      body: 'The update has been downloaded and verified.',
      actions: [
        _primaryButton(
          const Text('Install now'),
          onPressed: () => context.read<UpdateCubit>().installUpdate(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // State: installing — session committed; the system confirmation governs.
  // STATUS_PENDING_USER_ACTION is not a failure (contract §4): stay here.
  // ---------------------------------------------------------------------------

  Widget _installingState(BuildContext context, ThemeColors colors) {
    return _shell(
      context,
      colors,
      icon: Icons.system_update_alt_rounded,
      iconColor: AppColors.accent,
      title: 'Installing…',
      body: 'Confirm the install in the system dialog if prompted.',
      detail: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      actions: const [],
    );
  }

  // ---------------------------------------------------------------------------
  // State: installed — terminal success; the restart finishes the update
  // (installing over the running app kills its process, contract §4).
  // ---------------------------------------------------------------------------

  Widget _installedState(BuildContext context, ThemeColors colors) {
    return _shell(
      context,
      colors,
      icon: Icons.check_circle_rounded,
      iconColor: AppColors.successText,
      title: 'Update installed',
      body: 'Restart the app to finish.',
      actions: [
        _primaryButton(
          const Text('Done'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // State: installFailed — per-reason copy + per-reason action.
  // ---------------------------------------------------------------------------

  Widget _installFailedState(
    BuildContext context,
    UpdateState state,
    ThemeColors colors,
  ) {
    final reason = state.installFailureReason ?? InstallFailureReason.unknown;
    switch (reason) {
      case InstallFailureReason.userCancelled:
        return _shell(
          context,
          colors,
          icon: Icons.error_outline,
          iconColor: AppColors.errorText,
          title: 'Installation cancelled',
          body:
              'The update was not installed. You can try again whenever you like.',
          actions: [
            _primaryButton(
              const Text('Try again'),
              onPressed: () => context.read<UpdateCubit>().retry(),
            ),
          ],
        );
      case InstallFailureReason.signatureMismatch:
        return _shell(
          context,
          colors,
          icon: Icons.error_outline,
          iconColor: AppColors.errorText,
          title: 'Update cannot be installed',
          body:
              'Update cannot be installed (signature mismatch). Please download manually.',
          actions: [
            _primaryButton(
              const Text('Download manually'),
              onPressed: () => _launchManualDownload(context, state),
            ),
          ],
        );
      case InstallFailureReason.permissionDenied:
        return _shell(
          context,
          colors,
          icon: Icons.error_outline,
          iconColor: AppColors.errorText,
          title: 'Permission needed',
          body:
              'AgentA needs the "install unknown apps" permission to install updates. '
              'Open the settings, allow it for AgentA, then try again.',
          actions: [
            _primaryButton(
              const Text('Open settings'),
              onPressed: () =>
                  context.read<UpdateCubit>().openInstallPermissionSettings(),
            ),
            Center(
              child: TextButton(
                onPressed: () => context.read<UpdateCubit>().retry(),
                child: const Text('Try again'),
              ),
            ),
          ],
        );
      case InstallFailureReason.unknown:
      case InstallFailureReason.download:
      case InstallFailureReason.network:
      case InstallFailureReason.timeout:
      case InstallFailureReason.storage:
      case InstallFailureReason.sizeMismatch:
      case InstallFailureReason.checksumMismatch:
      case InstallFailureReason.invalidPackage:
        return _shell(
          context,
          colors,
          icon: Icons.error_outline,
          iconColor: AppColors.errorText,
          title: 'Installation failed',
          body: 'Installation failed. Try again.',
          actions: [
            _primaryButton(
              const Text('Try again'),
              onPressed: () => context.read<UpdateCubit>().retry(),
            ),
          ],
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Shell + shared pieces.
  // ---------------------------------------------------------------------------

  Widget _shell(
    BuildContext context,
    ThemeColors colors, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String body = '',
    Widget? detail,
    List<Widget> actions = const [],
  }) {
    return AlertDialog(
      backgroundColor: colors.base,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.dialogRadius),
      titlePadding: EdgeInsets.zero,
      buttonPadding: EdgeInsets.zero,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Icon(icon, color: iconColor, size: 28)),
          const SizedBox(height: 16),
          Center(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.title.copyWith(color: AppColors.ink),
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: AppColors.subtext),
              ),
            ),
          ],
          if (detail != null) ...[const SizedBox(height: 16), detail],
          ...actions,
        ],
      ),
    );
  }

  /// Primary button per §5 — raised (the pressed inset is the §5 state; the
  /// Material ripple carries the transient press).
  Widget _primaryButton(Widget child, {required VoidCallback? onPressed}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.buttonRadius,
        boxShadow: AppShadows.raised,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(onPressed: onPressed, child: child),
      ),
    );
  }

  /// The sanctioned browser exception (signatureMismatch / no in-app
  /// download URL): opens the release page for a manual download. Never the
  /// default path.
  Future<void> _launchManualDownload(
    BuildContext context,
    UpdateState state,
  ) async {
    final url = state.remote?.downloadUrl ?? state.remote?.releaseUrl;
    final uri = url == null || url.isEmpty ? null : Uri.tryParse(url);
    // H3: https-only launch (defense-in-depth) — a non-https or unparseable
    // target never opens the browser; the failure snackbar explains instead.
    var launched = false;
    if (uri != null && uri.scheme == 'https') {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }
    if (!context.mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the download page.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    if (state.isForced) return;
    Navigator.pop(context);
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
        color: colors.base,
        borderRadius: AppRadius.bannerRadius,
        boxShadow: AppShadows.well,
      ),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: AppTypography.body.copyWith(color: colors.ink),
        ),
      ),
    );
  }
}
