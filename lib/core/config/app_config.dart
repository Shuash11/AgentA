import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // C1: build-time --dart-define is the source of truth in release;
  // `.env` (dotenv) is a local-dev fallback only and is never bundled
  // as a Flutter asset (see pubspec.yaml) nor committed (see .gitignore).
  static String _withFallback(String defined, String key) {
    if (defined.isNotEmpty) return defined;
    try {
      return dotenv.env[key] ?? '';
    } catch (_) {
      return '';
    }
  }

  // NOTE: String.fromEnvironment requires a literal key (compile-time),
  // so each secret gets its own const + dotenv fallback (dev only).
  static const _dGroq = String.fromEnvironment('GROQ_API_KEY');
  static const _dHf = String.fromEnvironment('HF_TOKEN');
  static const _dGemmaUrl = String.fromEnvironment('GEMMA_MODEL_URL');
  static const _dForegroundDownload =
      String.fromEnvironment('FOREGROUND_DOWNLOAD');
  static const _dSupaUrl = String.fromEnvironment('SUPABASE_URL');
  static const _dSupaKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const _dGoogleId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static Future<void> init() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Missing .env in release/CI is expected — dart-define covers it.
    }
  }

  static String get groqApiKey => _withFallback(_dGroq, 'GROQ_API_KEY').trim();
  static String get hfToken => _withFallback(_dHf, 'HF_TOKEN').trim();

  static const String groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String hfImageModel =
      'stabilityai/stable-diffusion-3-medium-diffusers';
  static String get hfImageEndpoint =>
      'https://router.huggingface.co/hf-inference/models/$hfImageModel';

  /// GitHub Releases "latest" endpoint for the update-check engine
  /// (lib/services/update/). Public URL (repo is public), not a secret.
  static const String githubLatestReleaseUrl =
      'https://api.github.com/repos/Shuash11/AgentA/releases/latest';

  static const String groqModel = 'allam-2-7b';

  /// Shared English-enforcing rule reused across every AI persona prompt
  /// (Groq / Gemma) so all chat paths always respond in English.
  static const String aiEnglishRule =
      'IMPORTANT: Always respond ONLY in English, regardless of the language '
      'the user writes in. Never reply in any other language.';

  static String get gemmaModelUrl => _withFallback(_dGemmaUrl, 'GEMMA_MODEL_URL').trim();
  static const String gemmaModelFilename = 'gemma-offline.task';

  /// Foreground-service experiment override for the offline model download.
  /// Env `FOREGROUND_DOWNLOAD`, default true when unset or unrecognised.
  /// Flip to 'false' (via --dart-define or .env, no code change) as an
  /// immediate workaround if the foreground path fails on a device.
  static bool get foregroundDownload {
    final test = _foregroundDownloadOverrideForTest;
    if (test != null) return test;
    final raw =
        _withFallback(_dForegroundDownload, 'FOREGROUND_DOWNLOAD').trim();
    return _parseForegroundDownload(raw);
  }

  static bool _parseForegroundDownload(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    if (normalized == 'false') return false;
    if (normalized == 'true') return true;
    return true;
  }

  // Test-only override backing field (setter below is the visible entry).
  static bool? _foregroundDownloadOverrideForTest;

  /// Test-only override for [foregroundDownload]; null restores env behavior.
  @visibleForTesting
  static set foregroundDownloadOverrideForTest(bool? value) {
    _foregroundDownloadOverrideForTest = value;
  }

  /// Test-only entry point for the 'true'/'false' parsing (case-insensitive,
  /// default true).
  @visibleForTesting
  static bool parseForegroundDownloadForTest(String raw) =>
      _parseForegroundDownload(raw);

  static String get supabaseUrl => _withFallback(_dSupaUrl, 'SUPABASE_URL').trim();
  static String get supabasePublishableKey =>
      _withFallback(_dSupaKey, 'SUPABASE_PUBLISHABLE_KEY').trim();

  /// Trimmed Web Client ID — whitespace / newline stripped per reviewer finding #1.
  static String get googleServerClientId =>
      _withFallback(_dGoogleId, 'GOOGLE_SERVER_CLIENT_ID').trim();

  static const String _googleSuffix = '.apps.googleusercontent.com';

  static bool _googleConfigured = false;
  static bool get googleConfigured => _googleConfigured;

  static String? _googleConfigError;
  static String? get googleConfigError => _googleConfigError;

  /// Last 8 chars only — never log full ID.
  static String get googleIdSuffixForLog {
    final id = googleServerClientId;
    if (id.isEmpty) return '(empty)';
    if (id.length <= 8) return '***';
    return id.substring(id.length - 8);
  }

  static String _idSuffix(String id) {
    if (id.isEmpty) return '(empty)';
    if (id.length <= 8) return '***';
    return id.substring(id.length - 8);
  }

  static String? _validateGoogleId(String trimmed) {
    if (trimmed.isEmpty) {
      return 'GOOGLE_SERVER_CLIENT_ID is missing or empty in .env. '
          'Add your Web Client ID from Google Cloud Console > Credentials > OAuth 2.0 Client IDs > Web application. '
          'It must end with $_googleSuffix';
    }
    if (!trimmed.endsWith(_googleSuffix)) {
      final tail = trimmed.length <= 24
          ? trimmed
          : trimmed.substring(trimmed.length - 24);
      return 'GOOGLE_SERVER_CLIENT_ID is malformed: must end with $_googleSuffix. '
          'Got tail "...$tail". Check you copied the Web Client ID (not Android Client ID).';
    }
    return null;
  }

  /// Validates GOOGLE_SERVER_CLIENT_ID at startup.
  /// Sets [googleConfigured] flag and logs only suffix.
  /// Returns true if valid; false otherwise (app still boots — UI can show banner).
  static bool validateGoogleConfigAtStartup() {
    final trimmed = googleServerClientId;
    final err = _validateGoogleId(trimmed);
    if (err != null) {
      _googleConfigured = false;
      _googleConfigError = err;
      if (kDebugMode) {
        debugPrint(
            '[AppConfig] Google config INVALID: $err | idSuffix: ${_idSuffix(trimmed)}');
      }
      return false;
    }
    _googleConfigured = true;
    _googleConfigError = null;
    if (kDebugMode) {
      debugPrint(
          '[AppConfig] Google config OK | idSuffix: ...${_idSuffix(trimmed)} | length:${trimmed.length}');
    }
    return true;
  }

  /// Throwing validator for use before initialize() — fail-fast with actionable message.
  static void validateGoogleIdOrThrow() {
    final trimmed = googleServerClientId;
    final err = _validateGoogleId(trimmed);
    if (err != null) {
      if (kDebugMode) {
        debugPrint(
            '[AppConfig] validateGoogleIdOrThrow FAILED: $err | idSuffix: ${_idSuffix(trimmed)}');
      }
      throw FormatException(err);
    }
  }

  /// Called when env file changes or on logout to allow re-init.
  static void notifyGoogleConfigChanged() {
    _googleConfigured = false;
    _googleConfigError = null;
    if (kDebugMode) {
      debugPrint('[AppConfig] Google config changed — flag reset');
    }
  }

  static bool get hasValidApiKeys =>
      groqApiKey.isNotEmpty && !groqApiKey.contains('your_');

  /// Logs only lengths (never values) for trimmed env — satisfies M21.
  static void logTrimmedLengths() {
    if (!kDebugMode) return;
    debugPrint(
        '[AppConfig] env lengths — SUPABASE_URL:${supabaseUrl.length} '
        'SUPABASE_PUBLISHABLE_KEY:${supabasePublishableKey.length} '
        'GOOGLE_SERVER_CLIENT_ID:${googleServerClientId.length} '
        'GROQ_API_KEY:${groqApiKey.length} '
        'HF_TOKEN:${hfToken.length}');
  }

  /// Returns lengths map for badge/debug UI without exposing secrets.
  static Map<String, int> get envLengths => {
        'SUPABASE_URL': supabaseUrl.length,
        'SUPABASE_PUBLISHABLE_KEY': supabasePublishableKey.length,
        'GOOGLE_SERVER_CLIENT_ID': googleServerClientId.length,
      };
}
