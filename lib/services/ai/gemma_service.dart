import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import '../../data/local/offline_model_dao.dart';
import '../../data/models/chat_message_model.dart';
import 'device_capabilities.dart';
import 'model_download_service.dart';
import 'offline_model_spec.dart';
import 'turn_priming.dart';

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

/// The stray-thinking dropper (cycle-46 P2 — plan §6.2/§9 S7 as amended,
/// contract v1.1.0 §10 S7).
///
/// The thinking FEATURE is withdrawn: there is no toggle, no UI surface and
/// no persistence of thinking text. What survives is the SEAM DISCIPLINE —
/// every chat is created with `enableThinking: false` EXPLICITLY, and this
/// transform drops whatever thinking content arrives anyway:
///
///   * the TYPED leg — a [ThinkingResponse] token is DROPPED outright (the
///     resolved source exposes a typed stream: `ModelResponse`);
///   * the MARKER leg — think-span TEXT that arrives inside a
///     [TextResponse] token is DROPPED too: core splits `<think>` spans
///     into a thinking channel for the Qwen/DeepSeek families ONLY
///     (`extensions.dart:378` puts `ModelType.llama` in the pass-through
///     arm), so on the GGUF path a raw span would otherwise reach the user
///     as ordinary answer text.
///
/// The transform is BOUNDED: at most one marker is ever held back, and an
/// UNCLOSED span at the end of a turn is thinking-only — it is dropped,
/// never persisted as an answer (plan §5.6, branch (b)).
///
/// Nothing that passes through here reaches the caller, the UI, the
/// transcript DB or the next turn's history: the drop happens AT THE SEAM.
class StrayThinkingFilter {
  /// The opening marker of a raw think span.
  static const String thinkStart = '<think>';

  /// The closing marker of a raw think span.
  static const String thinkEnd = '</think>';

  /// Whether the filter is currently inside a think span.
  bool _insideThinkSpan = false;

  /// The text held back because it may be the start of a marker.
  final StringBuffer _held = StringBuffer();

  /// Feeds one response and returns the VISIBLE answer text it carries —
  /// empty when the response was thinking content.
  String addResponse(ModelResponse response) {
    if (response is ThinkingResponse) {
      // The TYPED leg — DROPPED: never surfaced, never persisted.
      return '';
    }
    if (response is TextResponse) {
      return addText(response.token);
    }
    return '';
  }

  /// Feeds one text chunk and returns the VISIBLE answer text it carries.
  ///
  /// Text outside a think span is returned as it arrives; text inside one
  /// is dropped. A marker split across two chunks is held back until it
  /// resolves, so a span can never leak through the seam.
  String addText(String chunk) {
    if (chunk.isEmpty) return '';
    _held.write(chunk);

    final visible = StringBuffer();
    while (true) {
      final buffer = _held.toString();
      if (buffer.isEmpty) break;

      if (_insideThinkSpan) {
        final end = buffer.indexOf(thinkEnd);
        if (end >= 0) {
          _held.clear();
          _held.write(buffer.substring(end + thinkEnd.length));
          _insideThinkSpan = false;
          continue;
        }
        // Inside the span: everything but a possible SPLIT closing marker
        // is thinking content — dropped.
        final keep = _partialMarkerLength(buffer, thinkEnd);
        _held.clear();
        _held.write(buffer.substring(buffer.length - keep));
        break;
      }

      final start = buffer.indexOf(thinkStart);
      if (start >= 0) {
        visible.write(buffer.substring(0, start));
        _held.clear();
        _held.write(buffer.substring(start + thinkStart.length));
        _insideThinkSpan = true;
        continue;
      }

      final keep = _partialMarkerLength(buffer, thinkStart);
      visible.write(buffer.substring(0, buffer.length - keep));
      _held.clear();
      _held.write(buffer.substring(buffer.length - keep));
      break;
    }
    return visible.toString();
  }

