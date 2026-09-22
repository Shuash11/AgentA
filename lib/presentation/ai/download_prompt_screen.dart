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
      _startAutoDownload();
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
      if (modelDownload.canUseKaggle) {
        
        try {
          await modelDownload.installModelFromKaggle();
          if (mounted && modelDownload.isReady) {
            await _completeOnce();
            return;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[DownloadPrompt] Kaggle install failed, falling back to direct download: $e');
          }
        }
      }

      await modelDownload.installModel();

      if (mounted && !modelDownload.isReady) {
        // Defensive: close any residual DB-write race before deciding the
        // outcome (installModel marks ready itself; this is belt-and-braces).
        await modelDownload.checkModelExists();
      }

      if (mounted && modelDownload.isReady) {
        await _completeOnce();
      } else if (mounted) {
        // Never leave the UI in a dead progress state — surface the retry
        // button instead of an eternal bar.
        setState(() {
          _downloading = false;
          _errorMessage = 'Download did not finish. Tap to retry.';
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DownloadPrompt] install failed: $e');
      }
      if (mounted) {
        setState(() {
          _downloading = false;
          _errorMessage = 'Download did not complete. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);
    final isOnline = context.select((ConnectivityCubit c) => c.state.isOnline);
    final hasNoInternet =
        context.select((ConnectivityCubit c) => c.state.hasNoInternet);

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
                Icon(
                  Icons.smart_toy_outlined,
                  size: 72,
                  color: colors.amber,
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  widget.isForcedGate ? 'Download AI Model' : 'Download Offline AI',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                Text(
                  widget.isForcedGate
                      ? 'This AI model must be downloaded before you can use the app.'
                      : 'Get AgentA working without internet!\nThis AI model runs locally on your device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.subtext,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Model size: ~529MB',
                    style: TextStyle(
                      color: colors.amber,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  height: 190,
                  child: Consumer<ModelDownloadService>(
                    builder: (context, modelDownload, _) {
                      if (modelDownload.progress >= 100.0 && modelDownload.isReady) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, color: colors.amber, size: 56),
                            const SizedBox(height: AppSpacing.base),
                            Text(
                              'Download Complete!',
                              style: TextStyle(color: colors.text, fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                          ],
                        );
                      }

                      if (modelDownload.progress >= 100.0 && !modelDownload.isReady) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: colors.amber, strokeWidth: 2.5),
                            ),
                            const SizedBox(height: AppSpacing.base),
                            Text(
                              'Preparing AI Model...\nThis may take a moment.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.subtext, fontSize: 15),
                            ),
                          ],
                        );
                      }

                      if (_downloading || modelDownload.status == ModelStatus.installing) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LinearProgressIndicator(
                              value: modelDownload.progress / 100,
                              backgroundColor: colors.input,
                              valueColor: AlwaysStoppedAnimation<Color>(colors.amber),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Downloading... ${modelDownload.progress.toInt()}%',
                              style: TextStyle(color: colors.subtext),
                            ),
                            if (modelDownload.isSlowConnection) ...[
                              const SizedBox(height: AppSpacing.base),
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: colors.warning.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_rounded, color: colors.warning, size: 18),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        'Slow connection detected. Download may take longer.',
                                        style: TextStyle(color: colors.warning, fontSize: 13),
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
                          padding: const EdgeInsets.all(AppSpacing.base),
                          decoration: BoxDecoration(
                            color: colors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: colors.error.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.wifi_off_rounded, color: colors.error),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(
                                  'Connection required. Please turn on Wi-Fi or Data to start the download.',
                                  style: TextStyle(color: colors.error, fontSize: 13),
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
                    style: TextStyle(color: colors.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppSpacing.xxl),
                if (!_downloading) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isOnline
                          ? _startAutoDownload
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOnline
                            ? colors.amber
                            : colors.input,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: Text(
                        isOnline
                            ? 'Download Offline AI'
                            : 'Waiting for Connection...',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (!widget.isForcedGate && widget.onSkip != null) ...[
                    const SizedBox(height: AppSpacing.base),
                    TextButton(
                      onPressed: widget.onSkip,
                      child: Text(
                        'Use Online AI Instead',
                        style: TextStyle(
                          color: colors.subtext,
                          fontSize: 14,
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
