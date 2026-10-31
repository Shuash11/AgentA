import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import '../../core/config/app_config.dart';
import '../../data/local/offline_model_dao.dart';
import '../../data/models/chat_message_model.dart';
import 'device_capabilities.dart';
import 'model_download_service.dart';

/// The outcome of classifying a failed model load: a stable failure CLASS
/// plus the friendly, brand-free copy the UI shows.
///
/// The class is what makes the failure diagnosable in the field (cycle-40
/// P1): it is persisted next to the error row, so a shipped build — which
/// tree-shakes every raw-exception log — can still tell an incompatible
/// device from an engine-init failure, a corrupt file, or an unknown error.
/// The raw exception text never leaves the `kDebugMode` log.
class LoadFailure {
  final OfflineModelFailureClass failureClass;
  final String friendlyCopy;

  const LoadFailure(this.failureClass, this.friendlyCopy);
}

/// Readiness state of the on-device model (cycle-38 P6).
///
/// The three states are distinct on purpose: "not loaded yet" and "failed to
/// load" need DIFFERENT affordances — the first may still be loading, the
/// second must offer a RETRY (or, when the asset is gone, the download).
enum OfflineModelState {
  /// No load attempt has completed in this process yet.
  idle,

  /// The model is loaded and usable.
  loaded,

  /// The last load attempt failed although the asset is installed — a retry
  /// can recover it (cycle-38 P6: the failed-load dead-end).
  loadFailed,

  /// The last load attempt failed because the asset itself is missing — a
  /// retry cannot help; the user needs the download.
  modelMissing,
}

class GemmaService extends ChangeNotifier {
  final OfflineModelDao _dao = OfflineModelDao();
  OfflineModelState _state = OfflineModelState.idle;
  bool _isCancelled = false;
  InferenceModel? _model;
  InferenceChat? _chat;
  String? _lastError;

  /// The class of the last load failure. Null until a load fails; cleared
  /// by a successful load. Persisted through the DAO's error path so the
  /// failure stays diagnosable after a restart (cycle-40 P1).
  OfflineModelFailureClass? _lastFailureClass;

