import 'package:flutter/foundation.dart';

class AppConfig {
  // C1: build-time --dart-define is the ONLY config source — release and
  // local dev alike (see .env.example for the key reference). The former
  // `.env` fallback was dead code: the removed package loaded Flutter
  // assets only (never a root `.env`), and no `.env` asset is declared
  // (the CI guard forbids bundling one), so it always threw and was
  // swallowed. Removed in cycle 15. `.env` stays git-ignored; never read.
  static String _withFallback(String defined) => defined.trim();

  // NOTE: String.fromEnvironment requires a literal key (compile-time),
  // so each secret gets its own const.
  static const _dGroq = String.fromEnvironment('GROQ_API_KEY');
  static const _dHf = String.fromEnvironment('HF_TOKEN');
  static const _dGemmaUrl = String.fromEnvironment('GEMMA_MODEL_URL');
  static const _dForegroundDownload = String.fromEnvironment(
    'FOREGROUND_DOWNLOAD',
  );
  static const _dSupaUrl = String.fromEnvironment('SUPABASE_URL');
  static const _dSupaKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const _dGoogleId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static String get groqApiKey => _withFallback(_dGroq);
  static String get hfToken => _withFallback(_dHf);

  static const String groqEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';
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

  static String get gemmaModelUrl => _withFallback(_dGemmaUrl);
  static const String gemmaModelFilename = 'gemma-offline.task';

  /// Foreground-service experiment override for the offline model download.
  /// Env `FOREGROUND_DOWNLOAD`, default true when unset or unrecognised.
  /// Flip to 'false' (via --dart-define, no code change) as an
  /// immediate workaround if the foreground path fails on a device.
  static bool get foregroundDownload {
    final test = _foregroundDownloadOverrideForTest;
    if (test != null) return test;
    final raw = _withFallback(_dForegroundDownload);
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

  static String get supabaseUrl => _withFallback(_dSupaUrl);
  static String get supabasePublishableKey => _withFallback(_dSupaKey);

  /// Trimmed Web Client ID — whitespace / newline stripped per reviewer finding #1.
  static String get googleServerClientId => _withFallback(_dGoogleId);

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
      return 'GOOGLE_SERVER_CLIENT_ID is missing or empty (pass it via --dart-define). '
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
          '[AppConfig] Google config INVALID: $err | idSuffix: ${_idSuffix(trimmed)}',
        );
      }
      return false;
    }
    _googleConfigured = true;
    _googleConfigError = null;
    if (kDebugMode) {
      debugPrint(
        '[AppConfig] Google config OK | idSuffix: ...${_idSuffix(trimmed)} | length:${trimmed.length}',
      );
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
          '[AppConfig] validateGoogleIdOrThrow FAILED: $err | idSuffix: ${_idSuffix(trimmed)}',
        );
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

  /// Returns lengths map for badge/debug UI without exposing secrets.
  static Map<String, int> get envLengths => {
    'SUPABASE_URL': supabaseUrl.length,
    'SUPABASE_PUBLISHABLE_KEY': supabasePublishableKey.length,
    'GOOGLE_SERVER_CLIENT_ID': googleServerClientId.length,
  };
}
