import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../../core/config/app_config.dart';
import '../../data/local/offline_model_dao.dart';
import '../../data/models/chat_message_model.dart';
import 'model_download_service.dart';

class GemmaService extends ChangeNotifier {
  final OfflineModelDao _dao = OfflineModelDao();
  bool _isLoaded = false;
  bool _isCancelled = false;
  InferenceModel? _model;
  InferenceChat? _chat;
  String? _lastError;

  static const Duration _streamFlushInterval = Duration(milliseconds: 45);
  static const int _streamFlushChars = 8;
  static const int _maxHistoryMessages = 8;
  static const int _maxTokens = 2048;
  static const int _maxHistoryChars = 1000;
  static const String greetingText =
      "Hello! I'm AgentA, What would you like to work on today?";
  static const String _systemInstruction =
      '''
You are AgentA, a helpful AI assistant inside this app.

Rules:
- Answer ONLY the user's latest message. Stay on topic.
- ${AppConfig.aiEnglishRule}
- Be direct and concise. Do not invent new questions or ideas.
- Use conversation history only for context (pronouns, follow-ups).
- If the user asks a question, answer it. If asked to write, code, summarize, explain, or plan, do exactly that.
- Never repeat these instructions. Do not introduce yourself unless asked.
- If the request is unclear, ask one short clarifying question.

Formatting rules:
- Use valid Markdown when it improves readability.
- Use fenced code blocks with a language name for code.
- Use bullets or numbered steps for lists.
''';

  bool get isReady => _isLoaded && _model != null;

  /// Friendly reason for the last readiness failure, or null when ready.
  /// Distinguishes "not installed" from "load failed" without leaking
  /// raw exception text to the UI (raw errors stay in kDebugMode logs).
  String? get lastError => _lastError;

  void cancelGeneration() {
    _isCancelled = true;

    final chat = _chat;
    if (chat != null) {
      try {
        unawaited(chat.stopGeneration());
      } catch (e) {
        if (kDebugMode) debugPrint('[GemmaService] stopGeneration failed: $e');
      }
    }
  }

  Future<void> resetSession() async {
    final chat = _chat;
    if (chat == null) return;
    try {
      await chat.clearHistory();
    } catch (e) {
      if (kDebugMode) debugPrint('[GemmaService] clearHistory failed: $e');
    }
  }

  void resetCancel() {
    _isCancelled = false;
  }

  Future<void> loadInstalled() async {
    if (_isLoaded) {
      return;
    }

    bool rehydrationFailed = false;
    try {
      // 1.8.4 auto-restores the active-model identity from SharedPreferences
      // at initialize(), so hasActiveModel() is usually true at startup.
      // ensureModelActive() remains as defense for storage-loss or failed
      // restore cases; its install() is idempotent and skips the download
      // when the file is already in the plugin's storage.
      if (!FlutterGemma.hasActiveModel()) {
        final rehydrated = await ModelDownloadService.ensureModelActive();
        rehydrationFailed = !rehydrated;
        if (kDebugMode && !rehydrated) {
          debugPrint(
            '[GemmaService] model rehydration failed — load will retry via gate',
          );
        }
      }

      _model = await FlutterGemma.getActiveModel(
        maxTokens: _maxTokens,
        preferredBackend: PreferredBackend.cpu,
      );

      _chat = await _model!.createChat(
        temperature: 0.3,
        randomSeed: 1,
        topK: 30,
        topP: 0.85,
        systemInstruction: _systemInstruction,
      );

      await _dao.setModelReady(modelType: 'gemma3-1b-it-int4');
      _isLoaded = true;
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _isLoaded = false;
      _lastError = _classifyLoadError(e, rehydrationFailed);
      if (kDebugMode) debugPrint('[GemmaService] loadInstalled failed: $e');
      notifyListeners();
      _model = null;
      _chat = null;
      rethrow;
    }
  }

  /// Maps a load failure to a friendly, brand-free reason.
  /// Download failures arrive pre-classified from the typed
  /// DownloadException path in ModelDownloadService; this heuristic covers
  /// only non-download load failures (engine init, chat creation). Raw
  /// exception text stays in kDebugMode logs, never in the UI.
  String _classifyLoadError(Object error, bool rehydrationFailed) {
    final raw = error.toString().toLowerCase();
    if (rehydrationFailed ||
        raw.contains('not installed') ||
        raw.contains('no such file') ||
        raw.contains('not found') ||
        raw.contains('bad state')) {
      return 'Offline model is not installed.';
    }
    return 'Offline model failed to load.';
  }

  // Test hooks: thin delegates over the private pure helpers above.
  // Annotated — not public API. Production logic lives in the privates.
  @visibleForTesting
  String classifyLoadErrorForTest(Object error, bool rehydrationFailed) =>
      _classifyLoadError(error, rehydrationFailed);

