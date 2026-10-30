import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_mediapipe/flutter_edge_ai_mediapipe.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'theme/app_theme.dart';
import 'cubit/app_providers.dart';
import 'cubit/connectivity/connectivity_cubit.dart';
import 'services/auth/auth_service.dart';
import 'services/auth/session_manager.dart';
import 'services/ai/offline_ai_service.dart';
import 'services/ai/online_ai_service.dart';
import 'services/ai/gemma_service.dart';
import 'services/ai/groq_service.dart';
import 'services/ai/openrouter_service.dart';
import 'services/ai/huggingface_image_service.dart';
import 'services/ai/pollinations_service.dart';
import 'services/ai/ai_service.dart';
import 'services/ai/model_download_service.dart';
import 'services/sync/sync_service.dart';
import 'services/update/version_check_service.dart';
import 'core/utils/connectivity_service.dart';
import 'core/config/app_config.dart';
import 'data/local/database_helper.dart';
import 'data/local/offline_model_dao.dart';
import 'repositories/chat_repository.dart';
import 'repositories/message_repository.dart';
import 'presentation/auth/login.dart';
import 'presentation/shared/app_shell.dart';
import 'presentation/shared/update_dialog_host.dart';
import 'presentation/ai/download_prompt_screen.dart';

enum AppInitStatus {
  initializing,
  backendSuccess,
  backendFailed,
  databaseReady,
  error,
}

class InitState {
  final AppInitStatus status;
  final String? errorMessage;
  final bool isOfflineOnly;

  const InitState({
    this.status = AppInitStatus.initializing,
    this.errorMessage,
    this.isOfflineOnly = false,
  });

  InitState copyWith({
    AppInitStatus? status,
    String? errorMessage,
    bool? isOfflineOnly,
  }) {
    return InitState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      isOfflineOnly: isOfflineOnly ?? this.isOfflineOnly,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const AppLoader());
}