  /// The end-of-stream tail: the text held back by a split marker — or
  /// nothing at all when the turn ended inside an UNCLOSED think span
  /// (thinking-only, never an answer).
  String finish() {
    final tail = _held.toString();
    _held.clear();
    if (_insideThinkSpan) return '';
    return tail;
  }

  /// The think-span-free text of a COMPLETE answer.
  static String strip(String text) {
    final filter = StrayThinkingFilter();
    return '${filter.addText(text)}${filter.finish()}';
  }

  /// The length of the longest suffix of [buffer] that is a proper prefix
  /// of [marker] — the text that may still turn out to be a split marker.
  static int _partialMarkerLength(String buffer, String marker) {
    final maxLength = marker.length - 1;
    if (maxLength <= 0) return 0;
    final take = buffer.length < maxLength ? buffer.length : maxLength;
    for (var length = take; length > 0; length--) {
      final suffix = buffer.substring(buffer.length - length);
      if (suffix == marker.substring(0, length)) return length;
    }
    return 0;
  }
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

  /// The generation stall watchdog, armed while a turn generates and reset
  /// on every token the engine emits. Null when no generation is in flight.
  Timer? _generationWatchdog;

  /// Set when the watchdog fires: the turn is stopped AND the failure is
  /// surfaced — a stalled generation is never a silently truncated answer.
  bool _generationStalled = false;

  static const Duration _streamFlushInterval = Duration(milliseconds: 45);
  static const int _streamFlushChars = 8;
  static const int _maxHistoryMessages = 8;
  static const int _maxTokens = 2048;
  static const int _maxHistoryChars = 1000;

  /// The output cap of EVERY send (cycle-46 P2 — plan §5.5, contract §2
  /// `load_shape`): at most 2048 GENERATED tokens per turn. On the llama
  /// path the thinking text would count toward it too — the app pins
  /// thinking off, so the cap belongs to the answer.
  static const int _maxOutputTokens = 2048;

  /// The generation stall watchdog window: 3 minutes with NO token at all.
  ///
  /// The app's download stall watchdog uses the same 3-minute window
  /// (`model_download_service.dart:143`); the generation watchdog EXTENDS
  /// that posture to the turn itself (plan §5.5: "the stall watchdog extends
  /// to generation via `stopGeneration()` on timeout"; contract §10
  /// `watchdog_extension`). Generous on purpose: a cold 2B model on a phone
  /// CPU can take a while to emit its FIRST token, and a slow turn still
  /// emits tokens — which reset the timer.
  static const Duration _generationStallTimeout = Duration(minutes: 3);

  /// The role-marked priming builder (cycle-45 Phase 1, the S3 ruling).
  /// The TOTAL staged budget (priming + new message) lives on the builder.
  static const TurnPrimingBuilder _primingBuilder = TurnPrimingBuilder();

  static const String greetingText =
      "Hello! I'm AgentA, What would you like to work on today?";

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
    _cancelGenerationWatchdog();

