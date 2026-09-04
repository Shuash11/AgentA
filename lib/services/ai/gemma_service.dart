// ignore_for_file: empty_catches
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../../data/local/offline_model_dao.dart';
import '../../data/models/chat_message_model.dart';

class GemmaService extends ChangeNotifier {
  final OfflineModelDao _dao = OfflineModelDao();
  bool _isLoaded = false;
  bool _isCancelled = false;
  InferenceModel? _model;
  dynamic _chat;

  static const Duration _streamFlushInterval = Duration(milliseconds: 45);
  static const int _streamFlushChars = 8;
  static const String _systemInstruction = '''
You are AgentA, a helpful AI assistant inside this app.

Follow the user's latest message directly.
Do not introduce yourself unless the user asks who you are.
Do not start replies with "I'm AgentA" or repeat your identity.
If the user asks you to write, rewrite, summarize, plan, explain, code, or generate content, do that task directly.

Formatting rules:
- Use valid Markdown when it improves readability.
- Use fenced code blocks with a language name for code.
- Use bullets or numbered steps for lists.
- Do not leave raw formatting markers separated like "* *".
''';

  bool get isReady => _isLoaded && _model != null;

  void cancelGeneration() {
    _isCancelled = true;

    if (_chat != null) {
      try {
        _chat!.clearHistory();
      } catch (e) {}
    }
  }

  void resetCancel() {
    _isCancelled = false;
  }

  Future<void> loadInstalled() async {
    if (_isLoaded) {
      return;
    }

    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 1000,
        preferredBackend: PreferredBackend.cpu,
      );

      _chat = await _model!.createChat(
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        systemInstruction: _systemInstruction,
      );

      await _dao.setModelReady(modelType: 'gemma3-1b-it-int4');
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      _isLoaded = false;
      notifyListeners();
      _model = null;
      _chat = null;
      rethrow;
    }
  }

  Future<bool> ensureReady() async {
    if (isReady) {
      return true;
    }

    try {
      await loadInstalled();
      return isReady;
    } catch (e) {
      return false;
    }
  }

  String _buildUserPrompt(String newMessage) {
    return newMessage.trim();
  }

  List<ChatMessageModel> _getRecentHistory(
    List<ChatMessageModel> history, {
    required String currentMessage,
  }) {
    if (history.isEmpty) return [];

    final usableHistory = List<ChatMessageModel>.from(history);
    if (usableHistory.isNotEmpty &&
        usableHistory.last.isUser &&
        usableHistory.last.text.trim() == currentMessage.trim()) {
      usableHistory.removeLast();
    }

    final recent = usableHistory.length > 5
        ? usableHistory.sublist(usableHistory.length - 5)
        : usableHistory;
    return recent;
  }

  Future<String> sendMessage({
    required List<ChatMessageModel> history,
    required String newMessage,
  }) async {
    final ready = await ensureReady();

    if (!ready || _chat == null) {
      throw Exception('Gemma model not loaded');
    }

    try {
      final recentHistory = _getRecentHistory(
        history,
        currentMessage: newMessage,
      );
      if (recentHistory.isNotEmpty) {
        await _chat.clearHistory();
        for (final msg in recentHistory) {
          await _chat.addQueryChunk(
            Message.text(text: msg.text, isUser: msg.isUser),
          );
        }
      }

      final prompt = _buildUserPrompt(newMessage);
      await _chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      final response = await _chat.generateChatResponse();

      if (response is TextResponse) {
        return response.token;
      }
      return 'Unable to generate response.';
    } catch (e) {
      throw Exception('Gemma error: $e');
    }
  }

  Stream<String> sendMessageStream({
    required List<ChatMessageModel> history,
    required String newMessage,
  }) async* {
    resetCancel();

    if (_isCancelled) {
      return;
    }

    final ready = await ensureReady();

    if (!ready || _chat == null) {
      throw Exception('Gemma model not loaded');
    }

    if (_isCancelled) {
      return;
    }

    try {
      final recentHistory = _getRecentHistory(
        history,
        currentMessage: newMessage,
      );
      if (recentHistory.isNotEmpty) {
        await _chat.clearHistory();
        for (final msg in recentHistory) {
          await _chat.addQueryChunk(
            Message.text(text: msg.text, isUser: msg.isUser),
          );
        }
      }

      final prompt = _buildUserPrompt(newMessage);
      await _chat.addQueryChunk(Message.text(text: prompt, isUser: true));

      final flushTimer = Stopwatch()..start();
      final tokenBuffer = StringBuffer();
      await for (final response in _chat.generateChatResponseAsync()) {
        if (_isCancelled) {
          break;
        }
        if (response is TextResponse) {
          tokenBuffer.write(response.token);

          final shouldFlush = flushTimer.elapsed >= _streamFlushInterval ||
              tokenBuffer.length >= _streamFlushChars ||
              _endsAtNaturalBreak(response.token);

          if (shouldFlush) {
            yield tokenBuffer.toString();
            tokenBuffer.clear();
            flushTimer
              ..reset()
              ..start();
          }
        }

        if (_isCancelled) {
          break;
        }
      }
      if (tokenBuffer.isNotEmpty && !_isCancelled) {
        yield tokenBuffer.toString();
      }
    } catch (e) {
      if (_isCancelled) {
        return;
      }
      throw Exception('Gemma error: $e');
    }
  }

  bool _endsAtNaturalBreak(String token) {
    if (token.isEmpty) return false;
    final trimmed = token.trimRight();
    if (trimmed.isEmpty) return false;
    final last = trimmed[trimmed.length - 1];
    return last == '.' ||
        last == ',' ||
        last == ':' ||
        last == ';' ||
        last == '!' ||
        last == '?' ||
        last == '\n';
  }
}
