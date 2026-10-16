import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/ai/model_download_service.dart';
import '../../cubit/connectivity/connectivity_cubit.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../theme/app_theme.dart';

class DownloadPromptScreen extends StatefulWidget {
  /// Optional skip handler. Null (or [isForcedGate]) means no skip affordance
  /// is shown — the gate is honest about being mandatory instead of showing
  /// a fake no-op skip button.
  final VoidCallback? onSkip;
  final VoidCallback onComplete;
  final bool isForcedGate;

  const DownloadPromptScreen({
    super.key,
    this.onSkip,
    required this.onComplete,
    this.isForcedGate = false,
  });

  @override
  State<DownloadPromptScreen> createState() => _DownloadPromptScreenState();
}

class _DownloadPromptScreenState extends State<DownloadPromptScreen> {
  bool _downloading = false;
  String? _errorMessage;
  bool _hasCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startAutoDownload());
      _setupCompletionListener();
    });
  }

  void _setupCompletionListener() {
    final modelDownload = context.read<ModelDownloadService>();
    modelDownload.addListener(_checkCompletion);
  }

  void _checkCompletion() {
    final modelDownload = context.read<ModelDownloadService>();
    if (modelDownload.isReady && !_hasCompleted) {
      _hasCompleted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onComplete();
        }
      });
    }
  }

  @override
  void dispose() {
    final modelDownload = context.read<ModelDownloadService>();
    modelDownload.removeListener(_checkCompletion);
    super.dispose();
  }

  Future<void> _completeOnce() async {
    if (_hasCompleted || !mounted) return;
    _hasCompleted = true;
    widget.onComplete();
  }

  Future<void> _startAutoDownload() async {
    final modelDownload = context.read<ModelDownloadService>();
    await modelDownload.checkModelExists();

    if (modelDownload.isReady && mounted) {
      await _completeOnce();
      return;
    }

    if (!mounted) return;
    final connectivity = context.read<ConnectivityCubit>();
    if (connectivity.state.hasNoInternet) {
      setState(() {
        _errorMessage = 'Please connect to the internet to download the model.';
      });
      return;
    }

    setState(() {
      _downloading = true;
      _errorMessage = null;
    });

    try {
      await modelDownload.installModel();

      if (mounted && !modelDownload.isReady) {
        // Defensive: close any residual DB-write race before deciding the
        // outcome (installModel marks ready itself; this is belt-and-braces).
        await modelDownload.checkModelExists();
      }

      if (mounted && modelDownload.isReady) {
        await _completeOnce();
      } else if (mounted) {
        // Never leave the UI in a dead progress state — surface the typed
        // friendly error from the service (brand-free, never raw), or the
        // generic fallback, with the retry button below.
        setState(() {
          _downloading = false;
          _errorMessage =
              modelDownload.errorMessage ??
              'Download did not finish. Tap to retry.';
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DownloadPrompt] install failed: $e');
      }
      if (mounted) {
        setState(() {
          _downloading = false;
          _errorMessage =
              modelDownload.errorMessage ??
              'Download did not complete. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);
    final isOnline = context.select((ConnectivityCubit c) => c.state.isOnline);
    final hasNoInternet = context.select(
      (ConnectivityCubit c) => c.state.hasNoInternet,
    );

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.smart_toy_outlined,
                  size: 56,
                  color: AppColors.subtext,
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  widget.isForcedGate
                      ? 'Download AI Model'
                      : 'Download Offline AI',
                  style: AppTypography.display.copyWith(color: colors.text),
                ),
                const SizedBox(height: AppSpacing.base),
                Text(
                  widget.isForcedGate
                      ? 'This AI model must be downloaded before you can use the app.'
                      : 'Get AgentA working without internet!\nThis AI model runs locally on your device.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: colors.subtext),
                ),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: colors.input,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Model size: ~529MB',
                    style: AppTypography.labelSm.copyWith(
                      color: colors.subtext,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  height: 190,
                  child: Consumer<ModelDownloadService>(
                    builder: (context, modelDownload, _) {
                      if (modelDownload.progress >= 100.0 &&
                          modelDownload.isReady) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                              size: 48,
                            ),
                            const SizedBox(height: AppSpacing.base),
                            Text(
                              'Download Complete!',
                              style: AppTypography.title.copyWith(
                                color: colors.text,
                              ),
                            ),
                          ],
                        );
                      }

                      if (modelDownload.progress >= 100.0 &&
                          !modelDownload.isReady) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: colors.accent,
                                strokeWidth: 2.5,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.base),
                            Text(
                              'Preparing AI Model...\nThis may take a moment.',
                              textAlign: TextAlign.center,
                              style: AppTypography.body.copyWith(
                                color: colors.subtext,
                              ),
                            ),
                          ],
                        );
                      }

                      if (_downloading ||
                          modelDownload.status == ModelStatus.installing) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LinearProgressIndicator(
                              value: modelDownload.progress / 100,
                              backgroundColor: colors.input,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colors.accent,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Downloading... ${modelDownload.progress.toInt()}%',
                              style: AppTypography.body.copyWith(
                                color: colors.subtext,
                              ),
                            ),
                            if (modelDownload.isSlowConnection) ...[
                              const SizedBox(height: AppSpacing.base),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.base,
                                  vertical: AppSpacing.sm,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.warningContainer,
                                  borderRadius: AppRadius.bannerRadius,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.warning_rounded,
                                      color: AppColors.warning,
                                      size: 18,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        'Slow connection detected. Download may take longer.',
                                        style: AppTypography.label.copyWith(
                                          color: colors.text,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      }

                      if (hasNoInternet && !modelDownload.isReady) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.base,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: AppRadius.bannerRadius,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.wifi_off_rounded,
                                color: AppColors.error,
                                size: 18,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Connection required. Please turn on Wi-Fi or Data to start the download.',
                                  style: AppTypography.label.copyWith(
                                    color: colors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    _errorMessage!,
                    style: AppTypography.label.copyWith(color: colors.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppSpacing.xxl),
                if (!_downloading) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isOnline ? _startAutoDownload : null,
                      child: Text(
                        isOnline
                            ? 'Download Offline AI'
                            : 'Waiting for Connection...',
                      ),
                    ),
                  ),
                  if (!widget.isForcedGate && widget.onSkip != null) ...[
                    const SizedBox(height: AppSpacing.base),
                    TextButton(
                      onPressed: widget.onSkip,
                      child: Text(
                        'Use Online AI Instead',
                        style: AppTypography.body.copyWith(
                          color: colors.accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
