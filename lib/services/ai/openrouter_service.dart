import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../data/models/chat_message_model.dart';
import '../../core/config/app_config.dart';

/// OpenRouter chat service — structural sibling of `GroqService`
/// (contracts/openrouter-ai.yaml §3, plan cycle-36 P3).
///
/// Contract-pinned differences from Groq:
///  * 60s connect timeout (F11) instead of Groq's 30s — the reasoning models
///    need longer to start; the body stream stays unbounded;
///  * the request payload carries `stream: true` (SSE path), `max_tokens:
///    4096`, `temperature: 0.7` and `reasoning: {effort: "low", exclude:
///    true}` — the documented reasoning-budget mitigation (F3);
///  * the SSE parser understands mid-stream `finish_reason: "error"` events
///    (F2) and raises a mapped error instead of truncating silently;
///  * every error body is parsed — `error.code`, `error.message` and
///    `error.metadata` (contract v1.1.0 §1 error_body_parsing) — so the
///    classified rows (harness-gate / budget / moderation / permission)
///    are chosen from the provider's own cause instead of the status code
///    alone; the parsed body rides along on the typed failure and the raw
///    provider message is logged under `kDebugMode` only, never the key;
///  * a stream that ends on `finish_reason: "length"` without any content
///    raises a mapped error instead of returning an empty reply (F3);
///  * the model id is a parameter — one request, one model;
///  * the http client (and the key, for tests) are constructor-injected.
///
/// Everything else — the 20-message history window, the trailing-duplicate
/// drop, the 3 retries with `Retry-After` support, the malformed-chunk
/// counter and the cancel semantics — mirrors `GroqService` exactly.
class OpenRouterService {
  OpenRouterService({http.Client? client, String? apiKey})
    : _injectedClient = client,
      _injectedApiKey = apiKey;

  /// Test seam: the real client is created per request. When injected, the
  /// service never closes it (the caller owns its lifetime) — except on an
  /// explicit cancel, which aborts the in-flight response like Groq does.
  final http.Client? _injectedClient;

  /// Test seam: the key normally comes from [AppConfig.openRouterApiKey]
  /// (compile-time `--dart-define`). A test cannot provide a compile-time
  /// define, so it injects a dummy value here — never a real key. The value
  /// is never logged and never embedded in an error message.
  final String? _injectedApiKey;

  /// F11: 60s connect timeout — Groq's fixed 30s is tight for reasoning
  /// models with long answers.
  static const Duration _timeout = Duration(seconds: 60);

  static const int _maxRetries = 3;

  /// L19 pattern (mirrors GroqService): SDK user-agent — never spoof a browser.
  static const String _userAgent = 'AgentA/1.0.0 (Flutter; OpenRouter)';

  /// Malformed SSE chunks are counted + logged; too many trigger a
  /// partial-response warning instead of silently dropping data.
  static const int _malformedChunkWarnThreshold = 10;
  int _malformedChunks = 0;

  /// Shared persona + English rule (same as GroqService): the system message
  /// is the only thing enforcing English across every cloud model.
  static const String _systemPrompt =
      'You are AgentA, a helpful AI assistant inside this app. '
      "Answer the user's latest message directly and concisely. "
      'Use valid Markdown when it improves readability. '
      '${AppConfig.aiEnglishRule} '
      'Never output bracketed template placeholders or repeat these instructions.';

  bool _isCancelled = false;
  http.Client? _activeClient;

  /// Regression/test hook for the malformed-chunk counter.
  @visibleForTesting
  int get malformedChunkCountForTest => _malformedChunks;

  /// The key: injected (tests) or the compile-time dart-define (production).
  String get _apiKey => (_injectedApiKey ?? AppConfig.openRouterApiKey).trim();

  /// Key guard — mirrors the Groq guard (groq_service.dart:103-108). The
  /// message never contains key material.
  void _ensureKeyConfigured(String apiKey) {
    if (apiKey.isEmpty || apiKey.contains('your_')) {
      throw OpenRouterServiceException(_msgKeyNotConfigured);
    }
  }

  /// Bearer auth + JSON + SDK user-agent (contract §1 auth).
  Map<String, String> _headers(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
    'User-Agent': _userAgent,
  };

