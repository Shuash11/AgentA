import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubit/theme/theme_cubit.dart';
import '../../cubit/update/update_cubit.dart';
import '../../services/auth/auth_service.dart';
import '../../services/update/install_failure_reason.dart';
import '../../services/update/version_check_service.dart';
import '../../repositories/user_repository.dart';
import '../../theme/app_theme.dart';
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

  // Cycle-27 P4: manual "Check for updates" row. Only USER-initiated checks
  // render here — automatic paths stay silent (contract §2). The outcome
  // comes from VersionCheckService.checkNow() (the contract's outcome
  // source); the dialog flow (resultStream → UpdateCubit → host) is
  // untouched and re-shows the dialog on `available` automatically.
  bool _checkingUpdates = false;
  UpdateCheckOutcome? _updateOutcome;

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

  /// User-initiated check (plan ruling 4). Double taps are prevented by the
  /// [_checkingUpdates] guard; the row is disabled while the check runs.
  Future<void> _checkForUpdates() async {
    if (_checkingUpdates) return;
    setState(() {
      _checkingUpdates = true;
      _updateOutcome = null;
    });
    final outcome = await VersionCheckService.instance.checkNow();
    if (!mounted) return;
    setState(() {
      _checkingUpdates = false;
      _updateOutcome = outcome;
    });
  }

  /// Per-outcome content for the row (plan ruling 4): checking /
  /// up-to-date (vX) / available → dialog / failed(reason, retryAt?) + Retry /
  /// skipped(nonRelease) — extended in cycle-28 P5 with the install-flow
  /// states (contract §4): downloading/readyToInstall/installing/installed/
  /// installFailed take priority over the check outcome while present. All
  /// states carry text (never color-only, §7.4-5).
  ({String? subtitle, Color? subtitleColor, Widget? action}) _updateRowContent(
    BuildContext context,
    ThemeColors colors,
    UpdateState updateState,
  ) {
    if (_checkingUpdates) {
      return (
        subtitle: 'Checking for updates…',
        subtitleColor: null,
        action: null,
      );
    }
    switch (updateState.status) {
      case UpdateStatus.downloading:
        final percent = (updateState.downloadProgress * 100).round();
        return (
          subtitle: 'Downloading update… $percent%',
          subtitleColor: null,
          action: null,
        );
      case UpdateStatus.readyToInstall:
        return (
          subtitle: 'Ready to install.',
          subtitleColor: null,
          action: TextButton(
            onPressed: () => context.read<UpdateCubit>().installUpdate(),
            child: Text(
              'Install now',
              style: AppTypography.body.copyWith(color: colors.accentInk),
            ),
          ),
        );
      case UpdateStatus.installing:
        return (
          subtitle:
              'Installing… Confirm the install in the system dialog if prompted.',
          subtitleColor: null,
          action: null,
        );
      case UpdateStatus.installed:
        return (
          subtitle: 'Update installed. Restart the app to finish.',
          subtitleColor: null,
          action: null,
        );
      case UpdateStatus.installFailed:
        return _installFailedRowContent(context, colors, updateState);
      case UpdateStatus.idle:
      case UpdateStatus.checking:
      case UpdateStatus.available:
      case UpdateStatus.forced:
        break;
    }
    return switch (_updateOutcome) {
      null => (subtitle: null, subtitleColor: null, action: null),
      UpdateCheckCompleted(:final result) => _completedContent(result),
      UpdateCheckFailed(:final reason, :final retryAt) => _failedContent(
        colors,
        reason,
        retryAt,
      ),
      UpdateCheckSkipped(:final reason) => (
        subtitle: switch (reason) {
          UpdateSkipReason.nonRelease =>
            "Update check skipped — this build doesn't check for updates.",
          UpdateSkipReason.versionUnknown =>
            'Update check skipped — the installed version could not be determined.',
          UpdateSkipReason.throttled =>
            'Update check skipped — try again in a few minutes.',
        },
        subtitleColor: null,
        action: null,
      ),
    };
  }

  /// Install-flow failure copy per reason (contract §4) + the reason's
  /// action: retry, the permission settings route, or the sanctioned manual
  /// browser download (signatureMismatch).
  ({String? subtitle, Color? subtitleColor, Widget? action})
  _installFailedRowContent(
    BuildContext context,
    ThemeColors colors,
    UpdateState updateState,
  ) {
    final reason =
        updateState.installFailureReason ?? InstallFailureReason.unknown;
    switch (reason) {
      case InstallFailureReason.permissionDenied:
        return (
          subtitle: 'AgentA needs permission to install updates.',
          subtitleColor: colors.errorText,
          action: TextButton(
            onPressed: () =>
                context.read<UpdateCubit>().openInstallPermissionSettings(),
            child: Text(
              'Open settings',
              style: AppTypography.body.copyWith(color: colors.accentInk),
            ),
          ),
        );
      case InstallFailureReason.signatureMismatch:
        return (
          subtitle:
              'Update cannot be installed (signature mismatch). Please download manually.',
          subtitleColor: colors.errorText,
          action: TextButton(
            onPressed: () => _launchManualDownload(context, updateState),
            child: Text(
              'Download manually',
              style: AppTypography.body.copyWith(color: colors.accentInk),
            ),
          ),
        );
      case InstallFailureReason.userCancelled:
        return (
          subtitle: 'Installation cancelled.',
          subtitleColor: colors.errorText,
          action: TextButton(
            onPressed: () => context.read<UpdateCubit>().retry(),
            child: Text(
              'Try again',
              style: AppTypography.body.copyWith(color: colors.accentInk),
            ),
          ),
        );
      case InstallFailureReason.unknown:
      case InstallFailureReason.download:
      case InstallFailureReason.network:
      case InstallFailureReason.timeout:
      case InstallFailureReason.storage:
      case InstallFailureReason.sizeMismatch:
      case InstallFailureReason.checksumMismatch:
      case InstallFailureReason.invalidPackage:
        return (
          subtitle: 'Installation failed. Try again.',
          subtitleColor: colors.errorText,
          action: TextButton(
            onPressed: () => context.read<UpdateCubit>().retry(),
            child: Text(
              'Retry',
              style: AppTypography.body.copyWith(color: colors.accentInk),
            ),
          ),
        );
    }
  }

  /// Whether the install-flow UI owns the row right now — a check tap would
  /// clobber the flow state (the P4 `checkNow` has no flow guard), so the
  /// row disables checking while visible.
  bool _installFlowShowing(UpdateState updateState) =>
      updateState.isFlowActive ||
      updateState.status == UpdateStatus.installed ||
      updateState.status == UpdateStatus.installFailed;

  /// The sanctioned browser exception (signatureMismatch): opens the release
  /// page for a manual download. Never the default path.
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
    }
  }

  /// A fresh decision: the host auto-shows the dialog on `available`/`forced`
  /// (dismissals suppress only the exact version); the row states the fact.
  ({String? subtitle, Color? subtitleColor, Widget? action}) _completedContent(
    UpdateCheckResult result,
  ) {
    return switch (result.level) {
      UpdateLevel.available || UpdateLevel.forced => (
        subtitle: switch (result.remote?.version) {
          null => 'A new version of AgentA is available.',
          final version => 'AgentA v$version is available.',
        },
        subtitleColor: null,
        action: null,
      ),
      UpdateLevel.none => (
        subtitle: switch (result.currentVersion) {
          null || '' => "You're on the latest version.",
          final current => "You're on the latest version (v$current)",
        },
        subtitleColor: null,
        action: null,
      ),
    };
  }

  /// Failure text per reason + the Retry action (re-runs the check and
  /// clears the failure). The rate-limit deadline renders as local HH:mm.
  ({String? subtitle, Color? subtitleColor, Widget? action}) _failedContent(
    ThemeColors colors,
    UpdateFailureReason reason,
    DateTime? retryAt,
  ) {
    final text = switch (reason) {
      UpdateFailureReason.noRelease =>
        'Update check failed — no release found on the server.',
      UpdateFailureReason.offline =>
        'Update check failed — offline. Check your connection.',
      UpdateFailureReason.timeout =>
        'Update check failed — timed out. Try again.',
      UpdateFailureReason.rateLimited => switch (retryAt) {
        null => 'Update check rate-limited. Try again later.',
        final deadline =>
          'Update check rate-limited. Retry after '
              '${deadline.hour.toString().padLeft(2, '0')}:'
              '${deadline.minute.toString().padLeft(2, '0')}',
      },
      // The outcome carries no HTTP status (contract §2) — the engine logs it.
      UpdateFailureReason.unexpected =>
        'Update check failed — server error. Try again.',
    };
    return (
      subtitle: text,
      subtitleColor: colors.errorText,
      action: TextButton(
        onPressed: _checkForUpdates,
        child: Text(
          'Retry',
          style: AppTypography.body.copyWith(color: colors.accentInk),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return Scaffold(
      backgroundColor: colors.base,
      appBar: AppBar(
        backgroundColor: colors.base,
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
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.pressed,
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: colors.base,
                      child: Text(
                        _displayName?.isNotEmpty == true
                            ? _displayName![0].toUpperCase()
                            : 'U',
                        style: AppTypography.display.copyWith(
                          color: colors.accentInk,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _displayName ?? 'User',
                    style: AppTypography.title.copyWith(color: colors.ink),
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
                  const SizedBox(height: 12),
                  BlocBuilder<UpdateCubit, UpdateState>(
                    builder: (context, updateState) {
                      final flowShowing = _installFlowShowing(updateState);
                      final updateRow = _updateRowContent(
                        context,
                        colors,
                        updateState,
                      );
                      return _tile(
                        Icons.cloud_queue,
                        'Check for updates',
                        (_checkingUpdates || flowShowing)
                            ? null
                            : _checkForUpdates,
                        colors,
                        trailing: _checkingUpdates
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        subtitle: updateRow.subtitle,
                        subtitleColor: updateRow.subtitleColor,
                        action: updateRow.action,
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.errorText,
                      ),
                      onPressed: () async {
                        final colors = context.read<ThemeCubit>().state.colors;
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: colors.base,
                            title: Text(
                              'Sign Out?',
                              style: AppTypography.title.copyWith(
                                color: colors.ink,
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
                                  style: TextStyle(color: colors.errorText),
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
    VoidCallback? onTap,
    ThemeColors colors, {
    Widget? trailing,
    String? subtitle,
    Color? subtitleColor,
    Widget? action,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.tileRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: colors.base,
            borderRadius: AppRadius.tileRadius,
            boxShadow: AppShadows.raised,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, color: colors.subtext),
                  const SizedBox(width: AppSpacing.base),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTypography.subtitle.copyWith(color: colors.ink),
                    ),
                  ),
                  trailing ?? Icon(Icons.chevron_right, color: colors.subtext),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTypography.label.copyWith(
                    color: subtitleColor ?? colors.subtext,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 4), action],
            ],
          ),
        ),
      ),
    );
  }
}