class AppLoader extends StatefulWidget {
  const AppLoader({super.key});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  InitState _initState = const InitState();
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeApp());
  }

  Future<void> _initializeApp() async {
    // Config change: allow Google to re-initialize with new env values.
    AuthService.resetGoogleInit();

    setState(() {
      _initState = const InitState(status: AppInitStatus.initializing);
    });

    // F11 part 4: read-only upgrade check BEFORE the first secure-storage
    // access (AuthGate/SyncService reads, biometric reads, and DB-migration
    // key drops all happen after this point); Android-only per the plugin
    // contract; never blocks boot.
    await _checkSecureStorageUpgrade();

    try {
      if (AppConfig.supabaseUrl.isEmpty ||
          AppConfig.supabasePublishableKey.isEmpty) {
        throw Exception(
          'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY missing (pass via --dart-define)',
        );
      }
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
      );
      AuthService.markBackendReady();
      if (kDebugMode) {
        debugPrint('[Main] Supabase initialized successfully');
      }

      // ── Env validation split: validate Google ID at startup, set flag ──
      // Allow app to boot even if Google is misconfigured; expose flag for banner.
      final googleOk = AppConfig.validateGoogleConfigAtStartup();
      if (googleOk) {
        try {
          await AuthService.ensureGoogleInitialized();
          if (kDebugMode) {
            debugPrint(
              '[Main] GoogleSignIn pre-initialized at startup | suffix: ...${AppConfig.googleIdSuffixForLog}',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[Main] GoogleSignIn startup init failed (non-fatal, will retry on sign-in): $e | suffix: ...${AppConfig.googleIdSuffixForLog}',
            );
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '[Main] GoogleSignIn not configured at startup | error: ${AppConfig.googleConfigError} | suffix: ...${AppConfig.googleIdSuffixForLog}',
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _initState = const InitState(status: AppInitStatus.backendSuccess);
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Main] Supabase init failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _initState = const InitState(
          status: AppInitStatus.backendFailed,
          errorMessage:
              'Backend connection failed. You can continue in offline mode.',
        );
      });
    }

    try {
      // flutter_edge_ai 1.x: core registers NO engine by default — every
      // engine must be registered explicitly. MediaPipe (.task) stays
      // registered so the legacy 1B asset's uninstall id still resolves;
      // LiteRT-LM (.litertlm) runs the current Gemma 4 E2B bundle.
      // Retry budget: 3. Each attempt can run up to the 60-min install
      // ceiling in ModelDownloadService (the 3-min stall watchdog covers
      // the silent case), so a larger budget could never complete within
      // the timeout — 3 keeps the worst case inside a plausible session
      // while transient errors still get retried.
      await FlutterEdgeAi.initialize(
        inferenceEngines: const [MediaPipeEngine(), LiteRtLmEngine()],
        maxDownloadRetries: 3,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Main] FlutterEdgeAi.initialize failed (ignored): $e');
      }
    }
    if (!mounted) return;

    try {
      final dbHelper = DatabaseHelper.instance;
      await dbHelper.database;
      if (!mounted) return;
      setState(() {
        _initState = _initState.copyWith(status: AppInitStatus.databaseReady);
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Main] Database init failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _initState = const InitState(
          status: AppInitStatus.error,
          errorMessage: 'App data failed to initialize. Please try again.',
        );
      });
      return;
    }

    if (_initState.status == AppInitStatus.databaseReady) {
      _startMainApp();
    }
  }

  /// F11 part 4: reports whether secure-storage data written by an older
  /// plugin version survived the fss 10->11 upgrade. Read-only; Android is
  /// the only platform the plugin implements it on (elsewhere the plugin
  /// returns `unsupported`). A loss report arms the one-shot login notice
  /// ([AppConfig.consumeStorageUpgradeNotice]) so skip-path users degrade to
  /// re-login/re-enroll instead of a silent sign-out. Raw plugin detail stays
  /// in debug logs (docs/error-hygiene.md).
  Future<void> _checkSecureStorageUpgrade() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await const FlutterSecureStorage().checkUpgradeStatus();
      if (status.hasDataLoss) {
        AppConfig.recordStorageUpgradeLoss(
          state: status.state.name,
          reason: status.reason.name,
          entryCount: status.entryCount,
          details: status.details,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Main] secure-storage upgrade check failed: $e');
      }
    }
  }

  void _startMainApp() {
    final connectivity = ConnectivityService.instance;
    unawaited(connectivity.init());
    final syncService = SyncService(connectivity);

    final groqService = GroqService();
    final openRouterService = OpenRouterService();
    final pollinationsService = PollinationsService();
    final huggingFaceImageService = HuggingFaceImageService();
    final gemmaService = GemmaService();
    final offlineAIService = OfflineAIService(gemmaService);
    final onlineAIService = OnlineAIService(
      groqService,
      openRouterService,
      pollinationsService,
      huggingFaceImageService,
    );
    final modelDownloadService = ModelDownloadService();
    final aiService = AIService(
      offlineAIService,
      onlineAIService,
      connectivity,
    );
    final chatRepository = ChatRepository();
    final messageRepository = MessageRepository();

    // Update-check engine: init POST-FIRST-FRAME (plus_plugins #309 —
    // PackageInfo.fromPlatform must never run before the first frame /
    // runApp). The UpdateDialogHost (MaterialApp builder) is mounted by
    // then, so the first check can already reach the UI over any screen.
    // Fire-and-forget — never blocks boot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(VersionCheckService.instance.init());
    });

    runApp(
      AppProviders(
        connectivity: connectivity,
        gemmaService: gemmaService,
        groqService: groqService,
        openRouterService: openRouterService,
        pollinationsService: pollinationsService,
        huggingFaceImageService: huggingFaceImageService,
        offlineAIService: offlineAIService,
        onlineAIService: onlineAIService,
        modelDownloadService: modelDownloadService,
        aiService: aiService,
        chatRepository: chatRepository,
        messageRepository: messageRepository,
        syncService: syncService,
        child: const MyApp(),
      ),
    );
  }

  Future<void> _retryBackend() async {
    setState(() {
      _isRetrying = true;
    });
    // Reset Google init so retry re-validates env and re-initializes.
    AuthService.resetGoogleInit();
    AppConfig.notifyGoogleConfigChanged();
    await _initializeApp();
    if (!mounted) return;
    setState(() {
      _isRetrying = false;
    });
  }

  void _continueOffline() {
    setState(() {
      _initState = const InitState(
        status: AppInitStatus.databaseReady,
        isOfflineOnly: true,
      );
    });
    _startMainApp();
  }

  Widget _googleConfigBanner() {
    if (AppConfig.googleConfigured) return const SizedBox.shrink();
    final err = AppConfig.googleConfigError ?? 'Google sign-in not configured';
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.base,
        borderRadius: AppRadius.bannerRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warningText,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              err,
              style: AppTypography.label.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AgentA',
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: AppColors.base,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.smart_toy_outlined,
                  size: 80,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 32),
                Text(
                  'AgentA',
                  style: AppTypography.display.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 48),
                _buildStatusWidget(),
                _googleConfigBanner(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusWidget() {
    switch (_initState.status) {
      case AppInitStatus.initializing:
        return Column(
          children: [
            const CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              'Initializing...',
              style: AppTypography.label.copyWith(color: AppColors.subtext),
            ),
          ],
        );

      case AppInitStatus.backendFailed:
        return Column(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warningText,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _initState.errorMessage ?? 'Backend connection failed',
              style: AppTypography.body.copyWith(color: AppColors.warningText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_isRetrying)
              const CircularProgressIndicator(color: AppColors.accent)
            else ...[
              ElevatedButton(
                onPressed: _retryBackend,
                child: const Text('Retry'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _continueOffline,
                child: Text(
                  'Continue Offline',
                  style: AppTypography.body.copyWith(color: AppColors.subtext),
                ),
              ),
            ],
          ],
        );

      case AppInitStatus.error:
        return Column(
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.errorText,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _initState.errorMessage ?? 'An error occurred',
              style: AppTypography.body.copyWith(color: AppColors.errorText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retryBackend,
              child: const Text('Retry'),
            ),
          ],
        );

      case AppInitStatus.backendSuccess:
      case AppInitStatus.databaseReady:
        return Column(
          children: [
            const Icon(
              Icons.check_circle,
              color: AppColors.successText,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Ready!',
              style: AppTypography.body.copyWith(color: AppColors.successText),
            ),
          ],
        );
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AgentA',
      theme: AppTheme.lightTheme,
      // Update dialog host: app-level overlay via the builder — the dialog
      // appears over ANY screen (login, model-download gate, shell). The
      // navigatorKey lets the host (mounted above the navigator) push the
      // dialog route directly.
      navigatorKey: UpdateDialogHost.navigatorKey,
      builder: (context, child) =>
          UpdateDialogHost(child: child ?? const SizedBox.shrink()),
      home: const OfflineModelGate(child: AuthGate()),
    );
  }
}

