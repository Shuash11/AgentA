import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/ai/ai_model.dart';
import '../../../services/ai/ai_service.dart';
import '../../../services/ai/device_capabilities.dart';
import '../../../services/ai/offline_model_spec.dart';
import '../../../theme/app_theme.dart';

/// What the offline (Gemma) tile shows while the model is NOT ready, and
/// whether tapping it may start the download.
///
/// A device that cannot run the model never gets the download invitation
/// by default: the tile carries the honest incompatible-device message and
/// tapping it does nothing (cycle-40 P1). AMENDED at cycle-43 (contract §6
/// under_floor_first_use / under_floor_post_ack):
///
/// * a BELOW-FLOOR device (readable RAM) renders the ruled risk copy
///   FIRST, the honest message stays, and the tile's tap becomes the
///   "Download anyway" override — it records the ack and routes into the
///   download flow ([showModelPickerSheet]'s override route);
/// * post-ack the download is ENABLED and the short retained risk line
///   accompanies it (never re-nagged, never silently green);
/// * an UNREADABLE-RAM device keeps the plain honest message — the
///   override consents to a RAM risk, and the UI never states RAM it
///   cannot know (the fail-closed rule).
({String subtitle, bool canDownload}) offlineTileUnavailableState({
  required bool isDeviceCompatible,
  bool isBelowFloor = false,
}) {
  if (!isDeviceCompatible) {
    if (isBelowFloor) {
      return (
        subtitle:
            '${DeviceCapabilities.underFloorRiskCopy}\n'
            '${DeviceCapabilities.incompatibleDeviceMessage}',
        canDownload: false,
      );
    }
    return (
      subtitle: DeviceCapabilities.incompatibleDeviceMessage,
      canDownload: false,
    );
  }
  if (isBelowFloor) {
    // Post-ack: the honesty leads, the enabled invitation follows.
    return (
      subtitle:
          '${DeviceCapabilities.underFloorRetainedRiskLine}\n'
          'Download to use offline',
      canDownload: true,
    );
  }
  return (subtitle: 'Download to use offline', canDownload: true);
}

/// Records the under-floor override ack (cycle-43) and then runs the
/// host's download flow — the picker tile's "Download anyway" route. The
/// ack is recorded BEFORE the flow opens, so the download screen resolves
/// the now-admitted selection and proceeds normally.
Future<void> _acknowledgeOverrideThenDownload(
  VoidCallback onDownloadRequested,
) async {
  await DeviceCapabilities.acknowledgeRamOverride();
  onDownloadRequested();
}

Future<void> showModelPickerSheet({
  required BuildContext context,
  required ThemeColors colors,
  required AIService aiService,
  required ValueChanged<AIModel> onModelSelected,
  required VoidCallback onDownloadRequested,
}) async {
  // The per-device selection decides whether the offline tile may offer the
  // download at all (cycle-42 P2b) — it is resolved before the sheet opens
  // so the tile never flashes a download invitation it cannot honour. The
  // message-only class has NO model: the tile carries the honest message
  // and tapping it does nothing (cycle-40 P1). Cycle-43: the below-floor
  // facts ride the same resolve — the tile's override affordance (risk
  // copy + "Download anyway") and the post-ack retained line are keyed to
  // the SAME selection every other surface reads.
  final selection = await OfflineModelSpecTable.resolve();
  if (!context.mounted) return;
  final isDeviceCompatible = selection.hasModel;
  final isBelowFloor = selection.isBelowFloor;

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
                  isBelowFloor: isBelowFloor,
                  onSelected: (model) {
                    onModelSelected(model);
                    Navigator.pop(sheetContext);
                  },
                  onDownloadRequested: () {
                    Navigator.pop(sheetContext);
                    onDownloadRequested();
                  },
                  // The override route (cycle-43): only the below-floor
                  // message-only state carries it — the tap records the
                  // ack FIRST, then routes into the download flow with the
                  // override acknowledged.
                  onOverrideDownload: () {
                    Navigator.pop(sheetContext);
                    unawaited(
                      _acknowledgeOverrideThenDownload(onDownloadRequested),
                    );
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

  /// Whether this device's RAM is readable and below the floor (cycle-43,
  /// contract §3 under_floor_override): the below-floor fact that keys the
  /// tile's "Download anyway" override state (first use) and its retained
  /// risk line (post-ack).
  final bool isBelowFloor;

  /// The override route (cycle-43): records the ack and routes into the
  /// download flow. Null for the non-gemma tiles — they never enter the
  /// override state.
  final VoidCallback? onOverrideDownload;

  final ValueChanged<AIModel> onSelected;
  final VoidCallback onDownloadRequested;

  const _ModelTile({
    required this.model,
    required this.colors,
    required this.aiService,
    required this.isOnline,
    this.isOfflineModelReady = false,
    this.isDeviceCompatible = true,
    this.isBelowFloor = false,
    this.onOverrideDownload,
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
    // compatible device, the honest incompatible-device message otherwise,
    // the risk copy + the override state on a below-floor device, and the
    // retained line on an overridden one (cycle-40 P1; cycle-43).
    final unavailable = offlineTileUnavailableState(
      isDeviceCompatible: isDeviceCompatible,
      isBelowFloor: isBelowFloor,
    );
    final canStartDownload = isGemmaUnready && unavailable.canDownload;
    // The override state (cycle-43): a below-floor device that cannot run
    // the model YET — its tap is the "Download anyway" override, not a
    // direct download (consent comes first, cycle-43 §6 S1).
    final canOverride =
        isGemmaUnready &&
        !isDeviceCompatible &&
        isBelowFloor &&
        onOverrideDownload != null;

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
            canOverride,
          ),
          onTap: isAvailable
              ? () => onSelected(model)
              : canStartDownload
              ? onDownloadRequested
              : canOverride
              ? onOverrideDownload
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
    bool canOverride,
  ) {
    if (isSelected) {
      return Icon(Icons.check_circle_rounded, color: colors.accent, size: 22);
    }

    if (isGemmaUnready) {
      // The override affordance (cycle-43): a below-floor device's tile
      // names the consequence explicitly — the tap records the ack and
      // routes into the download flow. The option label summarises what
      // happens (contract §6 under_floor_first_use, verbatim).
      if (canOverride) {
        return Text(
          DeviceCapabilities.downloadAnywayButtonLabel,
          style: AppTypography.label.copyWith(color: colors.accentInk),
        );
      }
      // A device that cannot run the model has no download to offer — the
      // tile says so instead of showing a download affordance (cycle-40
      // P1; the unreadable state keeps this plain treatment at cycle-43).
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
