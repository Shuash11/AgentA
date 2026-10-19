import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/ai/ai_model.dart';
import '../../services/ai/model_download_service.dart';
import '../../services/ai/online_ai_service.dart';
import '../../cubit/connectivity/connectivity_cubit.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../theme/app_theme.dart';
import '../ai/download_prompt_screen.dart';

class OfflineModelBanner extends StatelessWidget {
  final VoidCallback? onTap;

  const OfflineModelBanner({super.key, this.onTap});

  static const String _offlineDisclaimer =
      'Offline answers can make mistakes — double-check schoolwork.';

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);
    final isOnline = context.select((ConnectivityCubit c) => c.state.isOnline);
    final isLimited = context.select(
      (ConnectivityCubit c) => c.state.isLimited,
    );
    final isGemmaReady = context.select((ModelDownloadService m) => m.isReady);
    final modelName = context.select(
      (OnlineAIService o) => o.preferredModel.displayName,
    );

    final status = _getStatus(
      isOnline,
      isLimited,
      isGemmaReady,
      modelName,
      colors,
    );

    final needsModel = !isOnline && !isLimited && !isGemmaReady;
    final effectiveOnTap =
        onTap ?? (needsModel ? () => openDownloadScreen(context) : null);

    return _StatusBanner(
      icon: status.icon,
      iconColor: status.iconColor,
      bgColor: status.background,
      titleColor: status.titleColor,
      subtextColor: status.subtextColor,
      text: status.text,
      subtext: status.subtext,
      onTap: effectiveOnTap,
    );
  }

  /// Shared navigation to the offline-model download screen.
  static void openDownloadScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DownloadPromptScreen(
          onSkip: () => Navigator.pop(context),
          onComplete: () => Navigator.pop(context),
          isForcedGate: false,
        ),
      ),
    );
  }

  ({
    Color background,
    Color iconColor,
    Color titleColor,
    Color subtextColor,
    IconData icon,
    String text,
    String? subtext,
  })
  _getStatus(
    bool isOnline,
    bool isLimited,
    bool isGemmaReady,
    String modelName,
    ThemeColors colors,
  ) {
    if (isOnline) {
      return (
        background: colors.base,
        iconColor: colors.successText,
        titleColor: colors.ink,
        subtextColor: colors.subtext,
        icon: Icons.cloud_done_rounded,
        text: 'Online — $modelName',
        subtext: null,
      );
    }
    if (isLimited) {
      return (
        background: colors.base,
        iconColor: colors.warningText,
        titleColor: colors.ink,
        subtextColor: colors.subtext,
        icon: Icons.cloud_queue_rounded,
        text: 'Limited — AgentA Offline AI',
        subtext: _offlineDisclaimer,
      );
    }
    if (isGemmaReady) {
      return (
        background: colors.base,
        iconColor: colors.accentInk,
        titleColor: colors.accentInk,
        subtextColor: colors.accentInk,
        icon: Icons.memory_rounded,
        text: 'Offline — AgentA Offline AI',
        subtext: _offlineDisclaimer,
      );
    }
    return (
      background: colors.base,
      iconColor: colors.errorText,
      titleColor: colors.errorText,
      subtextColor: colors.subtext,
      icon: Icons.wifi_off_rounded,
      text: 'Offline — model not ready',
      subtext: 'Tap to get the offline model.',
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Color titleColor;
  final Color subtextColor;
  final String text;
  final String? subtext;
  final VoidCallback? onTap;

  const _StatusBanner({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.titleColor,
    required this.subtextColor,
    required this.text,
    this.subtext,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(color: bgColor, boxShadow: AppShadows.raised),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: AppTypography.label.copyWith(color: titleColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtext != null)
                  Text(
                    subtext!,
                    style: AppTypography.labelSm.copyWith(color: subtextColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.arrow_forward_rounded, color: iconColor, size: 16),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class SyncingBanner extends StatelessWidget {
  const SyncingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.base,
        boxShadow: AppShadows.raised,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Syncing data...',
            style: AppTypography.label.copyWith(color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}
