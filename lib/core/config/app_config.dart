import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static Future<void> init() async {
    await dotenv.load(fileName: '.env');
  }

  static String get groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';
  static String get minimaxApiKey => dotenv.env['MINIMAX_API_KEY'] ?? '';
  static String get kaggleUsername => dotenv.env['KAGGLE_USERNAME'] ?? '';
  static String get kaggleKey => dotenv.env['KAGGLE_KEY'] ?? '';
  static String get hfToken => dotenv.env['HF_TOKEN'] ?? '';

  static const String groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String minimaxEndpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const String hfImageModel =
      'stabilityai/stable-diffusion-3-medium-diffusers';
  static String get hfImageEndpoint =>
      'https://router.huggingface.co/hf-inference/models/$hfImageModel';

  static const String groqModel = 'allam-2-7b';
  static const String minimaxModel = 'minimax/minimax-m2.7:free';

  static String get gemmaModelUrl => dotenv.env['GEMMA_MODEL_URL'] ?? '';
  static const String gemmaModelFilename = 'gemma-offline.task';

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabasePublishableKey =>
      dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';

  /// Trimmed Web Client ID — whitespace / newline stripped per reviewer finding #1.
  static String get googleServerClientId =>
      (dotenv.env['GOOGLE_SERVER_CLIENT_ID'] ?? '').trim();

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
      (groqApiKey.isNotEmpty && !groqApiKey.contains('your_')) ||
      (minimaxApiKey.isNotEmpty && !minimaxApiKey.contains('your_'));
}
