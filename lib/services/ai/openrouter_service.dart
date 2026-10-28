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

  static const String _msgKeyNotConfigured =
      'OpenRouter API key not configured. Please set OPENROUTER_API_KEY via --dart-define.';
  static const String _msgInvalidKey =
      'Invalid OpenRouter API key. Please check OPENROUTER_API_KEY.';
  static const String _msgFreeQuota =
      'OpenRouter free quota exhausted (daily limit or account balance).';
  static const String _msgForbidden = 'OpenRouter rejected the request (403).';
  static const String _msgTimeout = 'OpenRouter request timed out.';
  static const String _msgRateLimit =
      'OpenRouter rate limit exceeded (free tier: 20/min, 50/day).';
  static const String _msgBudgetExhausted =
      'OpenRouter: the model used its full response budget. Please try again.';
  static const String _msgCannotConnect =
      'Cannot connect to OpenRouter. Your network may be blocking external APIs.';

  /// Maps an HTTP status code to the contract's service message.
  static String _serviceMessageForStatus(int statusCode) {
    switch (statusCode) {
      case 401:
        return _msgInvalidKey;
      case 402:
        return _msgFreeQuota;
      case 403:
        return _msgForbidden;
      case 408:
        return _msgTimeout;
      case 429:
        return _msgRateLimit;
      default:
        if (statusCode >= 500) return 'OpenRouter server error: $statusCode';
        return 'OpenRouter request error: $statusCode';
    }
  }

  /// A mid-stream SSE error event carries the HTTP-equivalent code inside
  /// the stream (contract §1 mid_stream_error_events) — map it through the
  /// same table; an unknown code falls back to the generic copy.
  static String _serviceMessageForErrorCode(Object? code) {
    final status = switch (code) {
      final int value => value,
      final String value => int.tryParse(value.trim()),
      _ => null,
    };
    // Not a status code we know → the generic copy (contract §1
    // mid_stream_finish_reason_error).
    if (status == null || status < 100 || status > 599) {
      return 'OpenRouter request error: unknown';
    }
    return _serviceMessageForStatus(status);
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
            continue;
          } else {
            throw OpenRouterServiceException(
              _serviceMessageForStatus(response.statusCode),
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

      throw OpenRouterServiceException(_msgRateLimit);
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
        throw OpenRouterServiceException(
          _serviceMessageForStatus(streamedResponse.statusCode),
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
          if (event.errorCode != null || event.finishReason == 'error') {
            throw OpenRouterServiceException(
              _serviceMessageForErrorCode(event.errorCode),
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

/// A service error whose message is already mapped to the contract's error
/// table (§1). It never contains key material — only the mapped reason.
class OpenRouterServiceException implements Exception {
  final String message;

  const OpenRouterServiceException(this.message);

  @override
  String toString() => message;
}

/// One decoded SSE chunk. `reasoning_details` / `reasoning` deltas are
/// ignored on purpose (contract §1 ignored_fields) — only `delta.content`
/// reaches the UI.
class _SseEvent {
  final String? content;
  final String? finishReason;
  final Object? errorCode;

  const _SseEvent({this.content, this.finishReason, this.errorCode});
}

/// Decodes one `data: {json}` SSE payload. Throws (so the caller can count it
/// as a malformed chunk) when the payload is not a JSON object.
_SseEvent _parseSseEvent(String data) {
  final decoded = jsonDecode(data);
  if (decoded is! Map) {
    throw const FormatException('unexpected SSE payload');
  }

  Object? errorCode;
  final error = decoded['error'];
  if (error is Map) {
    errorCode = error['code'];
  }

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
      final nestedError = first['error'];
      if (nestedError is Map && errorCode == null) {
        errorCode = nestedError['code'];
      }
    }
  }

  return _SseEvent(
    content: content,
    finishReason: finishReason,
    errorCode: errorCode,
  );
}
