import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:aiproject/core/utils/chat_error_classifier.dart';
import 'package:aiproject/data/models/chat_message_model.dart';
import 'package:aiproject/services/ai/ai_model.dart';
import 'package:aiproject/services/ai/groq_service.dart';
import 'package:aiproject/services/ai/huggingface_image_service.dart';
import 'package:aiproject/services/ai/online_ai_service.dart';
import 'package:aiproject/services/ai/openrouter_service.dart';
import 'package:aiproject/services/ai/pollinations_service.dart';

// SECTION: test doubles (fake client, SSE/JSON response builders, message helper)

/// The two contract model ids (contracts/openrouter-ai.yaml §2, v1.2.0)
/// — the only OpenRouter model strings allowed in test/.
const String flashModelId = 'nvidia/nemotron-3.5-lightning:free';
const String proModelId = 'nvidia/nemotron-3-ultra-550b-a55b:free';

/// A dummy key — never a real one, and never asserted by value.
const String testApiKey = 'dummy-test-key';

/// The verbatim harness-gate 403 body from the P1 probe
/// (contracts/openrouter-ai.yaml §1 403_harness_gate.evidence_body; plan
/// §2.5) — byte-exact and free of key material.
const String harnessGateBody =
    '{"error":{"message":"nvidia/nemotron-3-ultra-550b-a55b:free is only available on agentic harnesses. Try plugging it into a coding agent or productivity app listed on https://openrouter.ai/apps","code":403,"metadata":{"routing_funnel":[{"step":"Initial Endpoints","endpoint_count":1}],"failed_routing_step":"Gate Free Endpoints by Agentic Harness"}}}';

/// Injected fake client — no network, full control over the response.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;
  final List<http.BaseRequest> requests = [];
  bool closed = false;

  /// The decoded JSON body of every captured request.
  List<Map<String, dynamic>> get requestBodies => requests
      .map((r) => jsonDecode((r as http.Request).body) as Map<String, dynamic>)
      .toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return _handler(request);
  }

  @override
  void close() {
    closed = true;
  }
}

/// A scripted SSE response.
http.StreamedResponse _sseResponse(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    headers: headers,
  );
}

/// A scripted JSON (non-stream) response.
http.StreamedResponse _jsonResponse(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    headers: headers,
  );
}

/// One SSE content chunk.
String _sseChunk(String content) {
  return 'data: {"object":"chat.completion.chunk","choices":'
      '[{"index":0,"delta":{"content":${jsonEncode(content)}},"finish_reason":null}]}\n\n';
}

/// The end-of-stream sentinel.
const String sseDone = 'data: [DONE]\n\n';

ChatMessageModel _msg(String text, {bool isUser = true}) {
  return ChatMessageModel(
    id: 'm',
    chatId: 'c',
    text: text,
    isUser: isUser,
    timestamp: DateTime(2026, 1, 1),
  );
}

/// Runs a stream and returns the first error it raised (null when it ended
/// cleanly).
Future<Object?> _streamError(Stream<String> stream) async {
  try {
    await stream.toList();
    return null;
  } catch (e) {
    return e;
  }
}

/// Runs a future and returns the first error it raised (null on success).
Future<Object?> _futureError(Future<String> future) async {
  try {
    await future;
    return null;
  } catch (e) {
    return e;
  }
}

/// Records which model id the facade dispatched (contract §3 dispatch).
class _RecordingOpenRouterService extends OpenRouterService {
  _RecordingOpenRouterService()
    : super(
        client: _FakeHttpClient((_) async => _sseResponse(sseDone)),
        apiKey: testApiKey,
      );

  final List<String> sentModels = [];
  final List<String> streamedModels = [];
  bool cancelled = false;

  @override
  Future<String> sendMessage({
    required List<ChatMessageModel> history,
    required String newMessage,
    required String model,
  }) async {
    sentModels.add(model);
    return 'ok';
  }

  @override
  Stream<String> sendMessageStream({
    required List<ChatMessageModel> history,
    required String newMessage,
    required String model,
  }) async* {
    streamedModels.add(model);
    yield 'ok';
  }

  @override
  void cancelGeneration() {
    cancelled = true;
  }
}
// SECTION: request shape (auth header, payload, per-model routing, history window)
// SECTION: stream parsing (content deltas, comments, DONE, malformed chunks)
// SECTION: error mapping (HTTP status table, mid-stream error, empty-content guard)
// SECTION: cancel + retry behaviour

