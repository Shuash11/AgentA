import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/local_message_dao.dart';
import 'package:aiproject/data/local/offline_model_dao.dart';
import 'package:aiproject/data/models/chat_message_model.dart';
import 'package:aiproject/presentation/chats/chats.dart';
import 'package:aiproject/services/ai/gemma_service.dart';
import 'package:aiproject/services/ai/offline_model_spec.dart';

void main() {
  late GemmaService service;

  setUp(() {
    service = GemmaService();
  });

  group('GemmaService.classifyLoadError', () {
    test('maps missing-model signals to not-installed', () {
      expect(
        service.classifyLoadErrorForTest(
          StateError('Bad state: No active model'),
          false,
        ),
        'Offline model is not installed.',
      );
      expect(
        service.classifyLoadErrorForTest(
          Exception('model not installed'),
          false,
        ),
        'Offline model is not installed.',
      );
      expect(
        service.classifyLoadErrorForTest(
          Exception('No such file or directory'),
          false,
        ),
        'Offline model is not installed.',
      );
      expect(
        service.classifyLoadErrorForTest(Exception('404 not found'), false),
        'Offline model is not installed.',
      );
    });

    test('failed rehydration means not-installed regardless of text', () {
      expect(
        service.classifyLoadErrorForTest(Exception('boom'), true),
        'Offline model is not installed.',
      );
    });

    test('null-mentioning errors are NOT misclassified as not-installed', () {
      // Phase 2 regression lock: the old raw.contains('null') branch is gone.
      expect(
        service.classifyLoadErrorForTest(
          Exception('Null check operator used on a null value'),
          false,
        ),
        'Offline model failed to load.',
      );
    });

    test('generic failures map to failed-to-load', () {
      expect(
        service.classifyLoadErrorForTest(Exception('boom'), false),
        'Offline model failed to load.',
      );
    });

    test('typed download errors fall through to failed-to-load here', () {
      // Download UX is owned by ModelDownloadService's typed mapping;
      // this classifier only handles non-download load failures.
      const typed = DownloadException(
        DownloadError.network('connection reset'),
      );
      expect(
        service.classifyLoadErrorForTest(typed, false),
        'Offline model failed to load.',
      );
    });
  });

  group('GemmaService.endsAtNaturalBreak', () {
    test('punctuation endings break', () {
      for (final token in ['hello.', 'a,', 'x:', 'y;', 'wow!', 'really?']) {
        expect(service.endsAtNaturalBreakForTest(token), isTrue, reason: token);
      }
      // A trailing newline still flushes when punctuation precedes it —
      // trimRight runs first, so the '.' decides here.
      expect(service.endsAtNaturalBreakForTest('word.\n'), isTrue);
    });

    test('mid-word tokens do not break', () {
      expect(service.endsAtNaturalBreakForTest('abc'), isFalse);
      expect(service.endsAtNaturalBreakForTest('word '), isFalse);
      expect(service.endsAtNaturalBreakForTest(''), isFalse);
      expect(service.endsAtNaturalBreakForTest('   '), isFalse);
      // trimRight strips trailing newlines before the check, so a bare
      // newline never breaks on its own (the '\n' arm is inert).
      expect(service.endsAtNaturalBreakForTest('line\n'), isFalse);
      expect(service.endsAtNaturalBreakForTest('\n'), isFalse);
    });
  });

  group('GemmaService.load shape (cycle-38 P2)', () {
    test('load shape and identity match the offline-model contract', () {
      final source = File(
        'lib/services/ai/gemma_service.dart',
      ).readAsStringSync();
      // Load shape (cycle-46 speed ruling): the 1500-token ACTIVE context
      // window on the CPU backend (chosen between the two officially
      // benchmarked points of the shipped q8_ekv4096.task — 4096 → 26.1 t/s,
      // 1280 → 34.3 t/s; 1500 keeps most of the gain with message headroom).
      expect(source, contains('static const int _maxTokens = 1500;'));
      expect(source, contains('maxTokens: _maxTokens'));
      expect(source, contains('preferredBackend: PreferredBackend.cpu'));
      // Identity coherence across the files that carry it (cycle-42 P2b: the
      // spec table is the ONLY place the identity string is written — the
      // consumers resolve the app's offline-model identity, which is
      // app-wide).
      expect(source, contains('OfflineModelSpecTable.appIdentity'));
      final service = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      expect(
        'setModelReady(modelType: spec.identity)'.allMatches(service).length,
        2,
      );
      final dao = File(
        'lib/data/local/offline_model_dao.dart',
      ).readAsStringSync();
      expect(
        "'model_type': modelType ?? OfflineModelSpecTable.appIdentity"
            .allMatches(dao)
            .length,
        2,
      );
      // No consumer carries a hardcoded identity any more.
      for (final consumer in [source, service, dao]) {
        expect(consumer, isNot(contains("'gemma-4-e2b-it'")));
        expect(consumer, isNot(contains("'qwen2.5-1.5b-it'")));
      }
    });
  });

  group('GemmaService load recovery (cycle-38 P6)', () {
    late Database db;
    late OfflineModelDao dao;

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
      dao = OfflineModelDao();
    });

    tearDown(() {
      service.chatOverrideForTest = null;
    });

    test('a failed load leaves a clean, retryable state', () async {
      service.chatOverrideForTest = () async => throw Exception('engine init');

      await expectLater(service.loadInstalled(), throwsA(isA<Exception>()));

      expect(service.isReady, isFalse);
      expect(service.state, OfflineModelState.loadFailed);
      expect(service.canRetryLoad, isTrue);
      // The classified reason is exposed; the raw exception never is.
      expect(service.lastError, 'Offline model failed to load.');
      expect(service.lastError, isNot(contains('engine init')));
    });

    test('a retry succeeds WITHOUT an app restart', () async {
      var attempts = 0;
      service.chatOverrideForTest = () async {
        attempts++;
        if (attempts == 1) throw Exception('engine init');
        return _fakeChat();
      };

      await expectLater(service.loadInstalled(), throwsA(isA<Exception>()));
      expect(service.isReady, isFalse);

      // Same service instance — no restart, no new provider.
      await service.loadInstalled();

      expect(attempts, 2);
      expect(service.isReady, isTrue);
      expect(service.state, OfflineModelState.loaded);
      expect(service.canRetryLoad, isFalse);
      expect(service.lastError, isNull);
    });

    test('a successful retry reaches a working chat', () async {
      var attempts = 0;
      service.chatOverrideForTest = () async {
        attempts++;
        if (attempts == 1) throw Exception('engine init');
        return _fakeChat();
      };

      await expectLater(service.loadInstalled(), throwsA(isA<Exception>()));

      final reply = await service.sendMessage(
        history: const [],
        newMessage: 'ping',
      );

      expect(reply, 'pong');
    });

    test(
      'the DAO records the error row on failure and ready again on retry',
      () async {
        // Installed: the install wrote the ready row (with the download
        // marker) before the load was ever attempted.
        await dao.setModelReady(modelType: OfflineModelSpecTable.appIdentity);
        service.chatOverrideForTest = () async =>
            throw Exception('engine init');

        await expectLater(service.loadInstalled(), throwsA(isA<Exception>()));

        var row = await dao.getModelStatus();
        expect(row, isNotNull);
        expect(row!['status'], 'error');
        expect(row['model_type'], OfflineModelSpecTable.appIdentity);
        // The friendly reason only — never the raw exception text.
        expect(row['version'], 'Offline model failed to load.');
        expect(row['version'], isNot(contains('engine init')));
        // The download marker survives → the asset is still INSTALLED, so the
        // UI must offer RETRY LOAD and never a re-download.
        expect(row['downloaded_at'], isNotNull);
        expect(await dao.isModelInstalled(), isTrue);

        service.chatOverrideForTest = () async => _fakeChat();
        await service.loadInstalled();

        row = await dao.getModelStatus();
        expect(row!['status'], 'ready');
        expect(row['version'], isNull);
        expect(await dao.isModelInstalled(), isTrue);
      },
    );

    test(
      'a missing asset is classified as missing, not as a retryable load',
      () async {
        // No row at all → the model was never downloaded, so a retry cannot
        // help: the user needs the download.
        service.chatOverrideForTest = () async =>
            throw StateError('Bad state: No active model');

        await expectLater(service.loadInstalled(), throwsA(isA<StateError>()));

        expect(service.state, OfflineModelState.modelMissing);
        expect(service.canRetryLoad, isFalse);
        expect(service.lastError, 'Offline model is not installed.');
        // The error row carries no download marker → genuinely not installed.
        final row = await dao.getModelStatus();
        expect(row!['status'], 'error');
        expect(row['downloaded_at'], isNull);
        expect(await dao.isModelInstalled(), isFalse);
      },
    );

    test(
      'an INSTALLED asset whose load reports a missing state stays retryable (S7)',
      () async {
        // The asset IS on the device (the install wrote the ready row) but
        // the engine reported a bad state. Routing this to the download gate
        // would strand the user behind a spurious 2.6 GB re-download of a
        // model the device already has — the durable marker outranks the
        // in-memory verdict.
        await dao.setModelReady(modelType: OfflineModelSpecTable.appIdentity);
        service.chatOverrideForTest = () async =>
            throw StateError('Bad state: No active model');

        await expectLater(service.loadInstalled(), throwsA(isA<StateError>()));

        expect(service.state, OfflineModelState.loadFailed);
        expect(service.canRetryLoad, isTrue);
        expect(service.lastError, 'Offline model failed to load.');
        // The download marker survives the error row → still installed.
        final row = await dao.getModelStatus();
        expect(row!['status'], 'error');
        expect(row['downloaded_at'], isNotNull);
        expect(await dao.isModelInstalled(), isTrue);
      },
    );

    test(
      'a repeated failure stays honest and retryable (no spinner loop)',
      () async {
        await dao.setModelReady(modelType: OfflineModelSpecTable.appIdentity);
        var attempts = 0;
        service.chatOverrideForTest = () async {
          attempts++;
          throw Exception('engine init');
        };

        await expectLater(service.loadInstalled(), throwsA(isA<Exception>()));
        await expectLater(service.loadInstalled(), throwsA(isA<Exception>()));

        expect(attempts, 2);
        expect(service.isReady, isFalse);
        expect(service.state, OfflineModelState.loadFailed);
        expect(service.canRetryLoad, isTrue);
        expect(service.lastError, 'Offline model failed to load.');
        // No fake success: the row still says "error".
        final row = await dao.getModelStatus();
        expect(row!['status'], 'error');
        expect(await dao.isModelInstalled(), isTrue);
      },
    );

    test(
      'a failed load never blocks a later attempt (guard is reset)',
      () async {
        var attempts = 0;
        service.chatOverrideForTest = () async {
          attempts++;
          if (attempts == 1) throw Exception('engine init');
          return _fakeChat();
        };

        await expectLater(service.loadInstalled(), throwsA(isA<Exception>()));
        await service.loadInstalled();
        await service.loadInstalled();

        // The third call is a no-op: the model is already loaded.
        expect(attempts, 2);
      },
    );
  });

  group('OfflineModelDao installed-state (cycle-38 P6)', () {
    late Database db;
    late OfflineModelDao dao;

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
      dao = OfflineModelDao();
    });

    test('no row means not installed', () async {
      expect(await dao.isModelInstalled(), isFalse);
    });

    test('a failed DOWNLOAD means not installed', () async {
      await dao.setModelError('Download failed. Please try again.');
      expect(await dao.isModelInstalled(), isFalse);
    });

    test(
      'a failed LOAD on a downloaded model means installed-but-broken',
      () async {
        await dao.setModelReady(modelType: OfflineModelSpecTable.appIdentity);
        await dao.setModelError('Offline model failed to load.');
        expect(await dao.isModelInstalled(), isTrue);
      },
    );

    test('a reset row means not installed', () async {
      await dao.setModelReady(modelType: OfflineModelSpecTable.appIdentity);
      await dao.setModelNotInstalled();
      expect(await dao.isModelInstalled(), isFalse);
    });
  });

  group('chat offline-model action selection (cycle-38 P6)', () {
    test('installed but not loaded → Retry load', () {
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.loadFailed,
          isInstalled: true,
        ),
        OfflineModelAction.retryLoad,
      );
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.idle,
          isInstalled: true,
        ),
        OfflineModelAction.retryLoad,
      );
    });

    test('genuinely not installed → Get model', () {
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.modelMissing,
          isInstalled: false,
        ),
        OfflineModelAction.getModel,
      );
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.idle,
          isInstalled: false,
        ),
        OfflineModelAction.getModel,
      );
      // A load that failed while NO asset was installed still needs the
      // model — the retry cannot recover an asset that is not there.
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.loadFailed,
          isInstalled: false,
        ),
        OfflineModelAction.getModel,
      );
    });

    test('an INSTALLED model never routes to the download screen (S7)', () {
      // Even when the load blamed a missing asset, the durable marker says
      // the model is on the device: the download screen would be a no-op
      // loop (and could re-download 2.6 GB of a model already present).
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.modelMissing,
          isInstalled: true,
        ),
        OfflineModelAction.retryLoad,
      );
    });
  });

  group('cycle-38 P6 recovery wiring (source-level)', () {
    test(
      'the service records the load failure in the DAO and logs the raw class',
      () {
        final source = File(
          'lib/services/ai/gemma_service.dart',
        ).readAsStringSync();
        expect(source, contains('await _dao.setModelError(_lastError);'));
        // S4 evidence: the raw exception CLASS stays in the debug log.
        expect(source, contains(r"(type: ${e.runtimeType})"));
      },
    );

    test(
      'the gate loads the model on every branch (init, retry, post-download)',
      () {
        final source = File('lib/main.dart').readAsStringSync();
        // The post-download path performs a load attempt (it used to only
        // re-check the download state).
        expect(source, contains('Future<void> _onModelReady()'));
        expect(source, contains('await _attemptLoad();'));
        expect(source, contains('await gemmaService.loadInstalled();'));
        // The gate routes on the DURABLE installed flag, never on the
        // in-memory download status (an error row must not re-open the
        // download gate for an installed model).
        expect(source, contains('OfflineModelDao().isModelInstalled()'));
      },
    );

    test('the post-download branch itself performs the load attempt', () {
      final source = File('lib/main.dart').readAsStringSync();
      // Scoped to `_onModelReady`: the branch that runs after a download
      // must LOAD the model, not merely re-check the download state —
      // that decoupling was the dead-end (the gate declared the model
      // ready while the service never loaded it).
      final postDownload = _methodBody(source, 'Future<void> _onModelReady()');
      expect(postDownload, isNotEmpty);
      expect(postDownload, contains('await _attemptLoad();'));
      // ...and the load attempt really invokes the service.
      final attempt = _methodBody(source, 'Future<void> _attemptLoad()');
      expect(attempt, isNotEmpty);
      expect(attempt, contains('await gemmaService.loadInstalled();'));
    });

    test(
      'the chat failure copy never embeds the raw exception (debug-only)',
      () {
        final source = File(
          'lib/presentation/chats/chats.dart',
        ).readAsStringSync();
        final retry = _methodBody(source, 'Future<void> _retryLoadModel()');
        expect(retry, isNotEmpty);
        // The user-facing copy is the service's FRIENDLY reason...
        expect(retry, contains('gemmaService.lastError'));
        // ...and the raw exception only ever reaches the debug log, so the
        // S4 determination stays possible without leaking engine detail
        // into the UI.
        expect(retry, contains('if (kDebugMode)'));
        expect(
          retry,
          contains(
            "debugPrint('[Chats] offline model load retry failed: \$e')",
          ),
        );
      },
    );

    test('a repeat-failing retry keeps the retry affordance available', () {
      final source = File(
        'lib/presentation/chats/chats.dart',
      ).readAsStringSync();
      final retry = _methodBody(source, 'Future<void> _retryLoadModel()');
      expect(retry, isNotEmpty);
      // The failure branch surfaces the honest reason AND keeps an action
      // — the user is never stranded (S4-safe: no endless spinner, no
      // fake success).
      expect(retry, contains('SnackBarAction('));
      expect(retry, contains('_offlineActionLabel(action)'));
      // The loading notice is dismissed before the failure is shown, so
      // the spinner can never loop over a failed attempt.
      expect(retry, contains('messenger.hideCurrentSnackBar();'));
    });

    test(
      'the gate never routes an INSTALLED model to the download gate (S7)',
      () {
        final source = File('lib/main.dart').readAsStringSync();
        // The installed/retry branch is evaluated BEFORE the download gate.
        final retryIndex = source.indexOf('_isInstalled ||');
        final downloadIndex = source.indexOf('DownloadPromptScreen(');
        expect(retryIndex, greaterThan(-1));
        expect(downloadIndex, greaterThan(retryIndex));
      },
    );

    test('the chat card routes by state and never dead-ends', () {
      final source = File(
        'lib/presentation/chats/chats.dart',
      ).readAsStringSync();
      expect(source, contains("'Retry load'"));
      expect(source, contains("'Get model'"));
      // The retry really calls the service load.
      expect(source, contains('await gemmaService.loadInstalled();'));
    });
  });

  group('chat-creation seam (contract v1.1.0 §11)', () {
    test(
      'every engine chat creation passes enableThinking: false EXPLICITLY',
      () {
        // The seam is the ENGINE-chat creation — the call that creates a
        // chat on the active model. (The transcript's chat-SESSION
        // creation in the repository is a different call and takes no
        // engine argument, so the scan is scoped to the AI service layer.)
        //
        // The plugin call cannot be intercepted without a seam in lib/ (off
        // limits here), so the seam is asserted AT ITS SOURCE — the same
        // way this file already asserts the other createChat arguments
        // (the load shape above).
        final sites = _engineChatCreationSites();

        // Every creation site is covered (criterion 7): there is exactly
        // one, and it is the service's.
        expect(sites, hasLength(1));
        expect(
          sites.single.file,
          endsWith('lib/services/ai/gemma_service.dart'),
        );

        final call = sites.single.arguments;
        // The argument is PRESENT and FALSE — not merely absent, never
        // defaulted (an unset kwarg lets the MODEL decide).
        expect(call, contains('enableThinking: false'));
        expect(call, isNot(contains('enableThinking: true')));
        // ...and it is passed exactly ONCE: never omitted, never doubled
        // with a contradicting value.
        expect(RegExp(r'enableThinking\s*:').allMatches(call).length, 1);
      },
    );
  });

  group('stray thinking drop (contract v1.1.0 §11)', () {
    late Database db;

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
            await db.execute('''
              CREATE TABLE messages (
                id TEXT PRIMARY KEY,
                chat_id TEXT NOT NULL,
                text TEXT NOT NULL,
                is_user INTEGER NOT NULL,
                timestamp INTEGER NOT NULL,
                is_synced INTEGER DEFAULT 0,
                is_deleted INTEGER DEFAULT 0
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

    test(
      'a stray ThinkingResponse never reaches the answer or the transcript',
      () async {
        // The engine hands the service a typed ThinkingResponse DESPITE the
        // app's explicit-false pin (the shape the step-0 smoke recorded on
        // the llama path) — the APP's seam must drop it.
        final chat = _FakeTypedChat(
          responses: const [
            ThinkingResponse('secret reasoning'),
            TextResponse('Final answer.'),
          ],
        );
        await chat.initSession();
        service.chatOverrideForTest = () async => chat;

        await service.loadInstalled();

        // The premise: the engine really did hand the service a typed
        // ThinkingResponse — so the drop below is not vacuous.
        final rawEvents = await chat.generateChatResponseAsync().toList();
        expect(rawEvents.whereType<ThinkingResponse>(), hasLength(1));

        final chunks = await service
            .sendMessageStream(history: const [], newMessage: 'hello')
            .toList();

        // The stray never reaches the surfaced answer: the stream carries
        // ONLY the final TextResponse content.
        expect(chunks, ['Final answer.']);
        final answer = chunks.join();
        expect(answer, isNot(contains('secret reasoning')));

        // ...and the transcript write path receives ONLY that content: the
        // stored row is the final answer, with nothing of the stray.
        await LocalMessageDao.instance.insert(
          ChatMessageModel(
            id: 'assistant-1',
            chatId: 'chat-1',
            text: answer,
            isUser: false,
            timestamp: DateTime(2026, 1, 1),
          ),
        );
        final stored = await LocalMessageDao.instance.getByChat('chat-1');
        expect(stored, hasLength(1));
        expect(stored.single.text, 'Final answer.');
        expect(stored.single.text, isNot(contains('secret reasoning')));
      },
    );
  });
}

/// Extracts ONE method body from [source].
///
/// A source-level assertion scoped to a method is far more faithful than one
/// scoped to the whole file: "the post-download branch performs a load" must
/// be true of `_onModelReady` itself, not of some other method that happens
/// to contain the same call.
String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) return '';
  // Methods of these classes are indented by two spaces, so the first
  // two-space closing brace ends the body (nested blocks close deeper).
  final end = source.indexOf('\n  }', start);
  if (end == -1) return '';
  return source.substring(start, end);
}

/// In-memory stand-in for the native engine's chat session.
class _FakeSession implements InferenceModelSession {
  final List<Message> queries = [];

  @override
  Future<String> getResponse() async => 'pong';

  @override
  Stream<String> getResponseAsync() async* {
    yield 'pong';
  }

  @override
  Future<int> sizeInTokens(String text) async => text.length;

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

/// A ready chat backed by [_FakeSession] — the injected "engine" of the
/// load-retry tests. The session is initialised because [InferenceChat]
/// reads its `late` session on the first turn.
Future<InferenceChat> _fakeChat() async {
  final chat = InferenceChat(
    sessionCreator: () async => _FakeSession(),
    maxTokens: 2048,
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  );
  await chat.initSession();
  return chat;
}

/// A chat whose stream carries the scripted RESPONSE EVENTS straight onto
/// the wire — including a typed [ThinkingResponse], the shape the llama
/// connector emits natively (the step-0 smoke recorded branch (a)).
///
/// The engine-side hide is BYPASSED on purpose: the app pins
/// `enableThinking: false`, but a stray that arrives ANYWAY must still be
/// dropped by the APP's seam (contract v1.1.0 §11 `p2_chat_send_path`).
class _FakeTypedChat extends InferenceChat {
  final List<ModelResponse> responses;

  _FakeTypedChat({required this.responses})
    : super(
        sessionCreator: () async => _FakeSession(),
        maxTokens: 2048,
        modelType: ModelType.qwen,
        fileType: ModelFileType.task,
        // The chat carries the app's own pin — thinking OFF, explicitly.
        enableThinking: false,
      );

  @override
  Stream<ModelResponse> generateChatResponseAsync() async* {
    for (final response in responses) {
      yield response;
    }
  }
}

/// One engine-chat creation site: the file it lives in and the ARGUMENT
/// LIST of the call.
class _CreationSite {
  final String file;
  final String arguments;

  _CreationSite(this.file, this.arguments);
}

/// The engine-chat creation sites in the AI service layer: every
/// `createChat(` / `openChat(` call, with the argument list of the call.
///
/// The argument list is what the seam is about, so the extraction keeps the
/// comments inside the call — a value that only ever appears in a comment
/// is not an argument.
List<_CreationSite> _engineChatCreationSites() {
  final sites = <_CreationSite>[];
  final pattern = RegExp(r'\.(?:createChat|openChat)\s*\(');
  for (final file in Directory(
    'lib/services/ai',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // A mention inside a comment is not a call site.
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
      if (!pattern.hasMatch(line)) continue;
      sites.add(
        _CreationSite(
          file.path.replaceAll('\\', '/'),
          _callArguments(lines, i),
        ),
      );
    }
  }
  return sites;
}

/// The argument list of the call that starts on [lineIndex]: every line up
/// to the call's closing parenthesis.
String _callArguments(List<String> lines, int lineIndex) {
  final buffer = <String>[];
  var depth = 0;
  for (var i = lineIndex; i < lines.length; i++) {
    final line = lines[i];
    buffer.add(line);
    for (final char in line.split('')) {
      if (char == '(') depth++;
      if (char == ')') depth--;
    }
    if (depth <= 0) break;
  }
  return buffer.join('\n');
}