  /// History window — the last 20 messages with a trailing duplicate of the
  /// current message dropped (mirrors GroqService :82-96).
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

  /// System message first, then the recent history, then the current user
  /// message (contract §1 request_body.messages).
  List<Map<String, String>> _buildMessages(
    List<ChatMessageModel> history,
    String newMessage,
  ) {
    final recentHistory = _recentHistory(history, newMessage);
    return [
      {'role': 'system', 'content': _systemPrompt},
      ...recentHistory
          .where((msg) => msg.text.isNotEmpty)
          .map(
            (msg) => {
              'role': msg.isUser ? 'user' : 'assistant',
              'content': msg.text,
            },
          ),
      {'role': 'user', 'content': newMessage},
    ];
  }

  /// Request payload (contract §1 request_body). `stream: true` is sent on the
  /// SSE path; the non-stream sibling keeps Groq's shape and omits the flag
  /// (the API default is a single JSON response).
  Map<String, dynamic> _buildPayload({
    required String model,
    required List<Map<String, String>> messages,
    required bool stream,
  }) {
    return {
      'model': model,
      'messages': messages,
      'temperature': 0.7,
      // F3 mitigation: reasoning tokens count against max_tokens.
      'max_tokens': 4096,
      // F3 mitigation: keep the reasoning effort low and exclude the
      // reasoning text from the reply.
      'reasoning': {'effort': 'low', 'exclude': true},
      if (stream) 'stream': true,
    };
  }

