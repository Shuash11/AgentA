import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/models/chat_message_model.dart';
import 'package:aiproject/services/ai/gemma_service.dart';

ChatMessageModel _msg(String text, {bool isUser = true, String id = 'm'}) {
  return ChatMessageModel(
    id: id,
    chatId: 'c',
    text: text,
    isUser: isUser,
    timestamp: DateTime(2026, 1, 1),
  );
}

/// A recording stand-in for the native engine's chat session.
///
/// Every chunk the service stages lands here, so the staged protocol is
/// observable end to end. The pinned core's `clearHistory()` CLOSES the
/// session and creates a fresh one (`chat.dart:1101-1112`), so the engine's
/// session-creator call count is the wipe counter.
class _RecordingSession implements InferenceModelSession {
  _RecordingSession(this.engine);

  final _FakeEngine engine;

  /// The chunks staged into THIS session, in order.
  final List<Message> queries = [];

  @override
  Future<String> getResponse() async {
    if (engine.failOnGenerate) throw Exception('native engine exploded');
    return 'pong';
  }

  @override
  Stream<String> getResponseAsync() async* {
    if (engine.failOnGenerate) throw Exception('native engine exploded');
    yield 'pong';
  }

  @override
  Future<int> sizeInTokens(String text) async => 1;

  @override
  Future<void> addQueryChunk(Message message) async {
    queries.add(message);
  }

  @override
  Future<void> stopGeneration() async {}

  @override
  SessionMetrics getSessionMetrics() => SessionMetrics();

  @override
  Future<void> close() async {}
}

/// The fake engine: a REAL `InferenceChat` over recording sessions.
///
/// The fake constructs `InferenceChat` DIRECTLY, so it inherits the class
/// default `tokenBuffer` (2000, `chat.dart:94`) instead of createChat's 256
/// (`flutter_edge_ai_interface.dart:362`). That mismatch is RECORDED AND
/// ACCEPTED (the cycle-45 ruling): the plugin's rotation is post-response-only
/// and the per-send wipe discards it, so it is unobservable. These tests
/// therefore never assert rotation behaviour — they assert the protocol.
class _FakeEngine {
  final List<_RecordingSession> sessions = [];

  /// How many times the plugin asked for a session — 1 for the initial
  /// session plus 1 per `clearHistory()` wipe.
  int sessionCreations = 0;

  /// Makes the generation fail, so the failure path can be observed.
  bool failOnGenerate = false;

  late final InferenceChat chat;

  Future<InferenceChat> build() async {
    chat = InferenceChat(
      sessionCreator: () async {
        sessionCreations++;
        final session = _RecordingSession(this);
        sessions.add(session);
        return session;
      },
      maxTokens: 2048,
      modelType: ModelType.qwen,
      fileType: ModelFileType.task,
    );
    await chat.initSession();
    return chat;
  }
}

