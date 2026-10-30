import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/offline_model_dao.dart';
import 'package:aiproject/data/models/chat_message_model.dart';
import 'package:aiproject/presentation/chats/chats.dart';
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

void main() {
  late GemmaService service;

  setUp(() {
    service = GemmaService();
  });

  group('GemmaService.truncateAtSentence', () {
    test('cuts at the last period boundary before the limit', () {
      const text = 'First sentence. Second sentence here and more';
      expect(service.truncateAtSentenceForTest(text, 30), 'First sentence.…');
    });

    test('prefers the latest boundary, not the first', () {
      const text = 'One. Two. Three and more words here';
      expect(service.truncateAtSentenceForTest(text, 22), 'One. Two.…');
    });

    test('cuts at question and exclamation boundaries', () {
      expect(
        service.truncateAtSentenceForTest('Really? Yes indeed and more', 20),
        'Really?…',
      );
      expect(
        service.truncateAtSentenceForTest('Wow! Amazing stuff here now', 12),
        'Wow!…',
      );
    });

    test('cuts at newline boundaries', () {
      expect(
        service.truncateAtSentenceForTest('Line one\nLine two continues', 15),
        'Line one…',
      );
    });

    test('falls back to a word boundary without sentence markers', () {
      expect(
        service.truncateAtSentenceForTest('aaa bbb ccc ddd eee fff', 10),
        'aaa bbb…',
      );
    });

    test('hard-cuts text with no spaces at all', () {
      expect(
        service.truncateAtSentenceForTest('abcdefghijklmnop', 6),
        'abcdef…',
      );
    });
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

  group('GemmaService.recentHistory', () {
    test('empty history stays empty', () {
      expect(service.recentHistoryForTest([], currentMessage: 'hi'), isEmpty);
    });

    test('filters the greeting and blank messages', () {
      final history = [
        _msg(GemmaService.greetingText, id: 'g'),
        _msg('   ', id: 'b'),
        _msg('real question', id: 'r'),
      ];
      final recent = service.recentHistoryForTest(
        history,
        currentMessage: 'next',
      );
      expect(recent.map((m) => m.id), ['r']);
    });

    test('removes a trailing duplicate of the new user message', () {
      final history = [_msg('hi', id: 'a'), _msg('current', id: 'dup')];
      final recent = service.recentHistoryForTest(
        history,
        currentMessage: 'current',
      );
      expect(recent.map((m) => m.id), ['a']);
    });

    test('keeps a same-text trailing assistant message', () {
      final history = [_msg('current', isUser: false, id: 'asst')];
      final recent = service.recentHistoryForTest(
        history,
        currentMessage: 'current',
      );
      expect(recent.map((m) => m.id), ['asst']);
    });

    test('caps history at the most recent messages', () {
      final history = [for (var i = 0; i < 10; i++) _msg('msg $i', id: 'm$i')];
      final recent = service.recentHistoryForTest(
        history,
        currentMessage: 'new',
      );
      expect(recent, hasLength(8));
      expect(recent.first.id, 'm2');
      expect(recent.last.id, 'm9');
    });

    test('truncates over-cap messages at a sentence boundary', () {
      final longText = '${'Sentence one. ' * 100}tail without end';
      final history = [_msg(longText, id: 'long', isUser: false)];
      final recent = service.recentHistoryForTest(
        history,
        currentMessage: 'new',
      );
      expect(recent, hasLength(1));
      final truncated = recent.first;
      expect(truncated.text.endsWith('…'), isTrue);
      expect(truncated.text.length, lessThan(longText.length));
      expect(truncated.text, startsWith('Sentence one.'));
      // Identity fields survive truncation.
      expect(truncated.id, 'long');
      expect(truncated.chatId, 'c');
      expect(truncated.isUser, isFalse);
    });
  });

  group('GemmaService.load shape (cycle-38 P2)', () {
    test('load shape and identity match the offline-model contract', () {
      final source = File(
        'lib/services/ai/gemma_service.dart',
      ).readAsStringSync();
      // Load shape unchanged by the engine swap: 2048-token context window
      // on the CPU backend (the LiteRT-LM engine clamps to its KV floor).
      expect(source, contains('static const int _maxTokens = 2048;'));
      expect(source, contains('maxTokens: _maxTokens'));
      expect(source, contains('preferredBackend: PreferredBackend.cpu'));
      // Identity coherence across the three files that carry it.
      expect(source, contains("setModelReady(modelType: 'gemma-4-e2b-it')"));
      final service = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      expect(service, contains("_modelType = 'gemma-4-e2b-it'"));
      final dao = File(
        'lib/data/local/offline_model_dao.dart',
      ).readAsStringSync();
      expect(dao, contains("'model_type': 'gemma-4-e2b-it'"));
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
        await dao.setModelReady(modelType: 'gemma-4-e2b-it');
        service.chatOverrideForTest = () async =>
            throw Exception('engine init');

        await expectLater(service.loadInstalled(), throwsA(isA<Exception>()));

        var row = await dao.getModelStatus();
        expect(row, isNotNull);
        expect(row!['status'], 'error');
        expect(row['model_type'], 'gemma-4-e2b-it');
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
        await dao.setModelReady(modelType: 'gemma-4-e2b-it');
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
        await dao.setModelReady(modelType: 'gemma-4-e2b-it');
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
        await dao.setModelReady(modelType: 'gemma-4-e2b-it');
        await dao.setModelError('Offline model failed to load.');
        expect(await dao.isModelInstalled(), isTrue);
      },
    );

    test('a reset row means not installed', () async {
      await dao.setModelReady(modelType: 'gemma-4-e2b-it');
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
