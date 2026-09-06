import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../data/models/chat_message_model.dart';
import '../../core/config/app_config.dart';

class GroqService {
  String get _model => AppConfig.groqModel;
  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxRetries = 3;
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

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
    final apiKey = AppConfig.groqApiKey.trim();
    if (apiKey.isEmpty || apiKey.contains('your_')) {
      throw Exception('Groq API key not configured. Please set GROQ_API_KEY in .env file.');
    }

    final recentHistory = _recentHistory(history, newMessage);
    final messages = [
      ...recentHistory
          .where((msg) => msg.text.isNotEmpty)
          .map((msg) => {
                'role': msg.isUser ? 'user' : 'assistant',
                'content': msg.text,
              }),
    ];

    messages.add({
      'role': 'user',
      'content': newMessage,
    });

    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      if (_isCancelled) break;
      try {
        final response = await http.post(
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
          throw Exception('Invalid response from Groq API');
        } else if (response.statusCode == 401) {
          throw Exception('Invalid Groq API key. Please check your GROQ_API_KEY in .env file.');
        } else if (response.statusCode == 429) {
          final waitTime = Duration(seconds: 2 << attempt);
          
          await Future.delayed(waitTime);
          continue;
        } else {
          throw Exception('Groq server error: ${response.statusCode}');
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
            throw Exception('Cannot connect to Groq. Your network may be blocking external APIs.');
          }
          final waitTime = Duration(seconds: 2 << attempt);
          
          await Future.delayed(waitTime);
          continue;
        }
        rethrow;
      }
    }

    throw Exception('Groq rate limit exceeded. Please wait a moment and try again.');
  }

  Stream<String> sendMessageStream({
    required List<ChatMessageModel> history,
    required String newMessage,
  }) async* {
    resetCancel();
    final apiKey = AppConfig.groqApiKey.trim();
    if (apiKey.isEmpty || apiKey.contains('your_')) {
      throw Exception('Groq API key not configured. Please set GROQ_API_KEY in .env file.');
    }

    final recentHistory = _recentHistory(history, newMessage);
    final messages = [
      ...recentHistory
          .where((msg) => msg.text.isNotEmpty)
          .map((msg) => {
                'role': msg.isUser ? 'user' : 'assistant',
                'content': msg.text,
              }),
    ];

    messages.add({
      'role': 'user',
      'content': newMessage,
    });

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
        throw Exception('Invalid Groq API key. Please check your GROQ_API_KEY in .env file.');
      }
      if (streamedResponse.statusCode == 429) {
        throw Exception('Groq rate limit exceeded. Please wait a moment and try again.');
      }
      if (streamedResponse.statusCode != 200) {
        throw Exception('Groq server error: ${streamedResponse.statusCode}');
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
              final delta = choices[0]['delta'] as Map?;
              if (delta != null) {
                final content = delta['content'] as String?;
                if (content != null) yield content;
              }
            }
          // ignore: empty_catches
          } catch (e) {}
        }
      }
    } on TimeoutException {
      throw Exception('Connection timed out. Check your internet connection.');
    } catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('HandshakeException')) {
        throw Exception('Cannot connect to Groq. Your network may be blocking external APIs.');
      }
      throw Exception('Groq service error: $e');
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }
}