void main() {
  // SECTION: request shape
  group('OpenRouterService request shape', () {
    test(
      'sends bearer auth, the contract payload and a system-first history',
      () async {
        final client = _FakeHttpClient(
          (_) async => _sseResponse('${_sseChunk('hi')}$sseDone'),
        );
        final service = OpenRouterService(client: client, apiKey: testApiKey);

        final chunks = await service
            .sendMessageStream(
              history: [_msg('earlier', isUser: false)],
              newMessage: 'hello',
              model: flashModelId,
            )
            .toList();

        expect(chunks, ['hi']);
        expect(client.requests.length, 1);

        final request = client.requests.single as http.Request;
        // Auth: the header is present exactly once and carries a bearer token.
        // The key VALUE is never asserted.
        expect(
          request.headers.keys.where((k) => k.toLowerCase() == 'authorization'),
          hasLength(1),
        );
        expect(request.headers['Authorization'], startsWith('Bearer '));
        expect(request.headers['Content-Type'], contains('application/json'));
        expect(
          request.headers['User-Agent'],
          'AgentA/1.0.0 (Flutter; OpenRouter)',
        );

        final body = client.requestBodies.single;
        expect(body['model'], flashModelId);
        expect(body['stream'], isTrue);
        expect(body['max_tokens'], 4096);
        expect(body['temperature'], 0.7);
        expect(body['reasoning'], {'effort': 'low', 'exclude': true});

        final messages = body['messages'] as List<dynamic>;
        expect((messages.first as Map)['role'], 'system');
        expect((messages[1] as Map)['role'], 'assistant');
        expect((messages[1] as Map)['content'], 'earlier');
        expect((messages.last as Map)['role'], 'user');
        expect((messages.last as Map)['content'], 'hello');
      },
    );

    test('routes each model id to its own request', () async {
      final client = _FakeHttpClient(
        (_) async => _sseResponse('${_sseChunk('ok')}$sseDone'),
      );
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      await service
          .sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: flashModelId,
          )
          .toList();
      await service
          .sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: proModelId,
          )
          .toList();

      expect(client.requestBodies[0]['model'], flashModelId);
      expect(client.requestBodies[1]['model'], proModelId);
    });

    test(
      'keeps the last 20 history messages and drops the duplicate',
      () async {
        final client = _FakeHttpClient(
          (_) async => _sseResponse('${_sseChunk('ok')}$sseDone'),
        );
        final service = OpenRouterService(client: client, apiKey: testApiKey);

        final history = [
          for (int i = 0; i < 25; i++) _msg('h$i', isUser: i.isEven),
        ];

        await service
            .sendMessageStream(
              history: history,
              newMessage: 'h24',
              model: flashModelId,
            )
            .toList();

        final messages =
            client.requestBodies.single['messages'] as List<dynamic>;
        // system + 20 history + the current user message.
        expect(messages.length, 22);
        expect((messages[1] as Map)['content'], 'h4');
        expect((messages[20] as Map)['content'], 'h23');
        expect((messages.last as Map)['content'], 'h24');
      },
    );

    test('refuses to run without a configured key', () async {
      final client = _FakeHttpClient((_) async => _sseResponse(sseDone));
      final service = OpenRouterService(client: client, apiKey: '');

      final error = await _streamError(
        service.sendMessageStream(
          history: const [],
          newMessage: 'hello',
          model: flashModelId,
        ),
      );

      expect(error, isNotNull);
      expect(client.requests, isEmpty);
      expect(
        ChatErrorClassifier.friendly(error.toString()),
        'Chat service is not configured correctly.',
      );
    });
  });

  // SECTION: stream parsing
  group('OpenRouterService stream parsing', () {
    test('yields content deltas, skips comments and stops at DONE', () async {
      final body =
          ': this is an SSE comment\n'
          '${_sseChunk('Hello')}'
          ': another comment\n'
          '${_sseChunk(' world')}'
          '$sseDone';
      final client = _FakeHttpClient((_) async => _sseResponse(body));
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final chunks = await service
          .sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: flashModelId,
          )
          .toList();

      expect(chunks, ['Hello', ' world']);
      expect(service.malformedChunkCountForTest, 0);
    });

    test('ignores reasoning deltas', () async {
      final body =
          'data: {"choices":[{"delta":{"reasoning_details":'
          '[{"type":"reasoning.text","text":"thinking"}],"content":"Answer"}}]}\n\n'
          '$sseDone';
      final client = _FakeHttpClient((_) async => _sseResponse(body));
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final chunks = await service
          .sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: flashModelId,
          )
          .toList();

      expect(chunks, ['Answer']);
    });

    test('counts malformed chunks instead of dropping them silently', () async {
      final body =
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n'
          'data: {not-json}\n'
          '$sseDone';
      final client = _FakeHttpClient((_) async => _sseResponse(body));
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final chunks = await service
          .sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: flashModelId,
          )
          .toList();

      expect(chunks, ['ok']);
      expect(service.malformedChunkCountForTest, 1);
    });
  });

  // SECTION: error mapping
  group('OpenRouterService error mapping', () {
    test('maps every HTTP status to its friendly copy', () async {
      const expected = <int, String>{
        401: 'Chat service is not configured correctly.',
        402:
            'Free chat quota reached for today. Try again tomorrow or switch models.',
        403:
            'Your OpenRouter account or API key is restricted from this request. Check your OpenRouter account settings or switch models.',
        408: 'Connection timed out. Check your internet connection.',
        400: 'The selected AI model failed to respond. Please try again.',
        404: 'The selected AI model failed to respond. Please try again.',
        413: 'The selected AI model failed to respond. Please try again.',
        422: 'The selected AI model failed to respond. Please try again.',
        429:
            'Cloud chat is rate limited (free tier: 20 requests/min, 50/day). Wait a moment and try again.',
        500: 'The AI service is temporarily unavailable. Please try again.',
        502: 'The AI service is temporarily unavailable. Please try again.',
        503: 'The AI service is temporarily unavailable. Please try again.',
        524: 'The AI service is temporarily unavailable. Please try again.',
        529: 'The AI service is temporarily unavailable. Please try again.',
      };

      for (final entry in expected.entries) {
        final client = _FakeHttpClient(
          (_) async => _sseResponse('{}', statusCode: entry.key),
        );
        final service = OpenRouterService(client: client, apiKey: testApiKey);

        final error = await _streamError(
          service.sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: flashModelId,
          ),
        );

        expect(error, isNotNull, reason: 'status ${entry.key}');
        expect(
          ChatErrorClassifier.friendly(error.toString()),
          entry.value,
          reason: 'status ${entry.key}',
        );
      }
    });

    test('maps a non-stream status to its friendly copy too', () async {
      final client = _FakeHttpClient(
        (_) async => _jsonResponse('{}', statusCode: 402),
      );
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final error = await _futureError(
        service.sendMessage(
          history: const [],
          newMessage: 'hello',
          model: flashModelId,
        ),
      );

      expect(error, isNotNull);
      expect(
        ChatErrorClassifier.friendly(error.toString()),
        'Free chat quota reached for today. Try again tomorrow or switch models.',
      );
    });

    test('raises the classified error for a mid-stream error event', () async {
      final body =
          'data: {"error":{"code":429,"message":"Rate limit"},'
          '"choices":[{"delta":{},"finish_reason":"error"}]}\n\n';
      final client = _FakeHttpClient((_) async => _sseResponse(body));
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final error = await _streamError(
        service.sendMessageStream(
          history: const [],
          newMessage: 'hello',
          model: flashModelId,
        ),
      );

      expect(error, isNotNull);
      expect(
        ChatErrorClassifier.friendly(error.toString()),
        'Cloud chat is rate limited (free tier: 20 requests/min, 50/day). Wait a moment and try again.',
      );
    });

    test(
      'raises the generic copy for an unknown mid-stream error code',
      () async {
        final body =
            'data: {"error":{"code":99999,"message":"boom"},'
            '"choices":[{"delta":{},"finish_reason":"error"}]}\n\n';
        final client = _FakeHttpClient((_) async => _sseResponse(body));
        final service = OpenRouterService(client: client, apiKey: testApiKey);

        final error = await _streamError(
          service.sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: flashModelId,
          ),
        );

        expect(error, isNotNull);
        expect(
          ChatErrorClassifier.friendly(error.toString()),
          'The selected AI model failed to respond. Please try again.',
        );
      },
    );

    test(
      'raises the budget copy when the stream ends on length with no text',
      () async {
        final body =
            'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n$sseDone';
        final client = _FakeHttpClient((_) async => _sseResponse(body));
        final service = OpenRouterService(client: client, apiKey: testApiKey);

        final error = await _streamError(
          service.sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: flashModelId,
          ),
        );

        expect(error, isNotNull);
        expect(
          ChatErrorClassifier.friendly(error.toString()),
          'The model used its full response budget. Please try again.',
        );
      },
    );

    test('raises the budget copy for an empty non-stream completion', () async {
      final body =
          '{"choices":[{"message":{"role":"assistant","content":null},'
          '"finish_reason":"length"}]}';
      final client = _FakeHttpClient((_) async => _jsonResponse(body));
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final error = await _futureError(
        service.sendMessage(
          history: const [],
          newMessage: 'hello',
          model: flashModelId,
        ),
      );

      expect(error, isNotNull);
      expect(
        ChatErrorClassifier.friendly(error.toString()),
        'The model used its full response budget. Please try again.',
      );
    });
  });

  // SECTION: error-body parsing (contract v1.1.0)
  group('OpenRouterService error-body parsing (contract v1.1.0)', () {
    test(
      'maps the verbatim harness-gate 403 body to the harness-gate copy',
      () async {
        final client = _FakeHttpClient(
          (_) async => _sseResponse(harnessGateBody, statusCode: 403),
        );
        final service = OpenRouterService(client: client, apiKey: testApiKey);

        final error = await _streamError(
          service.sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: proModelId,
          ),
        );

        expect(error, isNotNull);
        final friendly = ChatErrorClassifier.friendly(error.toString());
        expect(
          friendly,
          "This model is restricted by its provider to certain AI tools on OpenRouter's free tier. Please pick another model.",
        );
        // The retired generic decline copy must never appear (plan §6-P3
        // acceptance criterion 6).
        expect(friendly, isNot(contains('rephrase')));
        expect(friendly, isNot(contains('declined')));
      },
    );

    test('maps a 403 budget body to the spending-limit copy', () async {
      const body =
          '{"error":{"code":403,"message":"Key spending limit reached",'
          '"metadata":{"limit_source":"openrouter_key_limit"}}}';
      final client = _FakeHttpClient(
        (_) async => _sseResponse(body, statusCode: 403),
      );
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final error = await _streamError(
        service.sendMessageStream(
          history: const [],
          newMessage: 'hello',
          model: proModelId,
        ),
      );

      expect(error, isNotNull);
      final friendly = ChatErrorClassifier.friendly(error.toString());
      expect(
        friendly,
        "Your OpenRouter key has reached its spending limit. Raise or remove the key's limit in the OpenRouter dashboard, then try again.",
      );
      // Precedence: never the moderation, permission or retired decline rows.
      expect(friendly, isNot(contains('safety layer')));
      expect(friendly, isNot(contains('restricted from this request')));
      expect(friendly, isNot(contains('declined')));
    });

    test('maps a 403 moderation body to the safety-layer copy', () async {
      const body =
          '{"error":{"code":403,"message":"Request blocked: unsafe content",'
          '"metadata":{"error_type":"content_policy_violation",'
          '"provider_name":"some-provider"}}}';
      final client = _FakeHttpClient(
        (_) async => _sseResponse(body, statusCode: 403),
      );
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final error = await _streamError(
        service.sendMessageStream(
          history: const [],
          newMessage: 'hello',
          model: proModelId,
        ),
      );

      expect(error, isNotNull);
      expect(
        ChatErrorClassifier.friendly(error.toString()),
        "The AI service declined this request: the provider's safety layer blocked it. Please try again or switch models.",
      );
    });

    test('maps a residual 403 body to the permission copy', () async {
      const body = '{"error":{"code":403,"message":"Forbidden"}}';
      final client = _FakeHttpClient(
        (_) async => _sseResponse(body, statusCode: 403),
      );
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final error = await _streamError(
        service.sendMessageStream(
          history: const [],
          newMessage: 'hello',
          model: proModelId,
        ),
      );

      expect(error, isNotNull);
      expect(
        ChatErrorClassifier.friendly(error.toString()),
        'Your OpenRouter account or API key is restricted from this request. Check your OpenRouter account settings or switch models.',
      );
    });

    test(
      'classifies a 400 with routing metadata through the metadata rows',
      () async {
        const body =
            '{"error":{"code":400,"message":"routing failed","metadata":'
            '{"routing_funnel":[{"step":"Initial Endpoints","endpoint_count":1}],'
            '"failed_routing_step":"Gate Free Endpoints by Agentic Harness"}}}';
        final client = _FakeHttpClient(
          (_) async => _sseResponse(body, statusCode: 400),
        );
        final service = OpenRouterService(client: client, apiKey: testApiKey);

        final error = await _streamError(
          service.sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: proModelId,
          ),
        );

        expect(error, isNotNull);
        // A routing-class failure is never described as a payload defect.
        expect(
          ChatErrorClassifier.friendly(error.toString()),
          "This model is restricted by its provider to certain AI tools on OpenRouter's free tier. Please pick another model.",
        );
        expect(
          ChatErrorClassifier.friendly(error.toString()),
          isNot('The selected AI model failed to respond. Please try again.'),
        );
      },
    );

    test('falls back to the 4xx copy for an unmatched routing step', () async {
      const body =
          '{"error":{"code":400,"message":"no endpoint matched","metadata":'
          '{"routing_funnel":[{"step":"Initial Endpoints","endpoint_count":0}],'
          '"failed_routing_step":"Some Other Step"}}}';
      final client = _FakeHttpClient(
        (_) async => _sseResponse(body, statusCode: 400),
      );
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final error = await _streamError(
        service.sendMessageStream(
          history: const [],
          newMessage: 'hello',
          model: proModelId,
        ),
      );

      expect(error, isNotNull);
      expect(
        ChatErrorClassifier.friendly(error.toString()),
        'The selected AI model failed to respond. Please try again.',
      );
      // The parsed fields are still carried — never lost.
      final exception = error! as OpenRouterServiceException;
      expect(exception.errorBody?.code, 400);
      expect(exception.errorBody?.hasRoutingMetadata, isTrue);
      expect(exception.errorBody?.failedRoutingStep, 'Some Other Step');
    });

    test(
      'maps a 200 body holding only an error object through the table',
      () async {
        final client = _FakeHttpClient(
          (_) async => _jsonResponse(harnessGateBody, statusCode: 200),
        );
        final service = OpenRouterService(client: client, apiKey: testApiKey);

        final error = await _futureError(
          service.sendMessage(
            history: const [],
            newMessage: 'hello',
            model: proModelId,
          ),
        );

        expect(error, isNotNull);
        expect(error.toString(), isNot(contains('invalid response body')));
        expect(
          ChatErrorClassifier.friendly(error.toString()),
          "This model is restricted by its provider to certain AI tools on OpenRouter's free tier. Please pick another model.",
        );
      },
    );

    test('maps a mid-stream error event through the same rows', () async {
      final body =
          'data: {"error":{"code":403,"message":"nvidia/nemotron-3-ultra-550b-a55b:free '
          'is only available on agentic harnesses.","metadata":'
          '{"failed_routing_step":"Gate Free Endpoints by Agentic Harness"}},'
          '"choices":[{"delta":{},"finish_reason":"error"}]}\n\n';
      final client = _FakeHttpClient((_) async => _sseResponse(body));
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final error = await _streamError(
        service.sendMessageStream(
          history: const [],
          newMessage: 'hello',
          model: proModelId,
        ),
      );

      expect(error, isNotNull);
      expect(
        ChatErrorClassifier.friendly(error.toString()),
        "This model is restricted by its provider to certain AI tools on OpenRouter's free tier. Please pick another model.",
      );
    });

    test(
      'keeps the generic 5xx copy for a 500-class mid-stream code',
      () async {
        final body =
            'data: {"error":{"code":500,"message":"upstream exploded"},'
            '"choices":[{"delta":{},"finish_reason":"error"}]}\n\n';
        final client = _FakeHttpClient((_) async => _sseResponse(body));
        final service = OpenRouterService(client: client, apiKey: testApiKey);

        final error = await _streamError(
          service.sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: proModelId,
          ),
        );

        expect(error, isNotNull);
        expect(
          ChatErrorClassifier.friendly(error.toString()),
          'The AI service is temporarily unavailable. Please try again.',
        );
      },
    );

    test(
      'carries the parsed body on the failure and never logs the key',
      () async {
        final logs = <String>[];
        final originalPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };

        final client = _FakeHttpClient(
          (_) async => _sseResponse(harnessGateBody, statusCode: 403),
        );
        final service = OpenRouterService(client: client, apiKey: testApiKey);

        Object? error;
        try {
          error = await _streamError(
            service.sendMessageStream(
              history: const [],
              newMessage: 'hello',
              model: proModelId,
            ),
          );
        } finally {
          debugPrint = originalPrint;
        }

        expect(error, isA<OpenRouterServiceException>());
        final exception = error! as OpenRouterServiceException;
        expect(exception.errorBody?.code, 403);
        expect(
          exception.errorBody?.message,
          contains('only available on agentic harnesses'),
        );
        expect(
          exception.errorBody?.metadata?['failed_routing_step'],
          'Gate Free Endpoints by Agentic Harness',
        );
        expect(exception.errorBody?.hasRoutingMetadata, isTrue);
        // The raw provider message reaches the debug log — the key never does.
        final log = logs.join('\n');
        expect(log, contains('only available on agentic harnesses'));
        expect(log, isNot(contains(testApiKey)));
        expect(exception.message, isNot(contains(testApiKey)));
      },
    );
  });

  // SECTION: cancel + retry behaviour
  group('OpenRouterService cancel and retries', () {
    test('cancel stops the stream without yielding late content', () async {
      final controller = StreamController<List<int>>();
      final client = _FakeHttpClient(
        (_) async => http.StreamedResponse(controller.stream, 200),
      );
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final emitted = <String>[];
      final done = Completer<void>();
      final subscription = service
          .sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: flashModelId,
          )
          .listen(
            emitted.add,
            onError: (Object e) {
              if (!done.isCompleted) done.completeError(e);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
          );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      service.cancelGeneration();
      controller.add(utf8.encode(_sseChunk('late')));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await controller.close();
      await done.future;
      await subscription.cancel();

      expect(emitted, isEmpty);
    });

    test('honors Retry-After on 429 and retries the request', () async {
      var calls = 0;
      final client = _FakeHttpClient((_) async {
        calls++;
        if (calls == 1) {
          return _jsonResponse(
            '{"error":{"code":429,"message":"slow down"}}',
            statusCode: 429,
            headers: const {'retry-after': '0'},
          );
        }
        return _jsonResponse(
          '{"choices":[{"message":{"role":"assistant","content":"recovered"},'
          '"finish_reason":"stop"}]}',
        );
      });
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final answer = await service.sendMessage(
        history: const [],
        newMessage: 'hello',
        model: flashModelId,
      );

      expect(answer, 'recovered');
      expect(client.requests.length, 2);
    });

    test('surfaces the rate-limit copy when every attempt is limited', () async {
      final client = _FakeHttpClient(
        (_) async => _jsonResponse(
          '{"error":{"code":429,"message":"slow down"}}',
          statusCode: 429,
          headers: const {'retry-after': '0'},
        ),
      );
      final service = OpenRouterService(client: client, apiKey: testApiKey);

      final error = await _futureError(
        service.sendMessage(
          history: const [],
          newMessage: 'hello',
          model: flashModelId,
        ),
      );

      expect(error, isNotNull);
      expect(client.requests.length, 3);
      expect(
        ChatErrorClassifier.friendly(error.toString()),
        'Cloud chat is rate limited (free tier: 20 requests/min, 50/day). Wait a moment and try again.',
      );
    });
  });

  group('OnlineAIService dispatch — OpenRouter models', () {
    late _RecordingOpenRouterService openRouter;
    late OnlineAIService online;

    setUp(() {
      openRouter = _RecordingOpenRouterService();
      online = OnlineAIService(
        GroqService(),
        openRouter,
        PollinationsService(),
        HuggingFaceImageService(),
      );
    });

    test('routes each enum value to its contract model id', () async {
      await online.sendMessage(
        history: const [],
        newMessage: 'hello',
        model: AIModel.openrouterFlash,
      );
      await online.sendMessage(
        history: const [],
        newMessage: 'hello',
        model: AIModel.openrouterPro,
      );

      expect(openRouter.sentModels, [flashModelId, proModelId]);
    });

    test('streams through the OpenRouter service with the model id', () async {
      final chunks = await online
          .sendMessageStream(
            history: const [],
            newMessage: 'hello',
            model: AIModel.openrouterFlash,
          )
          .toList();

      expect(chunks, ['ok']);
      expect(openRouter.streamedModels, [flashModelId]);
    });

    test('cancelActiveGeneration cancels the OpenRouter request', () {
      online.cancelActiveGeneration();
      expect(openRouter.cancelled, isTrue);
    });
  });
}