  /// Honors the server `Retry-After` (seconds or HTTP date, ≤300s) and falls
  /// back to exponential backoff (mirrors GroqService :32-52).
  Duration _retryDelay(int attempt, {String? retryAfter}) {
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
            '[OpenRouterService] unparseable Retry-After "$retryAfter" — using backoff: $e',
          );
        }
      }
    }
    return Duration(seconds: 2 << attempt);
  }

  /// Malformed SSE chunks are counted + logged via the shared helper
  /// (threshold warning after repeated failures) instead of being dropped.
  void _noteMalformedChunk(String context, Object e, String raw) {
    _malformedChunks++;
    final preview = raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
    debugPrint(
      '[OpenRouterService] malformed SSE chunk #$context '
      '($_malformedChunks total): $e | raw: $preview',
    );
    if (_malformedChunks == _malformedChunkWarnThreshold) {
      debugPrint(
        '[OpenRouterService] WARNING: $_malformedChunkWarnThreshold+ '
        'malformed chunks — response may be partial',
      );
    }
  }

  /// Cancel semantics — identical to GroqService :69-80.
  void cancelGeneration() {
    _isCancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  void resetCancel() {
    _isCancelled = false;
  }

  /// True for the transport failures Groq retries on.
  static bool _isSocketError(Object e) {
    final text = e.toString();
    return text.contains('SocketException') ||
        text.contains('HandshakeException');
  }

  // ── Error mapping (contract §1 error table) ───────────────────────────
  // The service throws the table's `service_message`; the classifier maps it
  // to the table's `friendly` copy (contract §3). No key material ever
  // appears in these strings.
  //
  // cycle-37 P3 (contract v1.1.0): the status code alone is never enough —
  // every error body is parsed (`error.code` / `error.message` /
  // `error.metadata`) and the classified rows are selected from it BEFORE
  // the status row (contract §1 error_body_parsing.precedence).

  static const String _msgKeyNotConfigured =
      'OpenRouter API key not configured. Please set OPENROUTER_API_KEY via --dart-define.';
  static const String _msgInvalidKey =
      'Invalid OpenRouter API key. Please check OPENROUTER_API_KEY.';
  static const String _msgFreeQuota =
      'OpenRouter free quota exhausted (daily limit or account balance).';
  static const String _msgTimeout = 'OpenRouter request timed out.';
  static const String _msgRateLimit =
      'OpenRouter rate limit exceeded (free tier: 20/min, 50/day).';
  static const String _msgBudgetExhausted =
      'OpenRouter: the model used its full response budget. Please try again.';
  static const String _msgCannotConnect =
      'Cannot connect to OpenRouter. Your network may be blocking external APIs.';

  // The classified rows (contract §1 error_table, v1.1.0).
  static const String _msgHarnessGatePrefix = 'OpenRouter blocked this model: ';
  static const String _msgHarnessGateSuffix =
      ' is restricted to agentic harnesses on the free tier.';
  static const String _msgKeySpendingLimit =
      'OpenRouter key spending limit reached (403).';
  static const String _msgSafetyLayer =
      'OpenRouter blocked this request (safety layer).';
  static const String _msgRestricted =
      'OpenRouter refused the request (403): account or key restriction.';

  /// The routing step OpenRouter names when a `:free` endpoint is gated to
  /// agentic harnesses (contract §1 403_harness_gate; the P1 probe's
  /// verbatim body, plan §2.5).
  static const String _harnessGateRoutingStep =
      'Gate Free Endpoints by Agentic Harness';

  /// The provider's own phrase for the same gate (contract §1
  /// 403_harness_gate.match_key).
  static const String _harnessGateMessageKey =
      'only available on agentic harnesses';

  /// The guardrail block marker (contract §1 403_moderation_guardrail).
  static const String _guardrailMessageKey = 'request blocked:';

  /// Maps a status code to the contract's service message. The 403 row is
  /// the residual `403_permission_other` row — the classified rows
  /// (harness-gate / budget / moderation) are selected from the parsed body
  /// BEFORE this fallback (contract §1 error_body_parsing.precedence).
  static String _serviceMessageForStatus(int? statusCode) {
    switch (statusCode) {
      case 401:
        return _msgInvalidKey;
      case 402:
        return _msgFreeQuota;
      case 403:
        return _msgRestricted;
      case 408:
        return _msgTimeout;
      case 429:
        return _msgRateLimit;
      default:
        if (statusCode == null) return 'OpenRouter request error: unknown';
        if (statusCode >= 500) return 'OpenRouter server error: $statusCode';
        return 'OpenRouter request error: $statusCode';
    }
  }

  /// True for the harness gate: the routing step OpenRouter names, or the
  /// provider's own phrase for it (contract §1 403_harness_gate.match_key).
  static bool _isHarnessGate(OpenRouterErrorBody body) {
    final step = body.failedRoutingStep?.trim().toLowerCase();
    if (step == _harnessGateRoutingStep.toLowerCase()) return true;
    return (body.message ?? '').toLowerCase().contains(_harnessGateMessageKey);
  }

  /// True for the moderation / safety-layer class (contract §1
  /// 403_moderation_guardrail.match_key).
  static bool _isModeration(OpenRouterErrorBody body) {
    final type = body.errorType?.trim().toLowerCase();
    if (type == 'content_policy_violation' || type == 'refusal') return true;
    return (body.message ?? '').toLowerCase().contains(_guardrailMessageKey);
  }

  /// Maps a parsed error body to the contract's `service_message`
  /// (contract §1 error_body_parsing.precedence):
  ///   1. the classified rows — harness-gate FIRST, then budget, then
  ///      moderation — whatever the status code says;
  ///   2. otherwise the status row (a 403 falls through to the residual
  ///      permission row);
  ///   3. an unparseable body keeps the status-code fallback.
  static String _serviceMessageForErrorBody(
    OpenRouterErrorBody? body, {
    required int? status,
    required String model,
  }) {
    if (body != null) {
      if (_isHarnessGate(body)) {
        return '$_msgHarnessGatePrefix$model$_msgHarnessGateSuffix';
      }
      if (body.limitSource != null) return _msgKeySpendingLimit;
      if (_isModeration(body)) return _msgSafetyLayer;
    }
    return _serviceMessageForStatus(status);
  }

  /// Builds the mapped failure for a provider error: the classified
  /// `service_message` is the user-facing surface, the parsed body rides
  /// along on the exception (developer-visible truth) and the provider's raw
  /// message is logged under `kDebugMode` only — never the key (contract §1
  /// error_body_parsing.debug_surface).
  static OpenRouterServiceException _failureFor({
    required OpenRouterErrorBody? body,
    required int? status,
    required String model,
  }) {
    final message = _serviceMessageForErrorBody(
      body,
      status: status,
      model: model,
    );
    if (kDebugMode) {
      debugPrint(
        '[OpenRouterService] provider error — status: $status, '
        'code: ${body?.code ?? 'none'}, '
        'message: ${body?.message ?? 'none'}, '
        'metadata: ${body?.metadata ?? 'none'}',
      );
    }
    return OpenRouterServiceException(message, errorBody: body);
  }

  /// Parses the non-stream JSON body: the assistant content plus the finish
  /// reason (needed for the F3 empty-content guard).
  static ({String? content, String? finishReason}) _parseJsonCompletion(
    String body,
  ) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return (content: null, finishReason: null);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      return (content: null, finishReason: null);
    }
    final first = choices.first;
    if (first is! Map) return (content: null, finishReason: null);
    final reason = first['finish_reason'];
    final message = first['message'];
    String? content;
    if (message is Map) {
      final raw = message['content'];
      if (raw is String) content = raw;
    }
    return (content: content, finishReason: reason is String ? reason : null);
  }

  /// Non-stream chat completion — the sibling of [GroqService.sendMessage]
  /// with the OpenRouter payload and the contract's error table.
  Future<String> sendMessage({
    required List<ChatMessageModel> history,
    required String newMessage,
    required String model,
  }) async {
    resetCancel();
    final apiKey = _apiKey;
    _ensureKeyConfigured(apiKey);

    final messages = _buildMessages(history, newMessage);
    final client = _injectedClient ?? http.Client();
    final ownsClient = _injectedClient == null;

    try {
      // The parsed body of the last rate-limited response — mapped once the
      // retries are exhausted (contract §1 error_body_parsing).
      OpenRouterErrorBody? lastRateLimitBody;
      for (int attempt = 0; attempt < _maxRetries; attempt++) {
        if (_isCancelled) break;
        try {
          final response = await client
              .post(
                Uri.parse(AppConfig.openRouterEndpoint),
                headers: _headers(apiKey),
                body: jsonEncode(
                  _buildPayload(
                    model: model,
                    messages: messages,
                    stream: false,
                  ),
                ),
              )
              .timeout(_timeout);

          if (response.statusCode == 200) {
            final completion = _parseJsonCompletion(response.body);
            final content = completion.content;
            if (content != null && content.trim().isNotEmpty) return content;
            // A 200 body holding only an `error` object is a provider error,
            // not an invalid body (contract §1 error_body_parsing).
            final errorBody = OpenRouterErrorBody.parse(response.body);
            if (errorBody != null) {
              throw _failureFor(
                body: errorBody,
                status: _statusFromCode(errorBody.code),
                model: model,
              );
            }
            // F3: the budget was spent on reasoning — never an empty reply.
            if (completion.finishReason == 'length') {
              throw OpenRouterServiceException(_msgBudgetExhausted);
            }
            throw OpenRouterServiceException(
              'OpenRouter request error: invalid response body',
            );
          } else if (response.statusCode == 429) {
            // Honor the server's Retry-After hint when present, fall back to
            // exponential backoff.
            final waitTime = _retryDelay(
              attempt,
              retryAfter: response.headers['retry-after'],
            );
            await Future.delayed(waitTime);
            lastRateLimitBody = OpenRouterErrorBody.parse(response.body);
            continue;
          } else {
            final errorBody = OpenRouterErrorBody.parse(response.body);
            throw _failureFor(
              body: errorBody,
              status: _statusFromCode(errorBody?.code) ?? response.statusCode,
              model: model,
            );
          }
        } on TimeoutException {
          if (attempt == _maxRetries - 1) {
            throw OpenRouterServiceException(_msgTimeout);
          }
          await Future.delayed(Duration(seconds: 2 << attempt));
        } catch (e) {
          if (_isSocketError(e)) {
            if (attempt == _maxRetries - 1) {
              throw OpenRouterServiceException(_msgCannotConnect);
            }
            await Future.delayed(Duration(seconds: 2 << attempt));
            continue;
          }
          rethrow;
        }
      }

      throw _failureFor(
        body: lastRateLimitBody,
        status: _statusFromCode(lastRateLimitBody?.code) ?? 429,
        model: model,
      );
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Streaming chat completion — the SSE sibling of
  /// [GroqService.sendMessageStream] with two contract-pinned additions:
  /// mid-stream `finish_reason: "error"` events (F2) and the
  /// `finish_reason: "length"` empty-content guard (F3).
  Stream<String> sendMessageStream({
    required List<ChatMessageModel> history,
    required String newMessage,
    required String model,
  }) async* {
    resetCancel();
    final apiKey = _apiKey;
    _ensureKeyConfigured(apiKey);

    final messages = _buildMessages(history, newMessage);
    final client = _injectedClient ?? http.Client();
    final ownsClient = _injectedClient == null;
    _activeClient = client;

    try {
      final request = http.Request(
        'POST',
        Uri.parse(AppConfig.openRouterEndpoint),
      );
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.headers['Content-Type'] = 'application/json';
      request.headers['User-Agent'] = _userAgent;
      request.body = jsonEncode(
        _buildPayload(model: model, messages: messages, stream: true),
      );

      final streamedResponse = await client.send(request).timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        // A pre-stream error carries the provider's cause in its body — read
        // it and map through the table (contract §1 error_body_parsing).
        final rawBody = await streamedResponse.stream.bytesToString().timeout(
          _timeout,
        );
        final errorBody = OpenRouterErrorBody.parse(rawBody);
        throw _failureFor(
          body: errorBody,
          status:
              _statusFromCode(errorBody?.code) ?? streamedResponse.statusCode,
          model: model,
        );
      }

      var yieldedContent = false;
      String? finishReason;
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

          final _SseEvent event;
          try {
            event = _parseSseEvent(data);
          } catch (e) {
            // Malformed chunk — counted + logged, never fatal.
            _noteMalformedChunk('stream', e, data);
            continue;
          }

          // F2: an error event inside the stream is NOT an HTTP status — it
          // must end the stream with a mapped error, never a silent truncation.
          // The embedded body is parsed exactly like the HTTP error path
          // (contract §1 mid_stream_finish_reason_error).
          if (event.errorBody != null || event.finishReason == 'error') {
            throw _failureFor(
              body: event.errorBody,
              status: _statusFromCode(event.errorBody?.code),
              model: model,
            );
          }

          if (event.finishReason != null && event.finishReason!.isNotEmpty) {
            finishReason = event.finishReason;
          }
          final content = event.content;
          if (content != null && content.isNotEmpty) {
            yieldedContent = true;
            yield content;
          }
        }
      }

      // F3: the stream ended on "length" without any content — the reasoning
      // budget ate the whole allowance. Raise a mapped error, never an empty
      // reply.
      if (!yieldedContent && finishReason == 'length') {
        throw OpenRouterServiceException(_msgBudgetExhausted);
      }
    } on TimeoutException {
      throw OpenRouterServiceException(_msgTimeout);
    } on OpenRouterServiceException {
      rethrow;
    } catch (e) {
      if (_isSocketError(e)) {
        throw OpenRouterServiceException(_msgCannotConnect);
      }
      throw OpenRouterServiceException('OpenRouter service error: $e');
    } finally {
      if (ownsClient) client.close();
      _activeClient = null;
    }
  }
}