void main() {
  late Database db;
  late GemmaService service;
  late _FakeEngine engine;

  setUpAll(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE offline_model_status (
              id INTEGER PRIMARY KEY,
              model_type TEXT NOT NULL,
              status TEXT NOT NULL,
              downloaded_at INTEGER,
              file_path TEXT,
              version TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    DatabaseHelper.testDatabase = db;
  });

  tearDownAll(() async {
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  setUp(() async {
    await db.delete('offline_model_status');
    service = GemmaService();
    engine = _FakeEngine();
    final chat = await engine.build();
    service.chatOverrideForTest = () async => chat;
    await service.loadInstalled();
  });

  tearDown(() {
    service.chatOverrideForTest = null;
  });

  group(
    'the per-send turn protocol — stateless (cycle-46, owner directive)',
    () {
      test(
        'a send wipes once and stages exactly ONE chunk: the new message',
        () async {
          await service.sendMessage(
            history: const [],
            newMessage: 'convert this binary 101 into decimal',
          );

          // One session per wipe: the initial one plus the one `clearHistory()`
          // creates. The wipe happened BEFORE anything was staged, so the first
          // session holds no chunks at all.
          expect(engine.sessionCreations, 2);
          expect(engine.sessions, hasLength(2));
          expect(engine.sessions.first.queries, isEmpty);

          // Exactly ONE chunk — the new message. No history, no priming.
          final staged = engine.sessions.last.queries;
          expect(staged, hasLength(1));
          expect(staged.single.isUser, isTrue);
          expect(staged.single.text, 'convert this binary 101 into decimal');
        },
      );

      test('two consecutive sends stay STATELESS — the model never sees the '
          'prior turns', () async {
        await service.sendMessage(
          history: const [],
          newMessage: 'my name is tester',
        );

        // The second send's history holds the finished first turn plus the new
        // question — the shape the chat screen hands to the service. The model
        // must NEVER see it: every send is self-contained.
        final history = [
          _msg('my name is tester', id: 'u1'),
          _msg('Nice to meet you, tester!', isUser: false, id: 'a1'),
          _msg('what is my name', id: 'u2'),
        ];
        await service.sendMessage(
          history: history,
          newMessage: 'what is my name',
        );

        // No EXTRA session recreation across the two sends: the initial session
        // plus exactly one wipe per send.
        expect(engine.sessionCreations, 3);
        expect(engine.sessions, hasLength(3));

        final staged = engine.sessions.last.queries;
        expect(staged, hasLength(1));
        expect(staged.single.text, 'what is my name');
        // The prior turns are ABANDONED — not even the user's own name is
        // replayed into the prompt.
        expect(staged.single.text, isNot(contains('my name is tester')));
        expect(staged.single.text, isNot(contains('Nice to meet you')));
      });

      test('a long message goes out intact as the single chunk', () async {
        // A message far larger than any historical staged budget: it still
        // goes out whole — there is no priming to crowd it out.
        final longMessage = 'q' * 6000;
        await service.sendMessage(history: const [], newMessage: longMessage);

        final staged = engine.sessions.last.queries;
        expect(staged, hasLength(1));
        expect(staged.single.text, longMessage);
      });

      test('the stream path runs the same per-send protocol', () async {
        final history = [
          _msg('my name is tester', id: 'u1'),
          _msg('what is my name', id: 'u2'),
        ];
        final chunks = <String>[];
        await for (final chunk in service.sendMessageStream(
          history: history,
          newMessage: 'what is my name',
        )) {
          chunks.add(chunk);
        }
        expect(chunks.join(), 'pong');

        // The same single chunk, after the same single wipe.
        expect(engine.sessionCreations, 2);
        final staged = engine.sessions.last.queries;
        expect(staged, hasLength(1));
        expect(staged.single.isUser, isTrue);
        expect(staged.single.text, 'what is my name');
      });
    },
  );

  group('the [System: …] prefix rides the first (only) chunk', () {
    test('the protocol order is wipe → new message (source-level)', () {
      final source = File(
        'lib/services/ai/gemma_service.dart',
      ).readAsStringSync();
      final stage = _methodBody(source, 'Future<void> _stageTurn(');
      expect(stage, isNotEmpty);

      // The ORDER is normative: the wipe, then the new-message chunk — the
      // FIRST and ONLY chunk of the fresh session. No priming chunk exists.
      final wipe = stage.indexOf('await chat.clearHistory();');
      final message = stage.indexOf(
        'Message.text(text: stagedMessage, isUser: true)',
      );
      expect(wipe, greaterThan(-1));
      expect(message, greaterThan(wipe));
      expect(stage, isNot(contains('primingText')));
    });

    test('both send paths run the same protocol (source-level)', () {
      final source = File(
        'lib/services/ai/gemma_service.dart',
      ).readAsStringSync();
      expect(
        _methodBody(source, 'Future<String> sendMessage({'),
        contains(
          'await _stageTurn(chat, history: history, newMessage: newMessage);',
        ),
      );
      expect(
        _methodBody(source, 'Stream<String> sendMessageStream({'),
        contains(
          'await _stageTurn(chat, history: history, newMessage: newMessage);',
        ),
      );
    });

    test('the prefix mechanics are recorded against the pinned plugin', () {
      final source = File(
        'lib/services/ai/gemma_service.dart',
      ).readAsStringSync();
      // The prefix is the PLUGIN's: on .task it prepends the system
      // instruction AS TEXT to the FIRST user chunk staged in the session
      // (native template injection is litertlm-only) — with the priming
      // gone, that first chunk IS the new message.
      expect(source, contains('mobile_inference_session.dart:40-46'));
      expect(source, contains('FIRST user chunk'));
      expect(source, contains('FIRST and ONLY chunk'));
      // The instruction the prefix carries is still the spec-driven one.
      expect(
        source,
        contains('systemInstruction: OfflineModelSpecTable.systemInstruction'),
      );
    });

    test('the app never writes the prefix into a staged chunk', () async {
      await service.sendMessage(
        history: [_msg('my name is tester', id: 'u1')],
        newMessage: 'what is my name',
      );

      for (final chunk in engine.sessions.last.queries) {
        expect(chunk.text, isNot(contains('[System:')));
      }
    });
  });

  group('the reset seam, failure paths and public surface', () {
    test('resetSession stays a bare wipe — no staged chunks', () async {
      await service.sendMessage(history: const [], newMessage: 'hello');
      final creationsBefore = engine.sessionCreations;

      await service.resetSession();

      // The wipe recreates the session and stages NOTHING: staging is
      // per-SEND, and a send stages exactly its own message.
      expect(engine.sessionCreations, creationsBefore + 1);
      expect(engine.sessions.last.queries, isEmpty);
    });

    test('a reset leaves no cross-chat leak', () async {
      await service.sendMessage(
        history: [_msg('secret from chat A', id: 'a')],
        newMessage: 'hello',
      );
      await service.resetSession();
      await service.sendMessage(
        history: [_msg('hello from chat B', id: 'b')],
        newMessage: 'hi',
      );

      // The last session holds EXACTLY the new message — nothing from chat A,
      // not even role-marked history.
      final staged = engine.sessions.last.queries;
      expect(staged, hasLength(1));
      expect(staged.single.text, 'hi');
      expect(staged.single.text, isNot(contains('secret from chat A')));
      expect(staged.single.text, isNot(contains('hello from chat B')));
    });

    test('a generation failure still surfaces the friendly copy', () async {
      engine.failOnGenerate = true;

      await expectLater(
        service.sendMessage(history: const [], newMessage: 'hi'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Offline AI could not respond. Please try again.'),
          ),
        ),
      );
    });

    test('the load retry affordance is untouched', () async {
      final failing = GemmaService();
      failing.chatOverrideForTest = () async => throw Exception('engine init');

      await expectLater(failing.loadInstalled(), throwsA(isA<Exception>()));

      expect(failing.state, OfflineModelState.loadFailed);
      expect(failing.canRetryLoad, isTrue);
      expect(failing.lastError, 'Offline model failed to load.');
      failing.chatOverrideForTest = null;
    });

    test('the send paths keep their public signatures', () {
      final source = File(
        'lib/services/ai/gemma_service.dart',
      ).readAsStringSync();
      final send = _methodBody(source, 'Future<String> sendMessage({');
      expect(send, contains('required List<ChatMessageModel> history,'));
      expect(send, contains('required String newMessage,'));
      final stream = _methodBody(source, 'Stream<String> sendMessageStream({');
      expect(stream, contains('required List<ChatMessageModel> history,'));
      expect(stream, contains('required String newMessage,'));

      // The call sites keep their signatures too.
      final offline = File(
        'lib/services/ai/offline_ai_service.dart',
      ).readAsStringSync();
      expect(
        offline,
        contains(
          '_gemma.sendMessage(history: history, newMessage: newMessage)',
        ),
      );
      expect(
        offline,
        contains(
          '_gemma.sendMessageStream(history: history, newMessage: newMessage)',
        ),
      );
    });
  });
}

/// Extracts ONE method body from [source].
///
/// A source-level assertion scoped to a method is more faithful than one
/// scoped to the whole file: the protocol's ORDER must be true of
/// `_stageTurn` itself, not of some other method that happens to contain the
/// same call. The body is found by brace counting from the body's opening
/// brace — the named-parameter list's own brace is not the body.
String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) return '';
  // The body opens at the first '{' AFTER the signature's closing paren.
  final parenEnd = source.indexOf(')', start + signature.length);
  if (parenEnd == -1) return '';
  final open = source.indexOf('{', parenEnd);
  if (open == -1) return '';
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return '';
}
