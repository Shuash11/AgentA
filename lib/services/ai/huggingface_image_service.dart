import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/config/app_config.dart';

class HuggingFaceImageService {
  static const Duration _timeout = Duration(seconds: 120);
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 10; Mobile) AgentA/1.0';

  bool _isCancelled = false;
  http.Client? _activeClient;

  void cancelGeneration() {
    _isCancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  void resetCancel() {
    _isCancelled = false;
  }

  bool get isConfigured {
    final token = AppConfig.hfToken.trim();
    return token.isNotEmpty && !token.contains('your_');
  }

  Future<String> generateImageFile({
    required String prompt,
    int? width,
    int? height,
  }) async {
    resetCancel();
    final token = AppConfig.hfToken.trim();
    if (!isConfigured) {
      throw Exception(
        'HuggingFace API token not configured. Please set HF_TOKEN in .env file.',
      );
    }
    if (prompt.trim().isEmpty) {
      throw Exception('Prompt cannot be empty');
    }

    final w = (width ?? 1024).clamp(256, 2048);
    final h = (height ?? 1024).clamp(256, 2048);

    final client = http.Client();
    _activeClient = client;
    try {
      for (int attempt = 0; attempt < 2; attempt++) {
        if (_isCancelled) break;
        http.Response response;
        try {
          response = await client
              .post(
                Uri.parse(AppConfig.hfImageEndpoint),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                  'User-Agent': _userAgent,
                },
                body: jsonEncode({
                  'inputs': prompt.trim(),
                  'parameters': {'width': w, 'height': h},
                }),
              )
              .timeout(_timeout);
        } on TimeoutException {
          if (attempt == 1) {
            throw Exception(
              'HuggingFace request timed out. The model may be warming up, try again.',
            );
          }
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }
        if (response.statusCode == 200) {
          return await _saveBytes(response.bodyBytes);
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception(
            'Invalid HuggingFace token. Please check your HF_TOKEN in .env file.',
          );
        } else if (response.statusCode == 402) {
          throw Exception(
            'HuggingFace free credits exhausted for this month. Try again later or use Pollinations.',
          );
        } else if (response.statusCode == 429) {
          if (attempt == 1) {
            throw Exception(
              'HuggingFace rate limit reached. Wait a moment and try again.',
            );
          }
          await Future.delayed(const Duration(seconds: 8));
          continue;
        } else if (response.statusCode == 503) {
          if (attempt == 1) {
            throw Exception(
              'HuggingFace model is warming up. Try again in a moment.',
            );
          }
          await Future.delayed(const Duration(seconds: 15));
          continue;
        } else {
          throw Exception(
            'HuggingFace image error: ${response.statusCode} ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}',
          );
        }
      }
    } on http.ClientException {
      if (_isCancelled) throw Exception('Image generation cancelled.');
      throw Exception(
        'Cannot reach HuggingFace. Check your internet connection.',
      );
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
    throw Exception('HuggingFace image generation failed. Please try again.');
  }

  Future<String> _saveBytes(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/hf_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
