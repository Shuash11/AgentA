import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static Future<void> init() async {
    await dotenv.load(fileName: '.env');
  }

  static String get groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';
  static String get minimaxApiKey => dotenv.env['MINIMAX_API_KEY'] ?? '';
  static String get kaggleUsername => dotenv.env['KAGGLE_USERNAME'] ?? '';
  static String get kaggleKey => dotenv.env['KAGGLE_KEY'] ?? '';

  static const String groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String minimaxEndpoint = 'https://openrouter.ai/api/v1/chat/completions';

  static const String groqModel = 'llama-3.3-70b-versatile';
  static const String minimaxModel = 'minimax/minimax-m2.5:free';

  static String get gemmaModelUrl => dotenv.env['GEMMA_MODEL_URL'] ?? '';
  static const String gemmaModelFilename = 'gemma-offline.task';

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabasePublishableKey =>
      dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';
  static String get googleServerClientId =>
      dotenv.env['GOOGLE_SERVER_CLIENT_ID'] ?? '';

  static bool get hasValidApiKeys =>
      !groqApiKey.contains('your_') &&
      groqApiKey.isNotEmpty &&
      !minimaxApiKey.contains('your_') &&
      minimaxApiKey.isNotEmpty;
}