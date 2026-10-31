import 'package:flutter/material.dart';

import '../../../services/ai/ai_model.dart';
import '../../../services/ai/ai_service.dart';
import '../../../services/ai/device_capabilities.dart';
import '../../../theme/app_theme.dart';

/// What the offline (Gemma) tile shows while the model is NOT ready, and
/// whether tapping it may start the download.
///
/// A device that cannot run the model never gets the download invitation:
/// the tile carries the honest incompatible-device message and tapping it
/// does nothing (cycle-40 P1).
({String subtitle, bool canDownload}) offlineTileUnavailableState({
  required bool isDeviceCompatible,
}) {
  if (!isDeviceCompatible) {
    return (
      subtitle: DeviceCapabilities.incompatibleDeviceMessage,
      canDownload: false,
    );
  }
  return (subtitle: 'Download to use offline', canDownload: true);
}

Future<void> showModelPickerSheet({
  required BuildContext context,
  required ThemeColors colors,
  required AIService aiService,
  required ValueChanged<AIModel> onModelSelected,
  required VoidCallback onDownloadRequested,
}) async {
  // The device capability decides whether the offline tile may offer the
  // download at all (cycle-40 P1) — it is resolved before the sheet opens
  // so the tile never flashes a download invitation it cannot honour.
  final isDeviceCompatible = await DeviceCapabilities.isOfflineAiSupported();
  if (!context.mounted) return;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.base,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: colors.base,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Select AI Model',
                  style: AppTypography.title.copyWith(color: colors.ink),
                ),
                const SizedBox(height: 16),
                _ModelTile(
                  model: AIModel.gemma,
                  colors: colors,
                  aiService: aiService,
                  isOnline: aiService.isOnline,
                  isOfflineModelReady: aiService.isOfflineModelReady,
                  isDeviceCompatible: isDeviceCompatible,
                  onSelected: (model) {
                    onModelSelected(model);
                    Navigator.pop(sheetContext);
                  },
                  onDownloadRequested: () {
                    Navigator.pop(sheetContext);
                    onDownloadRequested();
                  },
                ),
                ...AIModel.values.where((m) => m != AIModel.gemma).map((model) {
                  return _ModelTile(
                    model: model,
                    colors: colors,
                    aiService: aiService,
                    isOnline: aiService.isOnline,
                    onSelected: (model) {
                      onModelSelected(model);
                      Navigator.pop(sheetContext);
                    },
                    onDownloadRequested: onDownloadRequested,
                  );
                }),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ModelTile extends StatelessWidget {
  final AIModel model;
  final ThemeColors colors;
  final AIService aiService;
  final bool isOnline;
  final bool isOfflineModelReady;

  /// Whether this device can run the offline model (cycle-40 P1).
  final bool isDeviceCompatible;

  final ValueChanged<AIModel> onSelected;
  final VoidCallback onDownloadRequested;

  const _ModelTile({
    required this.model,
    required this.colors,
    required this.aiService,
    required this.isOnline,
    this.isOfflineModelReady = false,
    this.isDeviceCompatible = true,
    required this.onSelected,
    required this.onDownloadRequested,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = aiService.preferredModel == model;
    final isAvailable = model == AIModel.gemma ? isOfflineModelReady : isOnline;
    final isGemmaUnready = model == AIModel.gemma && !isOfflineModelReady;
    final isDisabled = !isAvailable;

    // The offline tile's unavailable state: the download invitation on a
    // compatible device, the honest incompatible-device message otherwise
    // (cycle-40 P1).
    final unavailable = offlineTileUnavailableState(
      isDeviceCompatible: isDeviceCompatible,
    );
    final canStartDownload = isGemmaUnready && unavailable.canDownload;

    return Container(
      // Selected = inset well (§5); unselected/disabled sit flat on the sheet.
      decoration: BoxDecoration(
        color: colors.base,
        borderRadius: AppRadius.tileRadius,
        boxShadow: isSelected ? AppShadows.pressed : AppShadows.flat,
      ),
      child: Material(
        // The ListTile paints its background and ink splashes on the
        // nearest Material ancestor. Without this transparent Material the
        // tile's own decorated background hides them (and trips Flutter's
        // ListTile background check in debug builds).
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          enabled: isAvailable || isGemmaUnready,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.base,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isImageGenerationModel(model)
                  ? Icons.image_rounded
                  : Icons.psychology_rounded,
              color: isSelected
                  ? colors.accent
                  : isDisabled
                  ? colors.disabledText
                  : colors.subtext,
              size: 24,
            ),
          ),
          title: Text(
            model.displayName,
            style: AppTypography.subtitle.copyWith(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? colors.accentInk
                  : isDisabled
                  ? colors.disabledText
                  : colors.ink,
            ),
          ),
          subtitle: Text(
            isGemmaUnready
                ? unavailable.subtitle
                : isDisabled
                ? 'Requires Internet'
                : model.description,
            style: AppTypography.label.copyWith(
              color: isDisabled ? colors.disabledText : colors.subtext,
            ),
          ),
          trailing: _buildTrailing(
            isSelected,
            isGemmaUnready,
            isDisabled,
            canStartDownload,
          ),
          onTap: isAvailable
              ? () => onSelected(model)
              : canStartDownload
              ? onDownloadRequested
              : null,
        ),
      ),
    );
  }

  bool _isImageGenerationModel(AIModel model) {
    return model.name.toLowerCase().contains('pollinations') ||
        model.name.toLowerCase().contains('image');
  }

  Widget? _buildTrailing(
    bool isSelected,
    bool isGemmaUnready,
    bool isDisabled,
    bool canStartDownload,
  ) {
    if (isSelected) {
      return Icon(Icons.check_circle_rounded, color: colors.accent, size: 22);
    }

    if (isGemmaUnready) {
      // A device that cannot run the model has no download to offer — the
      // tile says so instead of showing a download affordance (cycle-40 P1).
      if (!canStartDownload) {
        return Icon(Icons.block, color: colors.disabledText, size: 20);
      }
      return Icon(Icons.download_rounded, color: colors.accent, size: 20);
    }

    if (isDisabled) {
      return Icon(Icons.wifi_off_rounded, color: colors.disabledText, size: 20);
    }

    return null;
  }
}
