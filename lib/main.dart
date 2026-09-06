// ignore_for_file: empty_catches
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'theme/app_theme.dart';
import 'cubit/app_providers.dart';
import 'cubit/connectivity/connectivity_cubit.dart';
import 'services/auth/auth_service.dart';
import 'services/ai/offline_ai_service.dart';
import 'services/ai/online_ai_service.dart';
import 'services/ai/gemma_service.dart';
import 'services/ai/groq_service.dart';
import 'services/ai/huggingface_image_service.dart';
import 'services/ai/minimax_service.dart';
import 'services/ai/pollinations_service.dart';
import 'services/ai/ai_service.dart';
import 'services/ai/model_download_service.dart';
import 'services/sync/sync_service.dart';
import 'core/utils/connectivity_service.dart';
import 'core/config/app_config.dart';
import 'data/local/database_helper.dart';
import 'repositories/chat_repository.dart';
import 'repositories/message_repository.dart';
import 'presentation/auth/login.dart';
import 'presentation/shared/app_shell.dart';
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
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    setState(() {
      _initState = const InitState(status: AppInitStatus.initializing);
    });

    try {
      await AppConfig.init();
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initState = InitState(
          status: AppInitStatus.error,
          errorMessage: 'Failed to load app config: $e',
        );
      });
      return;
    }

    try {
      if (AppConfig.supabaseUrl.isEmpty ||
          AppConfig.supabasePublishableKey.isEmpty) {
        throw Exception(
            'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY missing from .env');
      }
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
      );
      AuthService.markBackendReady();
      if (!mounted) return;
      setState(() {
        _initState = const InitState(status: AppInitStatus.backendSuccess);
      });
    } catch (e) {
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
      await FlutterGemma.initialize();
} catch (e) {}
    if (!mounted) return;

    try {
      final dbHelper = DatabaseHelper.instance;
      await dbHelper.database;
      if (!mounted) return;
      setState(() {
        _initState = _initState.copyWith(status: AppInitStatus.databaseReady);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initState = InitState(
          status: AppInitStatus.error,
          errorMessage: 'Failed to initialize database: $e',
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
    connectivity.init();
    final syncService = SyncService(connectivity);

    final groqService = GroqService();
    final minimaxService = MiniMaxService();
    final pollinationsService = PollinationsService();
    final huggingFaceImageService = HuggingFaceImageService();
    final gemmaService = GemmaService();
    final offlineAIService = OfflineAIService(gemmaService);
    final onlineAIService = OnlineAIService(
      groqService,
      minimaxService,
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

    runApp(
      AppProviders(
        connectivity: connectivity,
        gemmaService: gemmaService,
        groqService: groqService,
        minimaxService: minimaxService,
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Skill Coach',
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
            Text(
              'Initializing...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        );

      case AppInitStatus.backendFailed:
        return Column(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
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
            Text(
              'Ready!',
              style: TextStyle(color: Colors.green),
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
      title: 'AI Skill Coach',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const OfflineModelGate(
        child: AuthGate(),
      ),
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
    _checkModelStatus();
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
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _loadingError!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => setState(() {
                    _loadingError = null;
                    _isChecking = true;
                    _checkModelStatus();
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
                _isChecking ? 'Checking model status...' : 'Loading offline model...',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (!_modelReady) {
      return DownloadPromptScreen(
        onSkip: () {},
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

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isBackendReady) {
      return const LoginPage();
    }
    return BlocBuilder<ConnectivityCubit, ConnectivityState>(
      buildWhen: (previous, current) => previous.isOnline != current.isOnline,
      builder: (context, connectivityState) {
        return StreamBuilder<AuthState>(
          stream: AuthService.authStateChanges,
          builder: (context, authSnapshot) {
            final session = authSnapshot.data?.session ??
                Supabase.instance.client.auth.currentSession;
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
