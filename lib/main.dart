import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_mediapipe/flutter_edge_ai_mediapipe.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'theme/app_theme.dart';
import 'cubit/app_providers.dart';
import 'cubit/connectivity/connectivity_cubit.dart';
import 'services/auth/auth_service.dart';
import 'services/auth/session_manager.dart';
import 'services/ai/offline_ai_service.dart';
import 'services/ai/online_ai_service.dart';
import 'services/ai/gemma_service.dart';
import 'services/ai/groq_service.dart';
import 'services/ai/huggingface_image_service.dart';
import 'services/ai/pollinations_service.dart';
import 'services/ai/ai_service.dart';
import 'services/ai/model_download_service.dart';
import 'services/sync/sync_service.dart';
import 'services/update/version_check_service.dart';
import 'core/utils/connectivity_service.dart';
import 'core/config/app_config.dart';
import 'data/local/database_helper.dart';
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

    try {
      await AppConfig.init();
      if (!mounted) return;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Main] AppConfig.init failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _initState = const InitState(
          status: AppInitStatus.error,
          errorMessage: 'App configuration failed to load. Please try again.',
        );
      });
      return;
    }

    try {
      if (AppConfig.supabaseUrl.isEmpty ||
          AppConfig.supabasePublishableKey.isEmpty) {
        throw Exception(
          'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY missing from .env',
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
      // flutter_edge_ai 1.x: core registers NO engine by default — the
      // MediaPipe (.task) engine must be registered explicitly.
      // Retry budget: 3. Each attempt can run up to the 30-min install
      // ceiling in ModelDownloadService (the 3-min stall watchdog covers
      // the silent case), so a larger budget could never complete within
      // the timeout — 3 keeps the worst case inside a plausible session
      // while transient errors still get retried.
      await FlutterEdgeAi.initialize(
        inferenceEngines: const [MediaPipeEngine()],
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

  void _startMainApp() {
    final connectivity = ConnectivityService.instance;
    unawaited(connectivity.init());
    final syncService = SyncService(connectivity);

    final groqService = GroqService();
    final pollinationsService = PollinationsService();
    final huggingFaceImageService = HuggingFaceImageService();
    final gemmaService = GemmaService();
    final offlineAIService = OfflineAIService(gemmaService);
    final onlineAIService = OnlineAIService(
      groqService,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              err,
              style: const TextStyle(color: Colors.orange, fontSize: 11),
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
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.smart_toy_outlined,
                  size: 80,
                  color: Color(0xFFFFD700),
                ),
                const SizedBox(height: 32),
                const Text(
                  'AgentA',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
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
        return const Column(
          children: [
            CircularProgressIndicator(color: Color(0xFFFFD700)),
            SizedBox(height: 16),
            Text('Initializing...', style: TextStyle(color: Colors.white70)),
          ],
        );

      case AppInitStatus.backendFailed:
        return Column(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _initState.errorMessage ?? 'Backend connection failed',
              style: const TextStyle(color: Colors.orange),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_isRetrying)
              const CircularProgressIndicator(color: Color(0xFFFFD700))
            else ...[
              ElevatedButton(
                onPressed: _retryBackend,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                ),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _continueOffline,
                child: const Text(
                  'Continue Offline',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ],
        );

      case AppInitStatus.error:
        return Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _initState.errorMessage ?? 'An error occurred',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retryBackend,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
              ),
              child: const Text('Retry'),
            ),
          ],
        );

      case AppInitStatus.backendSuccess:
      case AppInitStatus.databaseReady:
        return const Column(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 48),
            SizedBox(height: 16),
            Text('Ready!', style: TextStyle(color: Colors.green)),
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
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
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
  bool _modelReady = false;
  bool _isLoadingModel = false;
  String? _loadingError;

  @override
  void initState() {
    super.initState();
    unawaited(_checkModelStatus());
  }

  Future<void> _checkModelStatus() async {
    final modelDownload = context.read<ModelDownloadService>();
    await modelDownload.checkModelExists();

    if (!mounted) return;

    if (!modelDownload.isReady) {
      setState(() {
        _modelReady = false;
        _isChecking = false;
      });
      return;
    }

    setState(() {
      _isChecking = false;
      _isLoadingModel = true;
    });

    try {
      final gemmaService = context.read<GemmaService>();
      await gemmaService.loadInstalled();
      if (!mounted) return;
      setState(() {
        _modelReady = gemmaService.isReady;
        _isLoadingModel = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OfflineModelGate] loadInstalled failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _modelReady = false;
        _isLoadingModel = false;
        _loadingError = e.toString();
      });
    }
  }

  Future<void> _onModelReady() async {
    final modelDownload = context.read<ModelDownloadService>();
    await modelDownload.checkModelExists();
    if (!mounted) return;
    setState(() {
      _modelReady = modelDownload.isReady;
      _isChecking = false;
      _isLoadingModel = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load offline model',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The offline model could not be loaded. Please try again.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => setState(() {
                    _loadingError = null;
                    _isChecking = true;
                    unawaited(_checkModelStatus());
                  }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isChecking || _isLoadingModel) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFFFFC107)),
              const SizedBox(height: 20),
              Text(
                _isChecking
                    ? 'Checking model status...'
                    : 'Loading offline model...',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              if (!_isChecking) ...[
                const SizedBox(height: 8),
                const Text(
                  'First load can take a moment.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!_modelReady) {
      // M17: forced gate is mandatory by design — no fake skip is offered.
      return DownloadPromptScreen(
        onComplete: _onModelReady,
        isForcedGate: true,
      );
    }

    return widget.child;
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
                child: CircularProgressIndicator(color: Color(0xFFFFC107)),
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
                  child: CircularProgressIndicator(color: Color(0xFFFFC107)),
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
