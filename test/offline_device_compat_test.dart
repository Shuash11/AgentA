// cycle-40 P1 — the offline device-compat gate + field-reachable load
// diagnostics.
//
// Two guarantees are locked here:
//
// 1. A device that cannot run the offline model (non-arm64) NEVER sees a
//    download CTA and NEVER sees a retry — it sees one honest message on
//    every offline surface (the app gate, the download screen, the chat
//    card, the model picker).
// 2. Every load failure persists its CLASS (unsupportedAbi / notInstalled /
//    file / engineInit / unknown). A shipped build tree-shakes every
//    raw-exception log, so the persisted class is the only field-visible
//    evidence of why a load failed.
//
// Test-environment notes (the same ones the cycle-38 P6 gate test proved):
// * The DB is opened with `databaseFactoryFfiNoIsolate`: the isolate-backed
//   factory's futures never resolve inside testWidgets' fake-async zone.
// * The legacy-asset probe is stubbed so no plugin call is attempted.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/cubit/connectivity/connectivity_cubit.dart';
import 'package:aiproject/cubit/theme/theme_cubit.dart';
import 'package:aiproject/core/utils/connectivity_service.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/offline_model_dao.dart';
import 'package:aiproject/main.dart';
import 'package:aiproject/presentation/ai/download_prompt_screen.dart';
import 'package:aiproject/presentation/chats/chats.dart';
import 'package:aiproject/presentation/chats/widgets/model_picker_sheet.dart';
import 'package:aiproject/services/ai/ai_service.dart';
import 'package:aiproject/services/ai/device_capabilities.dart';
import 'package:aiproject/services/ai/gemma_service.dart';
import 'package:aiproject/services/ai/groq_service.dart';
import 'package:aiproject/services/ai/huggingface_image_service.dart';
import 'package:aiproject/services/ai/model_download_service.dart';
import 'package:aiproject/services/ai/offline_ai_service.dart';
import 'package:aiproject/services/ai/online_ai_service.dart';
import 'package:aiproject/services/ai/openrouter_service.dart';
import 'package:aiproject/services/ai/pollinations_service.dart';
import 'package:aiproject/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The exact text the pinned plugin throws on a non-arm64 Android device
/// (flutter_edge_ai_litertlm 1.8.6, litert_lm_client.dart:606-611).
const String _pluginUnsupportedAbiText =
    'flutter_edge_ai .litertlm models require an arm64-v8a Android device '
    '(got androidArm). Use a `.task` MediaPipe model on this ABI or run on '
    'an arm64-v8a device / Apple Silicon emulator.';

/// The key of the widget the gate reveals once the model is loaded.
const Key _appChildKey = ValueKey('offline-gate-child');

/// Pumps until [finder] matches (or the budget runs out).
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Widget never appeared: ${finder.describeMatch(Plurality.one)}');
}