/// A service error whose `message` is already mapped to the contract's error
/// table (§1). It never contains key material — only the mapped reason.
///
/// The parsed provider body (`code` / `message` / `metadata`) rides along as
/// [errorBody] — the developer-visible truth — while the user-facing
/// `message` stays the mapped `service_message` (contract §1
/// error_body_parsing.debug_surface).
class OpenRouterServiceException implements Exception {
  final String message;
  final OpenRouterErrorBody? errorBody;

  const OpenRouterServiceException(this.message, {this.errorBody});

  @override
  String toString() => message;
}

/// The parsed provider error body (contract §1 error_body_parsing).
///
/// `code` is the provider's own `error.code` (an integer or a numeric
/// string), `message` the provider's raw cause sentence and `metadata` the
/// discriminator object (`limit_source`, `error_type`, `provider_name`,
/// `routing_funnel`, `failed_routing_step`). The raw message is never
/// user-facing — it selects the mapped row and stays debug-only.
class OpenRouterErrorBody {
  final int? code;
  final String? message;
  final Map<String, dynamic>? metadata;

  const OpenRouterErrorBody({this.code, this.message, this.metadata});

  /// Parses a raw response body. Returns null when the body carries no
  /// usable `error` object — the caller then falls back to the status row.
  static OpenRouterErrorBody? parse(String rawBody) {
    if (rawBody.trim().isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(rawBody);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    return fromMap(decoded['error']);
  }

  /// Builds the parsed body from a decoded `error` object — the HTTP body
  /// and the SSE error event share this shape (contract §1
  /// mid_stream_error_events).
  static OpenRouterErrorBody? fromMap(Object? error) {
    if (error is! Map) return null;
    final rawCode = error['code'];
    final code = switch (rawCode) {
      final int value => value,
      final String value => int.tryParse(value.trim()),
      _ => null,
    };
    final message = error['message'];
    final metadata = error['metadata'];
    return OpenRouterErrorBody(
      code: code,
      message: message is String ? message : null,
      metadata: metadata is Map ? Map<String, dynamic>.from(metadata) : null,
    );
  }

  /// `error.metadata.limit_source` — the budget/key-limit discriminator.
  String? get limitSource {
    final value = metadata?['limit_source'];
    return value is String ? value : null;
  }

  /// `error.metadata.error_type` — the moderation/permission discriminator.
  String? get errorType {
    final value = metadata?['error_type'];
    return value is String ? value : null;
  }

  /// `error.metadata.failed_routing_step` — the routing discriminator (P1
  /// probe body, plan §2.5). A SIBLING of [routingFunnel].
  String? get failedRoutingStep {
    final value = metadata?['failed_routing_step'];
    return value is String ? value : null;
  }

  /// `error.metadata.routing_funnel` — the routing discriminator (P1 probe
  /// body, plan §2.5).
  List<dynamic>? get routingFunnel {
    final value = metadata?['routing_funnel'];
    return value is List ? value : null;
  }

  /// True when the body carries routing metadata at all — a routing-class
  /// failure, not a payload defect (contract §1
  /// other_4xx.routing_metadata_first).
  bool get hasRoutingMetadata =>
      routingFunnel != null || failedRoutingStep != null;

  @override
  String toString() =>
      'OpenRouterErrorBody(code: $code, message: $message, metadata: $metadata)';
}

/// The status a parsed `error.code` selects — null when the code is not a
/// usable HTTP status (the generic copy covers it; contract §1
/// mid_stream_finish_reason_error).
int? _statusFromCode(int? code) {
  if (code == null || code < 100 || code > 599) return null;
  return code;
}

/// One decoded SSE chunk. `reasoning_details` / `reasoning` deltas are
/// ignored on purpose (contract §1 ignored_fields) — only `delta.content`
/// reaches the UI.
class _SseEvent {
  final String? content;
  final String? finishReason;
  final OpenRouterErrorBody? errorBody;

  const _SseEvent({this.content, this.finishReason, this.errorBody});
}

/// Decodes one `data: {json}` SSE payload. Throws (so the caller can count it
/// as a malformed chunk) when the payload is not a JSON object.
_SseEvent _parseSseEvent(String data) {
  final decoded = jsonDecode(data);
  if (decoded is! Map) {
    throw const FormatException('unexpected SSE payload');
  }

  OpenRouterErrorBody? errorBody = OpenRouterErrorBody.fromMap(
    decoded['error'],
  );

  String? content;
  String? finishReason;
  final choices = decoded['choices'];
  if (choices is List && choices.isNotEmpty) {
    final first = choices.first;
    if (first is Map) {
      final delta = first['delta'];
      if (delta is Map) {
        final raw = delta['content'];
        if (raw is String) content = raw;
      }
      final reason = first['finish_reason'];
      if (reason is String) finishReason = reason;
      // A nested error object (choices[0].error) is parsed the same way.
      errorBody ??= OpenRouterErrorBody.fromMap(first['error']);
    }
  }

  return _SseEvent(
    content: content,
    finishReason: finishReason,
    errorBody: errorBody,
  );
}
