// cycle-38 P6 — the offline-model gate's recovery surface.
//
// The gate is the app's first line of defence against the failed-load
// dead-end: it must show a RETRY for an INSTALLED-but-unloaded model and
// the download gate ONLY for a model that is genuinely not on the device
// (S7: an installed model must never be routed into a 2.6 GB re-download).
//
// Test-environment notes (both proven in this repo):
// * The DB is opened with `databaseFactoryFfiNoIsolate`: the isolate-backed
//   factory's futures never resolve inside testWidgets' fake-async zone
//   (the cycle-31 e2e diagnosis) and hang the test for 10 minutes.
// * The migration markers are pre-set: they are one-time legacy migrations
//   that a device with the E2B bundle installed has already been through.
//   Leaving them unset would let the v2 migration reset the DAO row and
//   wipe the very state these tests assert.
// * The legacy-asset probe is stubbed so no plugin call is attempted.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/core/utils/connectivity_service.dart';
import 'package:aiproject/cubit/connectivity/connectivity_cubit.dart';
import 'package:aiproject/cubit/theme/theme_cubit.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/offline_model_dao.dart';
import 'package:aiproject/main.dart';
import 'package:aiproject/presentation/ai/download_prompt_screen.dart';
import 'package:aiproject/services/ai/gemma_service.dart';
import 'package:aiproject/services/ai/model_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The key of the widget the gate reveals once the model is loaded.
const Key _appChildKey = ValueKey('offline-gate-child');

/// Pumps until [finder] matches (or the budget runs out).
///
/// The gate resolves through real async work (sqflite + futures), so the
/// widget test pumps in small steps instead of `pumpAndSettle` — the
/// loading screen's progress indicator animates forever and would never
/// settle.
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Widget never appeared: ${finder.describeMatch(Plurality.one)}');
}

void main() {
  late Database db;
  late ModelDownloadService modelDownload;
  late GemmaService gemmaService;
  late ConnectivityCubit connectivity;
  late ThemeCubit theme;

  setUpAll(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfiNoIsolate.openDatabase(
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
    // A device that already carries the E2B bundle has been through both
    // one-time legacy migrations — their markers are set.
    SharedPreferences.setMockInitialValues({
      'model_asset_v2': true,
      'model_asset_v3': true,
    });
    await db.delete('offline_model_status');
    modelDownload = ModelDownloadService();
    gemmaService = GemmaService();
    connectivity = ConnectivityCubit(ConnectivityService.instance);
    theme = ThemeCubit();
    // No plugin call: the legacy asset is absent on this device.
    ModelDownloadService.legacyAssetPresentOverrideForTest = () async => false;
  });

  tearDown(() async {
    ModelDownloadService.legacyAssetPresentOverrideForTest = null;
    ModelDownloadService.uninstallOverrideForTest = null;
    await connectivity.close();
    await theme.close();
    modelDownload.dispose();
    gemmaService.dispose();
  });

  Widget buildGate() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ModelDownloadService>.value(
          value: modelDownload,
        ),
        ChangeNotifierProvider<GemmaService>.value(value: gemmaService),
        BlocProvider<ConnectivityCubit>.value(value: connectivity),
        BlocProvider<ThemeCubit>.value(value: theme),
      ],
      child: const MaterialApp(
        home: OfflineModelGate(child: SizedBox.shrink(key: _appChildKey)),
      ),
    );
  }

  group('OfflineModelGate recovery surface (cycle-38 P6)', () {
    testWidgets(
      'an installed model that fails to load shows a RETRY, not the download gate',
      (tester) async {
        // The install wrote the ready row (with the download marker).
        await OfflineModelDao().setModelReady(modelType: 'gemma-4-e2b-it');
        // The engine refuses to load.
        gemmaService.chatOverrideForTest = () async =>
            throw Exception('engine init');

        await tester.pumpWidget(buildGate());

        await _pumpUntilFound(
          tester,
          find.text('Failed to load offline model'),
        );
        expect(find.text('Failed to load offline model'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        // S7: an INSTALLED model must never re-open the download gate — that
        // is what stranded the user behind a spurious 2.59 GB re-download.
        expect(find.byType(DownloadPromptScreen), findsNothing);
      },
    );

    testWidgets('the retry on the error screen performs a load attempt', (
      tester,
    ) async {
      await OfflineModelDao().setModelReady(modelType: 'gemma-4-e2b-it');
      var attempts = 0;
      gemmaService.chatOverrideForTest = () async {
        attempts++;
        if (attempts == 1) throw Exception('engine init');
        return _readyChat();
      };

      await tester.pumpWidget(buildGate());
      await _pumpUntilFound(tester, find.text('Failed to load offline model'));
      expect(attempts, 1);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      // The retry recovers without a restart: the app is shown again.
      await _pumpUntilFound(tester, find.byKey(_appChildKey));
      expect(attempts, 2);
      expect(gemmaService.isReady, isTrue);
      expect(find.byType(DownloadPromptScreen), findsNothing);
    });

    testWidgets(
      'an installed model whose load reports a missing asset STILL gets the RETRY (S7)',
      (tester) async {
        // The asset is on the device; the engine only reports a bad state.
        // The durable install marker outranks that verdict — routing it to
        // the download gate would re-download 2.6 GB of a model already
        // present.
        await OfflineModelDao().setModelReady(modelType: 'gemma-4-e2b-it');
        gemmaService.chatOverrideForTest = () async =>
            throw StateError('Bad state: No active model');

        await tester.pumpWidget(buildGate());

        await _pumpUntilFound(
          tester,
          find.text('Failed to load offline model'),
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.byType(DownloadPromptScreen), findsNothing);
      },
    );

    test('a missing model keeps the download gate as its surface', () {
      // The download-gate surface is pre-existing behavior. It is asserted at
      // the source level because mounting DownloadPromptScreen in a widget
      // test trips a PRE-EXISTING defect in that screen's dispose()
      // (context.read on a deactivated element → debug-mode assertion).
      // Fixing it would touch a fifth lib file — an Adviser decision, not
      // this phase's (cycle-38 P6 scope).
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains('DownloadPromptScreen('));
      // The installed/retry branch comes FIRST: an installed model can never
      // reach the download gate (S7).
      final retryIndex = source.indexOf('_isInstalled ||');
      final downloadIndex = source.indexOf('DownloadPromptScreen(');
      expect(retryIndex, greaterThan(-1));
      expect(downloadIndex, greaterThan(retryIndex));
    });
  });
}

/// A ready chat backed by an in-memory session.
Future<InferenceChat> _readyChat() async {
  final chat = InferenceChat(
    sessionCreator: () async => _FakeSession(),
    maxTokens: 2048,
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  );
  await chat.initSession();
  return chat;
}

class _FakeSession implements InferenceModelSession {
  @override
  Future<String> getResponse() async => 'pong';

  @override
  Stream<String> getResponseAsync() async* {
    yield 'pong';
  }

  @override
  Future<int> sizeInTokens(String text) async => text.length;

  @override
  Future<void> addQueryChunk(Message message) async {}

  @override
  Future<void> stopGeneration() async {}

  @override
  SessionMetrics getSessionMetrics() => SessionMetrics();

  @override
  Future<void> close() async {}
}