class OfflineModelGate extends StatefulWidget {
  final Widget child;

  const OfflineModelGate({super.key, required this.child});

  @override
  State<OfflineModelGate> createState() => _OfflineModelGateState();
}

class _OfflineModelGateState extends State<OfflineModelGate> {
  bool _isChecking = true;
  bool _isLoadingModel = false;

  /// Whether the asset is recorded as INSTALLED on the device (the durable
  /// DAO marker). An installed model must never fall back to the download
  /// gate — that is the spurious 2.6 GB re-download class (cycle-38 P6,
  /// S7). It is the routing authority for the retry surface.
  bool _isInstalled = false;

  /// Readiness state of the on-device model. Drives the gate surface:
  /// loaded → the app, loadFailed → the retry surface, idle/modelMissing →
  /// the download gate.
  OfflineModelState _modelState = OfflineModelState.idle;

  @override
  void initState() {
    super.initState();
    unawaited(_checkModelStatus());
  }

  /// Checks the download state, then LOADS the installed model.
  ///
  /// The model is loaded on every path that finds it installed — the initial
  /// check, the post-install re-check and the error-screen retry — so
  /// "installed" can never mean "declared ready but never loaded" (the
  /// cycle-38 P6 dead-end).
  Future<void> _checkModelStatus() async {
    final modelDownload = context.read<ModelDownloadService>();
    await modelDownload.checkModelExists();
    if (!mounted) return;

    // The DAO row is the durable truth: an error row that still carries the
    // download marker means the asset IS installed (it only failed to load)
    // and must route to RETRY — never to the download gate, which would
    // strand the user behind a spurious 2.6 GB re-download.
    final installed = await OfflineModelDao().isModelInstalled();
    if (!mounted) return;

    if (!installed) {
      setState(() {
        _isChecking = false;
        _isLoadingModel = false;
        _isInstalled = false;
        _modelState = OfflineModelState.idle;
      });
      return;
    }

    setState(() {
      _isChecking = false;
      _isLoadingModel = true;
      _isInstalled = true;
    });

    await _attemptLoad();
  }

