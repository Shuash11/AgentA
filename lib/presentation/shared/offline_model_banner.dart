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

    final (
      Color bgColor,
      Color accentColor,
      IconData icon,
      String text,
      String? subtext,
    ) = _getStatus(
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
      icon: icon,
      text: text,
      subtext: subtext,
      bgColor: bgColor,
      accentColor: accentColor,
      textColor: colors.text,
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

  (Color, Color, IconData, String, String?) _getStatus(
    bool isOnline,
    bool isLimited,
    bool isGemmaReady,
    String modelName,
    ThemeColors colors,
  ) {
    if (isOnline) {
      return (
        colors.success.withValues(alpha: 0.15),
        colors.success,
        Icons.cloud_done_rounded,
        'Online - $modelName',
        null,
      );
    }
    if (isLimited) {
      return (
        colors.amber.withValues(alpha: 0.15),
        colors.amber,
        Icons.cloud_queue_rounded,
        'Limited - AgentA Offline AI',
        _offlineDisclaimer,
      );
    }
    if (isGemmaReady) {
      return (
        colors.amber.withValues(alpha: 0.12),
        colors.amber,
        Icons.memory_rounded,
        'Offline - AgentA Offline AI',
        _offlineDisclaimer,
      );
    }
    return (
      colors.error.withValues(alpha: 0.15),
      colors.error,
      Icons.wifi_off_rounded,
      'Offline - model not ready',
      'Tap to get the offline model.',
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? subtext;
  final Color bgColor;
  final Color accentColor;
  final Color textColor;
  final VoidCallback? onTap;

  const _StatusBanner({
    required this.icon,
    required this.text,
    this.subtext,
    required this.bgColor,
    required this.accentColor,
    required this.textColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        border: const Border(
          left: BorderSide(color: AppColors.amber, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtext != null)
                  Text(
                    subtext!,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.arrow_forward_rounded, color: accentColor, size: 16),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class SyncingBanner extends StatelessWidget {
  const SyncingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.amber.withValues(alpha: 0.15),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.amber,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Syncing data...',
            style: TextStyle(
              color: AppColors.textDark.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
