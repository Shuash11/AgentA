import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../data/models/chat_message_model.dart';
import '../../core/config/app_config.dart';

class GroqService {
  String get _model => AppConfig.groqModel;
  static const Duration _timeout = Duration(seconds: 30);
  // Shared persona + English rule (Bug 1): allam-2-7b is Arabic-first
  // bilingual, so a system message is the only thing enforcing English.
  static const String _systemPrompt =
      'You are AgentA, a helpful AI assistant inside this app. '
      "Answer the user's latest message directly and concisely. "
      'Use valid Markdown when it improves readability. '
      '${AppConfig.aiEnglishRule}';
  static const int _maxRetries = 3;
  // L19: SDK user-agent — never spoof a browser.
  static const String _userAgent = 'AgentA/1.0.0 (Flutter; Groq)';
  // L20: malformed SSE chunks are counted + logged; too many triggers a
  // partial-response warning instead of silently dropping data.
  static const int _malformedChunkWarnThreshold = 10;
  int _malformedChunks = 0;

  /// Regression/test hook for L20.
  @visibleForTesting
  int get malformedChunkCountForTest => _malformedChunks;

  Duration _retryDelay(int attempt, {String? retryAfter}) {
    // L19: honor server Retry-After (seconds or HTTP date) on 429.
    if (retryAfter != null && retryAfter.isNotEmpty) {
      final secs = int.tryParse(retryAfter.trim());
      if (secs != null && secs >= 0 && secs <= 300) {
        return Duration(seconds: secs);
      }
      try {
        final date = HttpDate.parse(retryAfter.trim());
        final diff = date.difference(DateTime.now().toUtc());
        if (!diff.isNegative && diff.inSeconds <= 300) return diff;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[GroqService] unparseable Retry-After "$retryAfter" — using backoff: $e',
          );
        }
      }
    }
    return Duration(seconds: 2 << attempt);
  }

  void _noteMalformedChunk(String context, Object e, String raw) {
    _malformedChunks++;
    final preview = raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
    debugPrint(
      '[GroqService] malformed SSE chunk #$context '
      '($_malformedChunks total): $e | raw: $preview',
    );
    if (_malformedChunks == _malformedChunkWarnThreshold) {
      debugPrint(
        '[GroqService] WARNING: $_malformedChunkWarnThreshold+ '
        'malformed chunks — response may be partial',
      );
    }
  }

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

  List<ChatMessageModel> _recentHistory(
    List<ChatMessageModel> history,
    String newMessage,
  ) {
    final usableHistory = List<ChatMessageModel>.from(history);
    if (usableHistory.isNotEmpty &&
        usableHistory.last.isUser &&
        usableHistory.last.text.trim() == newMessage.trim()) {
      usableHistory.removeLast();
    }

    return usableHistory.length > 20
        ? usableHistory.sublist(usableHistory.length - 20)
        : usableHistory;
  }

  Future<String> sendMessage({
    required List<ChatMessageModel> history,
    required String newMessage,
  }) async {
    resetCancel();
    final apiKey = AppConfig.groqApiKey.trim();
    if (apiKey.isEmpty || apiKey.contains('your_')) {
      throw Exception(
        'Groq API key not configured. Please set GROQ_API_KEY in .env file.',
      );
    }

    final recentHistory = _recentHistory(history, newMessage);
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ...recentHistory
          .where((msg) => msg.text.isNotEmpty)
          .map(
            (msg) => {
              'role': msg.isUser ? 'user' : 'assistant',
              'content': msg.text,
            },
          ),
    ];

    messages.add({'role': 'user', 'content': newMessage});

    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      if (_isCancelled) break;
      try {
        final response = await http
            .post(
              Uri.parse(AppConfig.groqEndpoint),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
                'User-Agent': _userAgent,
              },
              body: jsonEncode({
                'model': _model,
                'messages': messages,
                'temperature': 0.7,
                'max_tokens': 2048,
              }),
            )
            .timeout(_timeout);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final choices = data['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final message = choices[0]['message'] as Map?;
            if (message != null) {
              final content = message['content'] as String?;
              if (content != null) return content;
            }
          }
          throw Exception('Invalid response from Groq API');
        } else if (response.statusCode == 401) {
          throw Exception(
            'Invalid Groq API key. Please check your GROQ_API_KEY in .env file.',
          );
        } else if (response.statusCode == 429) {
          // L19: honor the server's Retry-After hint when present,
          // fall back to exponential backoff.
          final waitTime = _retryDelay(
            attempt,
            retryAfter: response.headers['retry-after'],
          );
          await Future.delayed(waitTime);
          continue;
        } else {
          throw Exception('Groq server error: ${response.statusCode}');
        }
      } on TimeoutException {
        if (attempt == _maxRetries - 1) {
          throw Exception(
            'Connection timed out. Check your internet connection.',
          );
        }
        final waitTime = Duration(seconds: 2 << attempt);

        await Future.delayed(waitTime);
      } catch (e) {
        if (e.toString().contains('SocketException') ||
            e.toString().contains('HandshakeException')) {
          if (attempt == _maxRetries - 1) {
            throw Exception(
              'Cannot connect to Groq. Your network may be blocking external APIs.',
            );
          }
          final waitTime = Duration(seconds: 2 << attempt);

          await Future.delayed(waitTime);
          continue;
        }
        rethrow;
      }
    }

    throw Exception(
      'Groq rate limit exceeded. Please wait a moment and try again.',
    );
  }

  Stream<String> sendMessageStream({
    required List<ChatMessageModel> history,
    required String newMessage,
  }) async* {
    resetCancel();
    final apiKey = AppConfig.groqApiKey.trim();
    if (apiKey.isEmpty || apiKey.contains('your_')) {
      throw Exception(
        'Groq API key not configured. Please set GROQ_API_KEY in .env file.',
      );
    }

    final recentHistory = _recentHistory(history, newMessage);
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ...recentHistory
          .where((msg) => msg.text.isNotEmpty)
          .map(
            (msg) => {
              'role': msg.isUser ? 'user' : 'assistant',
              'content': msg.text,
            },
          ),
    ];

    messages.add({'role': 'user', 'content': newMessage});

    final client = http.Client();
    _activeClient = client;
    try {
      final request = http.Request('POST', Uri.parse(AppConfig.groqEndpoint));
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.headers['Content-Type'] = 'application/json';
      request.headers['User-Agent'] = _userAgent;
      request.body = jsonEncode({
        'model': _model,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 2048,
        'stream': true,
      });

      final streamedResponse = await client.send(request).timeout(_timeout);

      if (streamedResponse.statusCode == 401) {
        throw Exception(
          'Invalid Groq API key. Please check your GROQ_API_KEY in .env file.',
        );
      }
      if (streamedResponse.statusCode == 429) {
        throw Exception(
          'Groq rate limit exceeded. Please wait a moment and try again.',
        );
      }
      if (streamedResponse.statusCode != 200) {
        throw Exception('Groq server error: ${streamedResponse.statusCode}');
      }

      String buffer = '';
      await for (final chunk in streamedResponse.stream.transform(
        utf8.decoder,
      )) {
        if (_isCancelled) break;
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data.isEmpty || data == '[DONE]') continue;
          try {
            final json = jsonDecode(data);
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map?;
              if (delta != null) {
                final content = delta['content'] as String?;
                if (content != null) yield content;
              }
            }
            // L20: malformed SSE chunks are counted + logged via the shared
            // helper (threshold warning after repeated failures) instead of
            // being silently dropped.
          } catch (e) {
            _noteMalformedChunk('stream', e, data);
          }
        }
      }
    } on TimeoutException {
      throw Exception('Connection timed out. Check your internet connection.');
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('HandshakeException')) {
        throw Exception(
          'Cannot connect to Groq. Your network may be blocking external APIs.',
        );
      }
      throw Exception('Groq service error: $e');
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }
}
