import 'dart:async';
// ignore_for_file: empty_catches
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../data/models/chat_message_model.dart';
import '../../core/config/app_config.dart';

class MiniMaxService {
  String get _model => AppConfig.minimaxModel;
  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxRetries = 3;
  static const String _systemPrompt =
      'You are an expert coding assistant. You specialize in writing clean, efficient, and well-documented code. '
      'When providing code examples, include comments explaining key sections. Always consider best practices, '
      'performance, and maintainability. Respond concisely and to the point.';

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
    final apiKey = AppConfig.minimaxApiKey.replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF]'), '').trim();
    if (apiKey.isEmpty || apiKey.contains('your_')) {
      throw Exception('MiniMax API key not configured. Please set MINIMAX_API_KEY in .env file.');
    }

    final recentHistory = _recentHistory(history, newMessage);
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ...recentHistory
          .where((msg) => msg.text.isNotEmpty)
          .map((msg) => {
                'role': msg.isUser ? 'user' : 'assistant',
                'content': msg.text,
              }),
    ];

    while (messages.length > 1 && messages[1]['role'] == 'assistant') {
      messages.removeAt(1);
    }

    messages.add({
      'role': 'user',
      'content': newMessage,
    });

    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      if (_isCancelled) break;
      try {
        final response = await http.post(
          Uri.parse(AppConfig.minimaxEndpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://agenta.app',
            'X-Title': 'AgentA AI Coach',
          },
          body: jsonEncode({
            'model': _model,
            'messages': messages,
            'temperature': 0.7,
            'max_tokens': 2048,
          }),
        ).timeout(_timeout);

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
          throw Exception('Invalid response from MiniMax API');
        } else if (response.statusCode == 401) {
          throw Exception('Invalid MiniMax API key. Please check your MINIMAX_API_KEY in .env file.');
        } else if (response.statusCode == 429) {
          final waitTime = Duration(seconds: 2 << attempt);
          
          await Future.delayed(waitTime);
          continue;
        } else {
          throw Exception('MiniMax server error: ${response.statusCode}');
        }
      } on TimeoutException {
        if (attempt == _maxRetries - 1) {
          throw Exception('Connection timed out. Check your internet connection.');
        }
        final waitTime = Duration(seconds: 2 << attempt);
        
        await Future.delayed(waitTime);
      } catch (e) {
        if (e.toString().contains('SocketException') || e.toString().contains('HandshakeException')) {
          if (attempt == _maxRetries - 1) {
            throw Exception('Cannot connect to MiniMax. Your network may be blocking external APIs.');
          }
          final waitTime = Duration(seconds: 2 << attempt);
          
          await Future.delayed(waitTime);
          continue;
        }
        rethrow;
      }
    }

    throw Exception('MiniMax rate limit exceeded. Please wait a moment and try again.');
  }

  Stream<String> sendMessageStream({
    required List<ChatMessageModel> history,
    required String newMessage,
  }) async* {
    resetCancel();
    final apiKey = AppConfig.minimaxApiKey.replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF]'), '').trim();
    if (apiKey.isEmpty || apiKey.contains('your_')) {
      throw Exception('MiniMax API key not configured. Please set MINIMAX_API_KEY in .env file.');
    }

    final recentHistory = _recentHistory(history, newMessage);
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ...recentHistory
          .where((msg) => msg.text.isNotEmpty)
          .map((msg) => {
                'role': msg.isUser ? 'user' : 'assistant',
                'content': msg.text,
              }),
    ];

    while (messages.length > 1 && messages[1]['role'] == 'assistant') {
      messages.removeAt(1);
    }

    messages.add({
      'role': 'user',
      'content': newMessage,
    });

    final client = http.Client();
    _activeClient = client;
    try {
      final request = http.Request('POST', Uri.parse(AppConfig.minimaxEndpoint));
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.headers['Content-Type'] = 'application/json';
      request.headers['HTTP-Referer'] = 'https://agenta.app';
      request.headers['X-Title'] = 'AgentA AI Coach';
      request.body = jsonEncode({
        'model': _model,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 2048,
        'stream': true,
      });

      final streamedResponse = await client.send(request).timeout(_timeout);

      if (streamedResponse.statusCode == 401) {
        throw Exception('Invalid MiniMax API key. Please check your MINIMAX_API_KEY in .env file.');
      }
      if (streamedResponse.statusCode == 429) {
        throw Exception('MiniMax rate limit exceeded. Please wait a moment and try again.');
      }
      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception('MiniMax server error: ${streamedResponse.statusCode} - $errorBody');
      }

      String buffer = '';
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
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
              final firstChoice = choices[0] as Map?;
              if (firstChoice != null) {
                final delta = firstChoice['delta'] as Map?;
                if (delta != null) {
                  final content = delta['content'] as String?;
                  if (content != null) yield content;
                }
              }
            }
          } catch (e) {}
        }
      }
    } on TimeoutException {
      throw Exception('Connection timed out. Check your internet connection.');
    } catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('HandshakeException')) {
        throw Exception('Cannot connect to MiniMax. Your network may be blocking external APIs.');
      }
      throw Exception('MiniMax service error: $e');
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }
}
