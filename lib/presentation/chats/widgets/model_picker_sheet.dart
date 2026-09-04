import 'package:flutter/material.dart';

import '../../../services/ai/ai_model.dart';
import '../../../services/ai/ai_service.dart';
import '../../../theme/app_theme.dart';

Future<void> showModelPickerSheet({
  required BuildContext context,
  required ThemeColors colors,
  required AIService aiService,
  required ValueChanged<AIModel> onModelSelected,
  required VoidCallback onDownloadRequested,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
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
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Select AI Model',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 16),
                _ModelTile(
                  model: AIModel.gemma,
                  colors: colors,
                  aiService: aiService,
                  isOnline: aiService.isOnline,
                  isOfflineModelReady: aiService.isOfflineModelReady,
                  onSelected: (model) {
                    onModelSelected(model);
                    Navigator.pop(sheetContext);
                  },
                  onDownloadRequested: () {
                    Navigator.pop(sheetContext);
                    onDownloadRequested();
                  },
                ),
                ...AIModel.values.where((m) => m != AIModel.gemma).map(
                  (model) {
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
                  },
                ),
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
  final ValueChanged<AIModel> onSelected;
  final VoidCallback onDownloadRequested;

  const _ModelTile({
    required this.model,
    required this.colors,
    required this.aiService,
    required this.isOnline,
    this.isOfflineModelReady = false,
    required this.onSelected,
    required this.onDownloadRequested,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = aiService.preferredModel == model;
    final isAvailable =
        model == AIModel.gemma ? isOfflineModelReady : isOnline;
    final isGemmaUnready = model == AIModel.gemma && !isOfflineModelReady;
    final isDisabled = !isAvailable;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      enabled: isAvailable || isGemmaUnready,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.amber.withValues(alpha: 0.1)
              : isDisabled
                  ? colors.border.withValues(alpha: 0.3)
                  : colors.input,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          _isImageGenerationModel(model)
              ? Icons.image_rounded
              : Icons.psychology_rounded,
          color: isSelected
              ? colors.amber
              : isDisabled
                  ? colors.subtext.withValues(alpha: 0.5)
                  : colors.subtext,
          size: 24,
        ),
      ),
      title: Text(
        model.displayName,
        style: TextStyle(
          color: isSelected
              ? colors.amber
              : isDisabled
                  ? colors.text.withValues(alpha: 0.5)
                  : colors.text,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        isGemmaUnready
            ? 'Download to use offline'
            : isDisabled
                ? 'Requires Internet'
                : model.description,
        style: TextStyle(
          color: isDisabled
              ? colors.subtext.withValues(alpha: 0.5)
              : colors.subtext,
          fontSize: 13,
          height: 1.3,
        ),
      ),
      trailing: _buildTrailing(isSelected, isGemmaUnready, isDisabled),
      onTap: isAvailable
          ? () => onSelected(model)
          : isGemmaUnready
              ? onDownloadRequested
              : null,
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
  ) {
    if (isSelected) {
      return Icon(Icons.check_circle_rounded, color: colors.amber, size: 22);
    }

    if (isGemmaUnready) {
      return Icon(
        Icons.download_rounded,
        color: colors.amber.withValues(alpha: 0.7),
        size: 20,
      );
    }

    if (isDisabled) {
      return Icon(
        Icons.wifi_off_rounded,
        color: colors.subtext.withValues(alpha: 0.3),
        size: 20,
      );
    }

    return null;
  }
}