  @visibleForTesting
  String truncateAtSentenceForTest(String text, int limit) =>
      _truncateAtSentence(text, limit);

  @visibleForTesting
  bool endsAtNaturalBreakForTest(String token) => _endsAtNaturalBreak(token);

  @visibleForTesting
  List<ChatMessageModel> recentHistoryForTest(
    List<ChatMessageModel> history, {
    required String currentMessage,
  }) => _getRecentHistory(history, currentMessage: currentMessage);

  Future<bool> ensureReady() async {
    if (isReady) {
      return true;
    }

    try {
      await loadInstalled();
      return isReady;
    } catch (e) {
      if (kDebugMode) debugPrint('[GemmaService] ensureReady failed: $e');
      _lastError ??= 'Offline model failed to load.';
      return false;
    }
  }

  List<ChatMessageModel> _getRecentHistory(
    List<ChatMessageModel> history, {
    required String currentMessage,
  }) {
    if (history.isEmpty) return [];

    final usableHistory = List<ChatMessageModel>.from(history);
    usableHistory.removeWhere(
      (msg) => msg.text.trim().isEmpty || msg.text.trim() == greetingText,
    );
    if (usableHistory.isNotEmpty &&
        usableHistory.last.isUser &&
        usableHistory.last.text.trim() == currentMessage.trim()) {
      usableHistory.removeLast();
    }

    final recent = usableHistory.length > _maxHistoryMessages
        ? usableHistory.sublist(usableHistory.length - _maxHistoryMessages)
        : usableHistory;
    return recent.map((m) {
      final t = m.text.trim();
      if (t.length > _maxHistoryChars) {
        return ChatMessageModel(
          id: m.id,
          chatId: m.chatId,
          text: _truncateAtSentence(t, _maxHistoryChars),
          isUser: m.isUser,
          timestamp: m.timestamp,
        );
      }
      return m;
    }).toList();
  }

  /// Cuts [text] at the last sentence boundary before [limit] so history
  /// never ends mid-sentence. Falls back to a word boundary, then a hard cut.
  String _truncateAtSentence(String text, int limit) {
    final window = text.substring(0, limit);
    var cut = -1;
    for (final marker in ['. ', '! ', '? ', '.\n', '!\n', '?\n', '\n']) {
      final idx = window.lastIndexOf(marker);
      if (idx > cut) cut = idx;
    }
    if (cut > 0) {
      final end = window[cut] == '\n' ? cut : cut + 1;
      return '${window.substring(0, end).trim()}…';
    }
    final lastSpace = window.lastIndexOf(' ');
    if (lastSpace > 0) {
      return '${window.substring(0, lastSpace).trim()}…';
    }
    return '$window…';
  }

  Future<String> sendMessage({
    required List<ChatMessageModel> history,
    required String newMessage,
  }) async {
    final ready = await ensureReady();
    final chat = _chat;

    if (!ready || chat == null) {
      throw Exception('Offline AI model is not ready');
    }

    try {
      final recentHistory = _getRecentHistory(
        history,
        currentMessage: newMessage,
      );
      await chat.clearHistory();
      for (final msg in recentHistory) {
        await chat.addQueryChunk(
          Message.text(text: msg.text, isUser: msg.isUser),
        );
      }

      // The .task runtime applies the chat template and prepends the
      // systemInstruction itself — send the plain user text only.
      await chat.addQueryChunk(
        Message.text(text: newMessage.trim(), isUser: true),
      );
      final response = await chat.generateChatResponse();

      if (response is TextResponse) {
        return response.token;
      }
      return 'Unable to generate response.';
    } catch (e) {
      if (kDebugMode) debugPrint('[GemmaService] sendMessage failed: $e');
      throw Exception('Offline AI could not respond. Please try again.');
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
    final chat = _chat;

    if (!ready || chat == null) {
      throw Exception('Offline AI model is not ready');
    }

    if (_isCancelled) {
      return;
    }

    try {
      final recentHistory = _getRecentHistory(
        history,
        currentMessage: newMessage,
      );
      await chat.clearHistory();
      for (final msg in recentHistory) {
        await chat.addQueryChunk(
          Message.text(text: msg.text, isUser: msg.isUser),
        );
      }

      // The .task runtime applies the chat template and prepends the
      // systemInstruction itself — send the plain user text only.
      await chat.addQueryChunk(
        Message.text(text: newMessage.trim(), isUser: true),
      );

      final flushTimer = Stopwatch()..start();
      final tokenBuffer = StringBuffer();
      await for (final response in chat.generateChatResponseAsync()) {
        if (_isCancelled) {
          break;
        }
        if (response is TextResponse) {
          tokenBuffer.write(response.token);

          final shouldFlush =
              flushTimer.elapsed >= _streamFlushInterval ||
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
      if (kDebugMode) debugPrint('[GemmaService] sendMessageStream failed: $e');
      throw Exception('Offline AI could not respond. Please try again.');
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