    final chat = _chat;
    if (chat != null) {
      _stopGeneration(chat);
    }
  }

  /// Stops the in-flight generation through the SAME path the stop
  /// affordance uses — `session.stopGeneration()` on the live chat.
  ///
  /// The stop affordance (the user pressing stop) and the generation stall
  /// watchdog (cycle-46 P2 — plan §5.5) share this one seam, so neither can
  /// drift from the other.
  void _stopGeneration(InferenceChat chat) {
    try {
      unawaited(
        chat.stopGeneration().catchError((Object error) {
          if (kDebugMode) {
            debugPrint('[GemmaService] stopGeneration failed: $error');
          }
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[GemmaService] stopGeneration failed: $e');
    }
  }

  /// Arms (or re-arms) the generation stall watchdog.
  ///
  /// Every token the engine emits proves the turn is alive, so the watchdog
  /// restarts from there — the same discipline the download watchdog uses
  /// (`model_download_service.dart:430`).
  void _armGenerationWatchdog() {
    _cancelGenerationWatchdog();
    _generationWatchdog = Timer(
      generationStallTimeoutOverrideForTest ?? _generationStallTimeout,
      _onGenerationStall,
    );
  }

  /// Cancels the generation stall watchdog. Safe when no timer is pending.
  void _cancelGenerationWatchdog() {
    _generationWatchdog?.cancel();
    _generationWatchdog = null;
  }

  /// The watchdog handler: no token arrived within the window, so the turn
  /// is presumed silently dead. The generation is STOPPED — exactly what
  /// the user's stop affordance does — and the turn is reported as failed
  /// rather than persisted as a truncated answer.
  void _onGenerationStall() {
    _generationWatchdog = null;
    if (_isCancelled) return;
    _generationStalled = true;
    _isCancelled = true;

    final chat = _chat;
    if (chat != null) {
      _stopGeneration(chat);
    }
    if (kDebugMode) {
      debugPrint('[GemmaService] generation stalled — generation stopped');
    }
  }

  /// Overrides the generation stall-watchdog window (test-only).
  @visibleForTesting
  Duration? generationStallTimeoutOverrideForTest;

  @override
  void dispose() {
    _cancelGenerationWatchdog();
    super.dispose();
  }

  /// Wipes the session so the next turn starts clean (cycle-45 Phase 1, S5).
  ///
  /// The reset seam stays a BARE WIPE: `clearHistory()` and nothing else. The
  /// priming is per-SEND (the ruled protocol), so priming here would be dead
  /// work — the next send wipes and re-primes anyway. The call site is
  /// `chats.dart:217` (`resetOfflineSession` inside `_initializeChat`).
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
      // The plugin auto-restores the active-model identity from
      // SharedPreferences at initialize() — from the persisted FILENAME
      // alone, never checked against the app's selected spec. So
      // ensureModelActive() is the load-time VERIFICATION (cycle-44 P2):
      // it confirms the active model IS the selected asset and repairs it
      // when it is not. Its install() is idempotent and skips the download
      // when the file is already in the plugin's storage.
      final chatOverride = chatOverrideForTest;
      if (chatOverride != null) {
        // Test-only: injects a ready chat instead of the native engine.
        _chat = await chatOverride();
      } else {
        // The load-time VERIFICATION (cycle-44 P2, branch A):
        // ensureModelActive() checks that the plugin's active model IS the
        // app's selected asset and activates it when it is not. It runs
        // UNCONDITIONALLY: the old `if (!hasActiveModel())` guard let a
        // restored FOREIGN active model — the plugin restores the persisted
        // filename alone, never checking it against the selected spec —
        // skip the repair entirely, and that foreign model answered.
        final rehydrated = await ModelDownloadService.ensureModelActive();
        rehydrationFailed = !rehydrated;
        if (kDebugMode && !rehydrated) {
          debugPrint(
            '[GemmaService] model rehydration failed — load will retry via gate',
          );
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
          // THINKING OFF — EXPLICITLY, NEVER OMITTED, NEVER DEFAULTED
          // (cycle-46 P2 — plan §6.2/§9 S7 as amended, contract v1.1.0
          // §10 S7; the reasoning: plan §2.4). The GGUF's embedded chat
          // template takes `enable_thinking` as a kwarg: an UNSET kwarg
          // lets the MODEL decide, and llamadart's own default is TRUE
          // (`llamadart-0.15.1/lib/src/core/engine/chat_session.dart:185`).
          // The app therefore pins it false on EVERY chat creation — the
          // llama.cpp connector forwards it to the template and to the
          // generation call
          // (`flutter_edge_ai_llama-0.0.5/lib/src/llama_inference_session
          // .dart:608`/`:639`).
          enableThinking: false,
          // The output cap of every send (plan §5.5, contract §2
          // `load_shape`): 2048 generated tokens at most.
          maxOutputTokens: _maxOutputTokens,
          // The SHORT, SPEC-DRIVEN system instruction (cycle-44 P2, the
          // rider): the instruction belongs to the asset, next to the
          // identity — the ~700-char rule-list that lived here is retired.
          systemInstruction: OfflineModelSpecTable.systemInstruction,
        );
      }

      // The identity the DB row carries is the app's offline-model identity
      // (the spec table is the only place the identity string is written —
      // contract §2): `qwen2.5-1.5b-it` app-wide.
      await _dao.setModelReady(modelType: OfflineModelSpecTable.appIdentity);
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

  /// The role-marked priming text of one send — the EXACT chunk text the
  /// send paths stage (cycle-45 Phase 1, the S3 ruling).
  ///
  /// Mirrors [recentHistoryForTest]: the raw history goes in and the current
  /// message names the turn being sent. Both de-dup rules run upstream (in
  /// `_getRecentHistory`), then the builder role-marks the window and fits it
  /// to the TOTAL staged budget (priming + new message ≤ 5000 chars).
  @visibleForTesting
  String primingTextForTest(
    List<ChatMessageModel> history, {
    required String currentMessage,
  }) => _primingBuilder.build(
    _getRecentHistory(history, currentMessage: currentMessage),
    stagedNewMessageLength: currentMessage.trim().length,
  );

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

  /// Stages ONE turn of the per-send protocol (cycle-45 Phase 1 — the S1–S5
  /// ruling). BOTH send paths run this method, so the two can never diverge.
  ///
  /// The order is NORMATIVE:
  ///   1. WIPE — `chat.clearHistory()`: the pinned core's FULL native wipe +
  ///      session recreate (`_fullHistory`/`_prefixes`/`_modelHistory`
  ///      cleared, `_currentTokens = 0`, `session.close()` + a fresh session —
  ///      the cycle-45 ruling cited `flutter_edge_ai-1.11.4` core
  ///      `chat.dart:966-980`; the resolved core 2.5.5 keeps the same
  ///      shape at `chat.dart:1101-1112`, and the llama connector's
  ///      override recreates the session the same way —
  ///      `flutter_edge_ai_llama-0.0.5/lib/src/llama_inference_chat.dart:96`).
  ///      The wipe STAYS (S1): the protocol carries every context APP-side,
  ///      so nothing depends on native response-retention (which stays
  ///      unverified).
  ///   2. PRIME — ONE role-marked priming chunk (`isUser: true`), staged
  ///      FIRST into the fresh session. Its text carries the capped window
  ///      with explicit `User: …` / `Assistant: …` blocks — role-marking is
  ///      app-side TEXT, because the `.task` RAW boundary strips every role
  ///      marker (`extensions.dart:57-69`/`:135-143`).
  ///   3. MESSAGE — the new-message chunk, staged AFTER the priming chunk.
  ///
  /// The protocol is UNCHANGED on the llama.cpp/GGUF path (cycle-46 P2 — the
  /// C45 turn protocol survives the chat-surface migration): the app still
  /// carries every context APP-side, and the history it replays is
  /// assembled from the STORED messages only — so no thinking content can
  /// enter it (the S7 stray-drop happens before an answer is stored).
  ///
  /// The `[System: …]` prefix rides the PRIMING chunk deterministically, once
  /// per send (S4): on `.task` the plugin does NOT inject the system
  /// instruction natively — native template injection is litertlm-only
  /// (`mobile_inference_session.dart:40-46`) — it prepends `'[System: …]\n\n'`
  /// AS TEXT to the FIRST user chunk staged in the session
  /// (`:77-86`), and the priming chunk is staged first into the fresh
  /// session. The prefix belongs to the PLUGIN: the app never writes it.
  ///
  /// Rotation posture (S2 — dissolved, recorded): the plugin's session
  /// rotation fires only AFTER a response was returned, and the per-send wipe
  /// resets `_currentTokens` (`chat.dart:970`), so it is unreachable in
  /// steady state and the next send's wipe discards any replay. There is NO
  /// app-side token accounting here.
  Future<void> _stageTurn(
    InferenceChat chat, {
    required List<ChatMessageModel> history,
    required String newMessage,
  }) async {
    final recentHistory = _getRecentHistory(
      history,
      currentMessage: newMessage,
    );
    final stagedMessage = newMessage.trim();
    // The TOTAL staged budget (S3): the priming text plus the new message.
    final primingText = _primingBuilder.build(
      recentHistory,
      stagedNewMessageLength: stagedMessage.length,
    );

    // 1. WIPE — the full native wipe + session recreate.
    await chat.clearHistory();
    // 2. PRIME — the role-marked history, staged FIRST (it carries the
    //    '[System: …]' prefix — see the method doc).
    await chat.addQueryChunk(Message.text(text: primingText, isUser: true));
    // 3. MESSAGE — the new message, staged after the priming chunk.
    await chat.addQueryChunk(Message.text(text: stagedMessage, isUser: true));
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
      await _stageTurn(chat, history: history, newMessage: newMessage);

      // The generation stall watchdog is armed for the TURN (plan §5.5).
      _generationStalled = false;
      _armGenerationWatchdog();

      final response = await chat.generateChatResponse();

      if (_generationStalled) {
        throw Exception('generation stalled');
      }

      if (response is TextResponse) {
        // The stray-thinking drop (S7): a think span that rode along with
        // the answer text is removed HERE — before it can reach the caller,
        // the UI or the transcript DB.
        return StrayThinkingFilter.strip(response.token);
      }
      // A typed thinking response (or any non-text response) is never an
      // answer: it is dropped, not surfaced.
      return 'Unable to generate response.';
    } catch (e) {
      if (kDebugMode) debugPrint('[GemmaService] sendMessage failed: $e');
      throw Exception('Offline AI could not respond. Please try again.');
    } finally {
      _cancelGenerationWatchdog();
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
      await _stageTurn(chat, history: history, newMessage: newMessage);

      // The generation stall watchdog is armed for the TURN (plan §5.5).
      _generationStalled = false;
      _armGenerationWatchdog();

      final flushTimer = Stopwatch()..start();
      final tokenBuffer = StringBuffer();
      // The stray-thinking drop (S7): the typed leg (a `ThinkingResponse`
      // token) and the marker leg (think-span text inside a text token)
      // are dropped AT THE SEAM — never rendered, never persisted, never
      // re-sent in the next turn's history.
      final strayThinking = StrayThinkingFilter();
      await for (final response in chat.generateChatResponseAsync()) {
        // ANY response — even a dropped one — proves the engine is alive,
        // so the stall watchdog restarts from here.
        _armGenerationWatchdog();

        if (_isCancelled) {
          break;
        }

        final visible = strayThinking.addResponse(response);
        if (visible.isNotEmpty) {
          tokenBuffer.write(visible);

          final shouldFlush =
              flushTimer.elapsed >= _streamFlushInterval ||
              tokenBuffer.length >= _streamFlushChars ||
              _endsAtNaturalBreak(visible);

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

      // The end-of-stream tail: text held back because a marker may have
      // been split across tokens. An UNCLOSED think span is thinking-only
      // — dropped, never flushed as an answer.
      final tail = strayThinking.finish();
      if (tail.isNotEmpty) {
        tokenBuffer.write(tail);
      }
      if (tokenBuffer.isNotEmpty && !_isCancelled) {
        yield tokenBuffer.toString();
        tokenBuffer.clear();
      }

      if (_generationStalled) {
        throw Exception('generation stalled');
      }
    } catch (e) {
      // A user stop is silent; a STALL is a failure the caller must see.
      if (_isCancelled && !_generationStalled) {
        return;
      }
      if (kDebugMode) debugPrint('[GemmaService] sendMessageStream failed: $e');
      throw Exception('Offline AI could not respond. Please try again.');
    } finally {
      _cancelGenerationWatchdog();
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