void main() {
  late Database db;
  late OfflineModelDao dao;

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
              failure_class TEXT,
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

  group('failure-class mapping (cycle-40 P1)', () {
    test('the engine ABI guard maps to unsupportedAbi', () {
      final service = GemmaService();
      final failure = service.classifyLoadFailureForTest(
        UnsupportedError(_pluginUnsupportedAbiText),
        false,
      );
      expect(failure.failureClass, OfflineModelFailureClass.unsupportedAbi);
      // The honest message, not the raw engine text.
      expect(
        failure.friendlyCopy,
        DeviceCapabilities.incompatibleDeviceMessage,
      );
      expect(
        failure.friendlyCopy,
        isNot(contains('arm64-v8a Android device (')),
      );
    });

    test('a missing asset maps to notInstalled', () {
      final service = GemmaService();
      final failure = service.classifyLoadFailureForTest(
        StateError('Bad state: No active model'),
        false,
      );
      expect(failure.failureClass, OfflineModelFailureClass.notInstalled);
    });

    test('a corrupt asset maps to file', () {
      final service = GemmaService();
      final failure = service.classifyLoadFailureForTest(
        Exception('Failed to read model file: corrupted data'),
        false,
      );
      expect(failure.failureClass, OfflineModelFailureClass.file);
    });

    test('an engine failure maps to engineInit', () {
      final service = GemmaService();
      final failure = service.classifyLoadFailureForTest(
        Exception('Failed to create engine'),
        false,
      );
      expect(failure.failureClass, OfflineModelFailureClass.engineInit);
    });

    test('an unrecognized failure maps to unknown', () {
      final service = GemmaService();
      final failure = service.classifyLoadFailureForTest(
        Exception('boom'),
        false,
      );
      expect(failure.failureClass, OfflineModelFailureClass.unknown);
    });

    test('the four families are four distinct classes', () {
      final service = GemmaService();
      final classes = {
        service
            .classifyLoadFailureForTest(
              UnsupportedError(_pluginUnsupportedAbiText),
              false,
            )
            .failureClass,
        service
            .classifyLoadFailureForTest(
              StateError('Bad state: No active model'),
              false,
            )
            .failureClass,
        service
            .classifyLoadFailureForTest(
              Exception('Failed to read model file: corrupted data'),
              false,
            )
            .failureClass,
        service
            .classifyLoadFailureForTest(
              Exception('Failed to create engine'),
              false,
            )
            .failureClass,
        service
            .classifyLoadFailureForTest(Exception('boom'), false)
            .failureClass,
      };
      expect(classes, hasLength(5));
    });

    test('a failed rehydration still maps to notInstalled', () {
      final service = GemmaService();
      final failure = service.classifyLoadFailureForTest(
        Exception('boom'),
        true,
      );
      expect(failure.failureClass, OfflineModelFailureClass.notInstalled);
    });
  });

  group('failure-class persistence (cycle-40 P1)', () {
    test('the class survives the write and comes back on the read', () async {
      await dao.setModelError('Offline model failed to load.');
      await dao.setFailureClass(OfflineModelFailureClass.engineInit);

      expect(await dao.getFailureClass(), OfflineModelFailureClass.engineInit);
    });

    test('every failure class round-trips', () async {
      for (final value in OfflineModelFailureClass.values) {
        await dao.setModelError('Offline model failed to load.');
        await dao.setFailureClass(value);
        expect(await dao.getFailureClass(), value, reason: value.name);
      }
    });

    test('a successful load clears the persisted class', () async {
      await dao.setModelError('Offline model failed to load.');
      await dao.setFailureClass(OfflineModelFailureClass.unsupportedAbi);
      expect(
        await dao.getFailureClass(),
        OfflineModelFailureClass.unsupportedAbi,
      );

      await dao.setModelReady(modelType: 'gemma-4-e2b-it');
      expect(await dao.getFailureClass(), isNull);
    });

    test('the service persists the class of a failed load', () async {
      final service = GemmaService();
      service.chatOverrideForTest = () async =>
          throw UnsupportedError(_pluginUnsupportedAbiText);

      await expectLater(
        service.loadInstalled(),
        throwsA(isA<UnsupportedError>()),
      );

      expect(service.lastFailureClass, OfflineModelFailureClass.unsupportedAbi);
      expect(
        await dao.getFailureClass(),
        OfflineModelFailureClass.unsupportedAbi,
      );
    });
  });

  group('ABI capability verdict (cycle-40 P1)', () {
    test('an arm64 device is compatible', () {
      expect(
        DeviceCapabilities.isCompatibleAbi(['arm64-v8a', 'armeabi-v7a']),
        isTrue,
      );
    });

    test('a 32-bit device is not compatible', () {
      expect(DeviceCapabilities.isCompatibleAbi(['armeabi-v7a']), isFalse);
    });

    test('an x86_64 emulator is not compatible even though it lists arm64', () {
      // The app process runs the device's FIRST 64-bit ABI (x86_64 here),
      // and the LiteRT-LM stack exists for android_arm64 only — the plugin
      // rejects the load with the same UnsupportedError.
      expect(
        DeviceCapabilities.isCompatibleAbi([
          'x86_64',
          'arm64-v8a',
          'x86',
          'armeabi-v7a',
        ]),
        isFalse,
      );
    });

    test('an unknown ABI list fails open (the load class is the backstop)', () {
      expect(DeviceCapabilities.isCompatibleAbi(null), isTrue);
      expect(DeviceCapabilities.isCompatibleAbi([]), isTrue);
    });
  });

  group('the app gate surface (cycle-40 P1)', () {
    late ModelDownloadService modelDownload;
    late GemmaService gemmaService;
    late ConnectivityCubit connectivity;
    late ThemeCubit theme;

    setUp(() async {
      // A device that already carries the E2B bundle has been through both
      // one-time legacy migrations — their markers are set.
      SharedPreferences.setMockInitialValues({
        'model_asset_v2': true,
        'model_asset_v3': true,
      });
      modelDownload = ModelDownloadService();
      gemmaService = GemmaService();
      connectivity = ConnectivityCubit(ConnectivityService.instance);
      theme = ThemeCubit();
      // No plugin call: the legacy asset is absent on this device.
      ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
          false;
    });

    tearDown(() async {
      ModelDownloadService.legacyAssetPresentOverrideForTest = null;
      ModelDownloadService.uninstallOverrideForTest = null;
      DeviceCapabilities.offlineAiSupportedOverrideForTest = null;
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

    testWidgets('an incompatible device sees the message and NO retry', (
      tester,
    ) async {
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => false;

      await tester.pumpWidget(buildGate());

      await _pumpUntilFound(
        tester,
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
      );
      expect(
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
        findsOneWidget,
      );
      // No retry affordance: it could never succeed on this device.
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Failed to load offline model'), findsNothing);
    });

    testWidgets('an incompatible device never reaches the download gate', (
      tester,
    ) async {
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => false;

      await tester.pumpWidget(buildGate());

      await _pumpUntilFound(
        tester,
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
      );
      // No download offer: the 2.59 GB transfer would be wasted here.
      expect(find.byType(DownloadPromptScreen), findsNothing);
      expect(find.text('Download Offline AI'), findsNothing);
      expect(find.text('Model size: ~2.6GB'), findsNothing);
      // The app child is not revealed either: the gate is mandatory.
      expect(find.byKey(_appChildKey), findsNothing);
    });

    testWidgets('an incompatible device never attempts a load', (tester) async {
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => false;
      var attempts = 0;
      gemmaService.chatOverrideForTest = () async {
        attempts++;
        return _readyChat();
      };

      await tester.pumpWidget(buildGate());

      await _pumpUntilFound(
        tester,
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
      );
      expect(attempts, 0);
    });

    testWidgets('a compatible device keeps the P6 retry surface', (
      tester,
    ) async {
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;
      // The install wrote the ready row (with the download marker).
      await dao.setModelReady(modelType: 'gemma-4-e2b-it');
      gemmaService.chatOverrideForTest = () async =>
          throw Exception('engine init');

      await tester.pumpWidget(buildGate());

      await _pumpUntilFound(tester, find.text('Failed to load offline model'));
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
        findsNothing,
      );
      expect(find.byType(DownloadPromptScreen), findsNothing);
    });

    testWidgets('a compatible device with no model keeps the download gate', (
      tester,
    ) async {
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;

      await tester.pumpWidget(buildGate());

      await _pumpUntilFound(tester, find.byType(DownloadPromptScreen));
      expect(find.byType(DownloadPromptScreen), findsOneWidget);
      expect(
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
        findsNothing,
      );
    });
  });

  group('the download screen surface (cycle-40 P1)', () {
    late ModelDownloadService modelDownload;
    late ConnectivityCubit connectivity;
    late ThemeCubit theme;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'model_asset_v2': true,
        'model_asset_v3': true,
      });
      modelDownload = ModelDownloadService();
      connectivity = ConnectivityCubit(ConnectivityService.instance);
      theme = ThemeCubit();
      ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
          false;
    });

    tearDown(() async {
      ModelDownloadService.legacyAssetPresentOverrideForTest = null;
      ModelDownloadService.uninstallOverrideForTest = null;
      DeviceCapabilities.offlineAiSupportedOverrideForTest = null;
      await connectivity.close();
      await theme.close();
      modelDownload.dispose();
    });

    Widget buildDownloadScreen() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ModelDownloadService>.value(
            value: modelDownload,
          ),
          BlocProvider<ConnectivityCubit>.value(value: connectivity),
          BlocProvider<ThemeCubit>.value(value: theme),
        ],
        child: const MaterialApp(
          home: DownloadPromptScreen(onComplete: _noop, isForcedGate: true),
        ),
      );
    }

    testWidgets('an incompatible device sees the message and NO download CTA', (
      tester,
    ) async {
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => false;

      await tester.pumpWidget(buildDownloadScreen());

      await _pumpUntilFound(
        tester,
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
      );
      expect(
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
        findsOneWidget,
      );
      // No download affordance at all.
      expect(find.text('Download Offline AI'), findsNothing);
      expect(find.text('Model size: ~2.6GB'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('an incompatible device never starts the download', (
      tester,
    ) async {
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => false;

      await tester.pumpWidget(buildDownloadScreen());

      await _pumpUntilFound(
        tester,
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
      );
      // The install would set the status to `installing`; it never ran.
      expect(modelDownload.status, ModelStatus.notInstalled);
      expect(modelDownload.progress, 0.0);
    });

    testWidgets('a compatible device keeps the download offer', (tester) async {
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;

      await tester.pumpWidget(buildDownloadScreen());

      await _pumpUntilFound(tester, find.text('Model size: ~2.6GB'));
      expect(
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
        findsNothing,
      );
      expect(find.text('Model size: ~2.6GB'), findsOneWidget);
    });
  });

  group('the chat card affordance (cycle-40 P1)', () {
    test('an incompatible device offers NO action', () {
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.loadFailed,
          isInstalled: true,
          isDeviceCompatible: false,
        ),
        OfflineModelAction.incompatibleDevice,
      );
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.modelMissing,
          isInstalled: false,
          isDeviceCompatible: false,
        ),
        OfflineModelAction.incompatibleDevice,
      );
    });

    test('an unsupportedAbi failure class offers NO action', () {
      // The persisted class is the release-visible evidence that a retry
      // cannot help (cycle-40 P1).
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.loadFailed,
          isInstalled: true,
          failureClass: OfflineModelFailureClass.unsupportedAbi,
        ),
        OfflineModelAction.incompatibleDevice,
      );
    });

    test('a compatible device keeps the cycle-38 P6 actions', () {
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.loadFailed,
          isInstalled: true,
        ),
        OfflineModelAction.retryLoad,
      );
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.modelMissing,
          isInstalled: false,
        ),
        OfflineModelAction.getModel,
      );
    });

    test('the card renders the message WITHOUT an action', () {
      final source = File(
        'lib/presentation/chats/chats.dart',
      ).readAsStringSync();
      final start = source.indexOf('void _showOfflineActionSnackBar(');
      expect(start, greaterThan(-1));
      final body = source.substring(start, source.indexOf('\n  }', start));
      // The honest message is the card's whole content...
      expect(body, contains('DeviceCapabilities.incompatibleDeviceMessage'));
      // ...and there is no action to tap when the state has no label.
      expect(body, contains('action: label == null'));
    });
  });

  group('the model picker tile (cycle-40 P1)', () {
    test(
      'an incompatible device carries the message and offers no download',
      () {
        final state = offlineTileUnavailableState(isDeviceCompatible: false);
        expect(state.subtitle, DeviceCapabilities.incompatibleDeviceMessage);
        expect(state.canDownload, isFalse);
      },
    );

    test('a compatible device keeps the download invitation', () {
      final state = offlineTileUnavailableState(isDeviceCompatible: true);
      expect(state.subtitle, 'Download to use offline');
      expect(state.canDownload, isTrue);
    });

    testWidgets(
      'the offline tile shows the message on an incompatible device',
      (tester) async {
        DeviceCapabilities.offlineAiSupportedOverrideForTest = () async =>
            false;
        var downloadRequested = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModelPickerSheet(
                  context: context,
                  colors: const ThemeColors(),
                  aiService: _fakeAiService(),
                  onModelSelected: (_) {},
                  onDownloadRequested: () => downloadRequested = true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await _pumpUntilFound(tester, find.text('AgentA Offline AI'));
        // Let the sheet finish sliding in before it is inspected.
        await tester.pumpAndSettle();

        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsOneWidget,
        );
        expect(find.text('Download to use offline'), findsNothing);

        // The tile is not a download CTA any more: tapping it does nothing.
        await tester.ensureVisible(find.text('AgentA Offline AI'));
        await tester.pump();
        await tester.tap(find.text('AgentA Offline AI'));
        await tester.pump();
        expect(downloadRequested, isFalse);
      },
    );

    testWidgets(
      'the offline tile keeps the download invitation on a compatible device',
      (tester) async {
        DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModelPickerSheet(
                  context: context,
                  colors: const ThemeColors(),
                  aiService: _fakeAiService(),
                  onModelSelected: (_) {},
                  onDownloadRequested: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await _pumpUntilFound(tester, find.text('AgentA Offline AI'));
        // Let the sheet finish sliding in before it is inspected.
        await tester.pumpAndSettle();

        expect(find.text('Download to use offline'), findsOneWidget);
        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsNothing,
        );
      },
    );
  });
}

/// A no-op completion handler for the download screen.
void _noop() {}

/// An AI service whose offline model is never ready.
AIService _fakeAiService() {
  return AIService(
    OfflineAIService(GemmaService()),
    OnlineAIService(
      GroqService(),
      OpenRouterService(),
      PollinationsService(),
      HuggingFaceImageService(),
    ),
    ConnectivityService.instance,
  );
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