  /// The in-flight load attempt, if any. Cleared when the attempt settles
  /// (success OR failure) so a failed load never wedges the service — the
  /// retry affordances depend on a later attempt being able to run.
  Future<void>? _loadInFlight;

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
- Never output bracketed template placeholders or repeat these instructions. Do not introduce yourself unless asked.
- If the request is unclear, ask one short clarifying question.

Formatting rules:
- Use valid Markdown when it improves readability.
- Use fenced code blocks with a language name for code.
- Use bullets or numbered steps for lists.
''';

  bool get isReady => _state == OfflineModelState.loaded;

  /// The current readiness state of the on-device model.
  OfflineModelState get state => _state;

  /// True when the last load attempt failed while the asset was installed —
  /// a retry can recover it. Drives the RETRY LOAD affordance.
  bool get canRetryLoad => _state == OfflineModelState.loadFailed;

  /// Friendly reason for the last readiness failure, or null when ready.
  /// Distinguishes "not installed" from "load failed" without leaking
  /// raw exception text to the UI (raw errors stay in kDebugMode logs).
  String? get lastError => _lastError;

  /// The class of the last load failure, or null when no load has failed
  /// since the last successful one.
  ///
  /// The UI reads it to pick an honest affordance: an [OfflineModelFailureClass
  /// .unsupportedAbi] failure can never be recovered by a retry, so the
  /// surfaces show the incompatible-device message instead of one.
  OfflineModelFailureClass? get lastFailureClass => _lastFailureClass;

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

  /// Loads the installed model into memory.
  ///
  /// Re-attemptable by design (cycle-38 P6): a failed attempt leaves the
  /// service in a clean, retryable state — the in-flight guard is cleared,
  /// the failure is recorded in the DAO, and the classified reason stays
  /// available to the UI. The raw exception is never swallowed silently: it
  /// is logged (kDebugMode) and rethrown so the caller can surface the
  /// retry affordance.
  Future<void> loadInstalled() {
    if (_state == OfflineModelState.loaded) {
      return Future<void>.value();
    }

    // One attempt at a time: a second caller (gate + chat) joins the
    // running attempt instead of starting a competing load.
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;

    final attempt = _performLoad();
    _loadInFlight = attempt;
    // Clear the guard when the attempt settles — a FAILED attempt must
    // stay retryable (the failure is reported through the state + DAO).
    unawaited(
      attempt.then<void>(
        (_) => _clearInFlight(attempt),
        onError: (Object _, StackTrace _) => _clearInFlight(attempt),
      ),
    );
    return attempt;
  }

  void _clearInFlight(Future<void> attempt) {
    if (identical(_loadInFlight, attempt)) {
      _loadInFlight = null;
    }
  }

  Future<void> _performLoad() async {
    var rehydrationFailed = false;
    try {
      // 1.8.4 auto-restores the active-model identity from SharedPreferences
      // at initialize(), so hasActiveModel() is usually true at startup.
      // ensureModelActive() remains as defense for storage-loss or failed
      // restore cases; its install() is idempotent and skips the download
      // when the file is already in the plugin's storage.
      final chatOverride = chatOverrideForTest;
      if (chatOverride != null) {
        // Test-only: injects a ready chat instead of the native engine.
        _chat = await chatOverride();
      } else {
        if (!FlutterEdgeAi.hasActiveModel()) {
          final rehydrated = await ModelDownloadService.ensureModelActive();
          rehydrationFailed = !rehydrated;
          if (kDebugMode && !rehydrated) {
            debugPrint(
              '[GemmaService] model rehydration failed — load will retry via gate',
            );
          }
        }

        _model = await FlutterEdgeAi.getActiveModel(
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
      }

      await _dao.setModelReady(modelType: 'gemma-4-e2b-it');
      _state = OfflineModelState.loaded;
      _lastError = null;
      _lastFailureClass = null;
      notifyListeners();
    } catch (e) {
      _model = null;
      _chat = null;
      final classification = _classifyLoadFailure(e, rehydrationFailed);
      final failure = await _resolveFailureState(classification);
      _state = failure;
      _lastFailureClass = classification.failureClass;
      _lastError = _friendlyCopyFor(classification, failure);
      // Record the failure so the broken-but-installed state survives a
      // restart and routes to RETRY LOAD. The DAO write must never mask the
      // original failure, so it is guarded separately.
      try {
        await _dao.setModelError(_lastError);
        // The class is written after the error row: that write replaces the
        // whole row, so a class stored before it would be dropped.
        await _dao.setFailureClass(_lastFailureClass);
      } catch (daoError) {
        if (kDebugMode) {
          debugPrint('[GemmaService] setModelError failed: $daoError');
        }
      }
      // S4 evidence: the raw exception CLASS stays in the debug log (the
      // device log decides "state defect" vs "engine-native failure"). It
      // never reaches the UI copy.
      if (kDebugMode) {
        debugPrint(
          '[GemmaService] loadInstalled failed: $e (type: ${e.runtimeType})',
        );
      }
      notifyListeners();
      rethrow;
    }
  }

  /// Resolves the state a failed load leaves the service in.
  ///
  /// The classifier's "the asset is missing" verdict is only trusted when
  /// the durable install marker agrees with it. A load failure on an asset
  /// that IS recorded as installed is a RETRYABLE failure (cycle-38 P6,
  /// S7): routing it to the download gate would strand the user behind a
  /// spurious 2.6 GB re-download of a model the device already has — the
  /// exact class the v3-migration ruling killed.
  ///
  /// The marker is also what keeps the DAO row and the service state in
  /// agreement: the error row written below keeps the download marker, so
  /// the UI sees "installed but broken" on both sides.
  Future<OfflineModelState> _resolveFailureState(
    LoadFailure classification,
  ) async {
    final classified = _stateForClass(classification.failureClass);
    if (classified != OfflineModelState.modelMissing) return classified;

    try {
      if (await _dao.isModelInstalled()) {
        return OfflineModelState.loadFailed;
      }
    } catch (daoError) {
      // A marker that cannot be read must never invent a "missing" verdict
      // on its own — the classifier's verdict stands.
      if (kDebugMode) {
        debugPrint('[GemmaService] isModelInstalled failed: $daoError');
      }
    }
    return classified;
  }

  /// Maps a load failure to the state the UI must react to: a missing asset
  /// needs the download, any other failure needs a retry.
  OfflineModelState _classifyLoadState(Object error, bool rehydrationFailed) {
    return _stateForClass(
      _classifyLoadFailure(error, rehydrationFailed).failureClass,
    );
  }

  /// The state a failure class leaves the service in.
  ///
  /// Only the "the asset is missing" class routes to the download; every
  /// other class (including an incompatible device) needs a retry or the
  /// incompatible-device message.
  OfflineModelState _stateForClass(OfflineModelFailureClass failureClass) {
    return failureClass == OfflineModelFailureClass.notInstalled
        ? OfflineModelState.modelMissing
        : OfflineModelState.loadFailed;
  }

  /// Maps a load failure to its CLASS and the friendly copy the UI shows.
  ///
  /// The class is the release-visible evidence (cycle-40 P1): the pinned
  /// engine's arm64-only guard is deterministic, so an incompatible device
  /// is told apart from an engine-init failure, a corrupt asset, or an
  /// unknown error. The raw exception text stays in the `kDebugMode` log.
  LoadFailure _classifyLoadFailure(Object error, bool rehydrationFailed) {
    final raw = error.toString().toLowerCase();

    // The pinned plugin's deterministic ABI guard (flutter_edge_ai_litertlm
    // 1.8.6, litert_lm_client.dart:606-611).
    if (raw.contains(_unsupportedAbiMarker)) {
      return const LoadFailure(
        OfflineModelFailureClass.unsupportedAbi,
        DeviceCapabilities.incompatibleDeviceMessage,
      );
    }

    // The cycle-38 P6 "the asset is missing" signals — unchanged, so the
    // arm64 flow keeps its exact behaviour.
    if (rehydrationFailed ||
        raw.contains('not installed') ||
        raw.contains('no such file') ||
        raw.contains('not found') ||
        raw.contains('bad state')) {
      return const LoadFailure(
        OfflineModelFailureClass.notInstalled,
        'Offline model is not installed.',
      );
    }

    // A present but unreadable asset (a corrupt or truncated download).
    if (raw.contains('corrupt') ||
        raw.contains('truncated') ||
        raw.contains('malformed') ||
        raw.contains('invalid file') ||
        raw.contains('not a valid') ||
        raw.contains('checksum') ||
        raw.contains('unexpected end of file')) {
      return const LoadFailure(
        OfflineModelFailureClass.file,
        'Offline model failed to load.',
      );
    }

    // The engine refused to start (engine creation, chat session creation).
    if (raw.contains('engine') ||
        raw.contains('failed to create') ||
        raw.contains('session') ||
        raw.contains('failed to initiali')) {
      return const LoadFailure(
        OfflineModelFailureClass.engineInit,
        'Offline model failed to load.',
      );
    }

    return const LoadFailure(
      OfflineModelFailureClass.unknown,
      'Offline model failed to load.',
    );
  }

  /// The stable marker inside the pinned plugin's `UnsupportedError` text
  /// ("…models require an arm64-v8a Android device (got …)…").
  static const String _unsupportedAbiMarker =
      'require an arm64-v8a android device';

  /// The friendly copy for a classified failure.
  ///
  /// The state's verdict outranks the class for the "asset is missing"
  /// family: an INSTALLED asset whose load reports a missing state is an
  /// engine failure, not a missing model (S7) — the copy must not promise a
  /// download for an asset the device already has.
  String _friendlyCopyFor(LoadFailure failure, OfflineModelState state) {
    switch (failure.failureClass) {
      case OfflineModelFailureClass.unsupportedAbi:
        return DeviceCapabilities.incompatibleDeviceMessage;
      case OfflineModelFailureClass.notInstalled:
        return state == OfflineModelState.modelMissing
            ? 'Offline model is not installed.'
            : 'Offline model failed to load.';
      case OfflineModelFailureClass.file:
      case OfflineModelFailureClass.engineInit:
      case OfflineModelFailureClass.unknown:
        return 'Offline model failed to load.';
    }
  }

  String _classifyLoadError(Object error, bool rehydrationFailed) {
    return _friendlyCopyFor(
      _classifyLoadFailure(error, rehydrationFailed),
      _classifyLoadState(error, rehydrationFailed),
    );
  }

  // Test hooks: thin delegates over the private pure helpers above.
  // Annotated — not public API. Production logic lives in the privates.
  @visibleForTesting
  String classifyLoadErrorForTest(Object error, bool rehydrationFailed) =>
      _classifyLoadError(error, rehydrationFailed);

  /// The classified failure of [error]: its class plus the friendly copy.
  @visibleForTesting
  LoadFailure classifyLoadFailureForTest(
    Object error,
    bool rehydrationFailed,
  ) => _classifyLoadFailure(error, rehydrationFailed);

  /// Injects the chat that [loadInstalled] uses instead of the native
  /// engine chain (active-model rehydration + getActiveModel + createChat).
  /// Production never sets it; tests use it to drive the load/retry state
  /// machine deterministically (a throwing override simulates a failed load).
  @visibleForTesting
  Future<InferenceChat> Function()? chatOverrideForTest;

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