  /// Loads the model and records the outcome.
  ///
  /// A failure never dead-ends: the state decides the surface — a broken but
  /// installed model gets the retry screen, a missing asset gets the
  /// download gate.
  Future<void> _attemptLoad() async {
    final gemmaService = context.read<GemmaService>();
    try {
      await gemmaService.loadInstalled();
      if (!mounted) return;
      // A successful load rewrites the DAO row to ready. The download
      // service's in-memory status was computed from the ERROR row (an
      // installed-but-broken model reads as "not ready" there), so it is
      // re-synced here: otherwise every surface that asks the download
      // service — the offline banner, the download screen — would keep
      // claiming the model is missing and would route the user into the
      // very download screen that no-ops for an installed model
      // (cycle-38 P6). checkModelExists() only reads state; it never
      // downloads.
      await context.read<ModelDownloadService>().checkModelExists();
      if (!mounted) return;
      setState(() {
        _isLoadingModel = false;
        _modelState = gemmaService.state;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[OfflineModelGate] loadInstalled failed: $e (type: ${e.runtimeType})',
        );
      }
      if (!mounted) return;
      setState(() {
        _isLoadingModel = false;
        _modelState = gemmaService.state;
      });
    }
  }

  /// Post-download: the asset is on the device — LOAD it.
  ///
  /// The old path only re-checked the download state and declared the gate
  /// open, which left the model unloaded and the chat stuck on "still
  /// getting ready" (cycle-38 P6).
  Future<void> _onModelReady() async {
    final modelDownload = context.read<ModelDownloadService>();
    await modelDownload.checkModelExists();
    if (!mounted) return;
    // The download just completed: the asset is on the device. The durable
    // marker is re-read so the gate keeps routing an installed model to the
    // retry surface — never back to the download gate (S7).
    final installed = await OfflineModelDao().isModelInstalled();
    if (!mounted) return;
    setState(() {
      _isChecking = false;
      _isLoadingModel = true;
      _isInstalled = installed;
    });
    await _attemptLoad();
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking || _isLoadingModel) {
      return Scaffold(
        backgroundColor: AppColors.base,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.accent),
              const SizedBox(height: 20),
              Text(
                _isChecking
                    ? 'Checking model status...'
                    : 'Loading offline model...',
                style: AppTypography.body.copyWith(color: AppColors.subtext),
              ),
              if (!_isChecking) ...[
                const SizedBox(height: 8),
                Text(
                  'First load can take a moment.',
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.subtext,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_modelState == OfflineModelState.loaded) {
      return widget.child;
    }

    // S7: an INSTALLED model never falls back to the download gate — the
    // user would be stranded behind a spurious 2.6 GB re-download of an
    // asset the device already has. The retry surface is the only honest
    // affordance for it, and it always re-invokes the service's load.
    if (_isInstalled || _modelState == OfflineModelState.loadFailed) {
      // The model is installed but did not load: the honest surface is a
      // retry, not a download.
      return Scaffold(
        backgroundColor: AppColors.base,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.errorText,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load offline model',
                  style: AppTypography.subtitle.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'The offline model could not be loaded. Please try again.',
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.subtext,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isChecking = true;
                      _isLoadingModel = false;
                    });
                    unawaited(_checkModelStatus());
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // M17: forced gate is mandatory by design — no fake skip is offered.
    return DownloadPromptScreen(onComplete: _onModelReady, isForcedGate: true);
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    context.read<SyncService>().init();
  }

  Future<bool> _hasOfflineSession() async {
    try {
      if (Supabase.instance.client.auth.currentSession != null) return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthGate] currentSession check failed: $e');
    }
    return (await SessionManager.currentSession()) != null;
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isBackendReady) {
      return FutureBuilder<bool>(
        future: _hasOfflineSession(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            );
          }
          if (snapshot.data == true) {
            return const AppShell(offlineMode: true);
          }
          return const LoginPage();
        },
      );
    }
    return BlocBuilder<ConnectivityCubit, ConnectivityState>(
      buildWhen: (previous, current) => previous.isOnline != current.isOnline,
      builder: (context, connectivityState) {
        return StreamBuilder<AuthState>(
          stream: AuthService.authStateChanges,
          builder: (context, authSnapshot) {
            AuthState? data = authSnapshot.data;
            SupabaseClient client;
            try {
              client = Supabase.instance.client;
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[AuthGate] Supabase client unavailable: $e');
              }
              return const LoginPage();
            }
            final session = data?.session ?? client.auth.currentSession;
            if (authSnapshot.connectionState == ConnectionState.waiting &&
                session == null) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              );
            }
            if (session != null) {
              return AppShell(offlineMode: !connectivityState.isOnline);
            }
            return const LoginPage();
          },
        );
      },
    );
  }
}
