// cycle-40 P1 — the offline device-compat gate + field-reachable load
// diagnostics. Amended by cycle-42 P2b (the RAM verdict is the ONE
// selection key) and cycle-43 (the under-floor "Download anyway" override).
//
// Three guarantees are locked here:
//
// 1. A device that cannot run the offline model NEVER sees a download CTA
//    by default and NEVER sees a retry — it sees one honest message on
//    every offline surface (the app gate, the download screen, the chat
//    card, the model picker). Cycle-42 P2b re-keyed that guarantee to the
//    RAM floor; cycle-43 (contract `offline-model-qwen15b` §6
//    under_floor_first_use / under_floor_post_ack) adds the ONE consented
//    exception: a BELOW-FLOOR device (readable RAM) sees the ruled risk
//    copy FIRST (warning-first, cycle-43 §6 S1) + the "Download anyway"
//    override; after the recorded ack the download is enabled and the
//    short retained risk line accompanies it — never re-nagged, never
//    silently green. The below-floor state is the ONLY state the override
//    unlocks, and only through the explicit tap: no download may start
//    without the recorded ack (S1).
// 2. Every load failure persists its CLASS (unsupportedAbi / notInstalled /
//    file / engineInit / unknown). A shipped build tree-shakes every
//    raw-exception log, so the persisted class is the only field-visible
//    evidence of why a load failed.
// 3. The failure path is untouched by the override: an OOM/kill on an
//    overridden device classifies and surfaces exactly as before.
//
// Test-environment notes (the same ones the cycle-38 P6 gate test proved):
// * The DB is opened with `databaseFactoryFfiNoIsolate`: the isolate-backed
//   factory's futures never resolve inside testWidgets' fake-async zone.
// * The legacy-asset probe is stubbed so no plugin call is attempted.
// * The RAM verdict is stubbed: the total-memory read is an ANDROID fact,
//   so an unstubbed host could not report RAM and would fail the floor —
//   every surface test states the RAM it simulates. The lived reference
//   device (cycle-43 plan §1.1) is OPPO CPH2591: MemTotal 3,814,532 kB —
//   the below-floor tests use that exact figure.
// * The override ack's `SharedPreferencesAsync` store is the platform-
//   interface in-memory store (the update_feature_test.dart precedent):
//   the async API has NO default platform instance in tests, so the groups
//   that exercise the ack path install one in setUp — an unset platform
//   reads (honestly) as NOT recorded, the S1 default.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
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
import 'package:aiproject/services/ai/offline_model_spec.dart';
import 'package:aiproject/services/ai/online_ai_service.dart';
import 'package:aiproject/services/ai/openrouter_service.dart';
import 'package:aiproject/services/ai/pollinations_service.dart';
import 'package:aiproject/theme/app_theme.dart';

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

/// The lived reference device's total memory (cycle-43 plan §1.1): OPPO
/// CPH2591, MemTotal 3,814,532 kB ≈ 3.64 GB — BELOW the 4 GB floor. The
/// below-floor tests simulate THIS device.
const int _livedDeviceTotalMemoryBytes = 3814532 * 1024;

/// Installs the in-memory async-preferences store (the ack's persisted
/// home) and forgets any cached ack read, so the next
/// [DeviceCapabilities.hasRamOverrideAck] re-reads the store.
void _installAckStore() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  DeviceCapabilities.resetRamOverrideAckForTest();
}

/// Tears the ack seams down: the reader override, the platform store and
/// the cached read all reset, so no test leaks its ack state into the next.
void _resetAckSeams() {
  DeviceCapabilities.ramOverrideAckOverrideForTest = null;
  DeviceCapabilities.resetRamOverrideAckForTest();
  SharedPreferencesAsyncPlatform.instance = null;
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

      await dao.setModelReady(modelType: OfflineModelSpecTable.appIdentity);
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
      // The ack's persisted store (cycle-43): the gate resolves the
      // override state on every path, so the async store is installed and
      // the ack starts unrecorded (the S1 default).
      _installAckStore();
      modelDownload = ModelDownloadService();
      gemmaService = GemmaService();
      connectivity = ConnectivityCubit(ConnectivityService.instance);
      theme = ThemeCubit();
      // No plugin call: the legacy asset is absent on this device.
      ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
          false;
      ModelDownloadService.e2bAssetPresentOverrideForTest = () async => false;
      // The default device clears the 4 GB RAM floor — it may run the
      // offline model. A test that simulates a below-floor device lowers it.
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          6 * 1024 * 1024 * 1024;
    });

    tearDown(() async {
      ModelDownloadService.legacyAssetPresentOverrideForTest = null;
      ModelDownloadService.e2bAssetPresentOverrideForTest = null;
      ModelDownloadService.uninstallOverrideForTest = null;
      DeviceCapabilities.offlineAiSupportedOverrideForTest = null;
      DeviceCapabilities.totalMemoryOverrideForTest = null;
      _resetAckSeams();
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

    testWidgets('a device below the RAM floor sees the message and NO retry', (
      tester,
    ) async {
      // The ONE requirement left (plan §4.9): 4 GB of total memory. The
      // ABI is irrelevant here — the RAM floor is the whole table.
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          2 * 1024 * 1024 * 1024;

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

    testWidgets(
      'a device below the RAM floor never reaches the download gate',
      (tester) async {
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            2 * 1024 * 1024 * 1024;

        await tester.pumpWidget(buildGate());

        await _pumpUntilFound(
          tester,
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
        );
        // No download offer: the 1.6 GB transfer would be wasted here.
        expect(find.byType(DownloadPromptScreen), findsNothing);
        expect(find.text('Download Offline AI'), findsNothing);
        expect(find.text('Model size: ~1.6GB'), findsNothing);
        // The app child is not revealed either: the gate is mandatory.
        expect(find.byKey(_appChildKey), findsNothing);
      },
    );

    testWidgets('a device below the RAM floor never attempts a load', (
      tester,
    ) async {
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          2 * 1024 * 1024 * 1024;
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

    testWidgets(
      'a below-floor device sees the risk copy and the Download anyway override — never an auto-download (cycle-43)',
      (tester) async {
        // The lived reference device (cycle-43 plan §1.1): 3.64 GB, below
        // the floor, no ack recorded yet — the FIRST-use state.
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            _livedDeviceTotalMemoryBytes;

        await tester.pumpWidget(buildGate());

        await _pumpUntilFound(
          tester,
          find.text(DeviceCapabilities.underFloorRiskCopy),
        );
        // Warning-first (cycle-43 §6 S1): the risk copy renders FIRST, the
        // honest message stays, and the override button follows.
        expect(
          find.text(DeviceCapabilities.underFloorRiskCopy),
          findsOneWidget,
        );
        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsOneWidget,
        );
        expect(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
          findsOneWidget,
        );
        // No download offer of any kind before the ack (S1): the override
        // button is the ONLY affordance, and nothing auto-starts behind it.
        expect(find.byType(DownloadPromptScreen), findsNothing);
        expect(find.text('Download Offline AI'), findsNothing);
        expect(find.text('Model size: ~1.6GB'), findsNothing);
        expect(find.byKey(_appChildKey), findsNothing);
        expect(modelDownload.status, ModelStatus.notInstalled);
        expect(modelDownload.progress, 0.0);
      },
    );

    testWidgets(
      'the gate override tap records the ack and proceeds into the download flow (cycle-43)',
      (tester) async {
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            _livedDeviceTotalMemoryBytes;

        await tester.pumpWidget(buildGate());
        await _pumpUntilFound(
          tester,
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
        );

        await tester.tap(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
        );

        // The ack is recorded — in memory AND persisted (the flag
        // round-trip through the real write path).
        expect(await DeviceCapabilities.hasRamOverrideAck(), isTrue);
        expect(
          await SharedPreferencesAsync().getBool(
            DeviceCapabilities.ramOverrideAckPrefsKey,
          ),
          isTrue,
        );

        // The selection now admits the device: the gate re-resolves into
        // the SAME download flow an eligible device takes.
        await _pumpUntilFound(tester, find.byType(DownloadPromptScreen));
        expect(find.byType(DownloadPromptScreen), findsOneWidget);
        // Never re-nagged: the full risk copy and the button do not
        // repeat. Never silently green: the retained risk line does (the
        // screen resolves its own selection, so pump until it renders).
        await _pumpUntilFound(
          tester,
          find.text(DeviceCapabilities.underFloorRetainedRiskLine),
        );
        expect(find.text(DeviceCapabilities.underFloorRiskCopy), findsNothing);
        expect(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
          findsNothing,
        );
        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsNothing,
        );
        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a below-floor device holding the ack goes straight to the enabled download with the retained line (cycle-43)',
      (tester) async {
        // Post-ack: the ack is recorded — the gate never re-nags.
        DeviceCapabilities.ramOverrideAckOverrideForTest = () async => true;
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            _livedDeviceTotalMemoryBytes;

        await tester.pumpWidget(buildGate());

        await _pumpUntilFound(tester, find.byType(DownloadPromptScreen));
        expect(find.byType(DownloadPromptScreen), findsOneWidget);
        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsNothing,
        );
        expect(find.text(DeviceCapabilities.underFloorRiskCopy), findsNothing);
        expect(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
          findsNothing,
        );
        // The retained risk line accompanies the enabled download (the
        // screen resolves its own selection — pump until it renders).
        await _pumpUntilFound(
          tester,
          find.text(DeviceCapabilities.underFloorRetainedRiskLine),
        );
        expect(
          find.text(DeviceCapabilities.underFloorRetainedRiskLine),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an unreadable-RAM device keeps the plain honest surface — no override affordance (cycle-43)',
      (tester) async {
        // The fail-closed rule carries: a device whose RAM cannot be read
        // is never told what its RAM is, so it gets no risk copy and no
        // override. Without an ack its verdict stays message-only.
        DeviceCapabilities.totalMemoryOverrideForTest = () async => null;

        await tester.pumpWidget(buildGate());

        await _pumpUntilFound(
          tester,
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
        );
        expect(find.text(DeviceCapabilities.underFloorRiskCopy), findsNothing);
        expect(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
          findsNothing,
        );
        expect(find.byType(DownloadPromptScreen), findsNothing);
      },
    );

    testWidgets(
      'a device that clears the RAM floor keeps the P6 retry surface',
      (tester) async {
        // The install wrote the ready row (with the download marker).
        await dao.setModelReady(modelType: OfflineModelSpecTable.appIdentity);
        gemmaService.chatOverrideForTest = () async =>
            throw Exception('engine init');

        await tester.pumpWidget(buildGate());

        await _pumpUntilFound(
          tester,
          find.text('Failed to load offline model'),
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsNothing,
        );
        expect(find.byType(DownloadPromptScreen), findsNothing);
      },
    );

    testWidgets(
      'a device that clears the RAM floor with no model keeps the download gate',
      (tester) async {
        await tester.pumpWidget(buildGate());

        await _pumpUntilFound(tester, find.byType(DownloadPromptScreen));
        expect(find.byType(DownloadPromptScreen), findsOneWidget);
        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsNothing,
        );
      },
    );

    testWidgets('the ABI verdict does not change the selection any more', (
      tester,
    ) async {
      // An arm64 device (the ABI the old table routed to E2B) now gets the
      // selected flow exactly like every other device — the ABI is not a
      // selection input (plan §4.9).
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          6 * 1024 * 1024 * 1024;

      await tester.pumpWidget(buildGate());

      await _pumpUntilFound(tester, find.byType(DownloadPromptScreen));
      expect(find.byType(DownloadPromptScreen), findsOneWidget);
      // The chip renders once the screen's own selection resolves.
      await _pumpUntilFound(tester, find.text('Model size: ~1.6GB'));
      expect(find.text('Model size: ~1.6GB'), findsOneWidget);
      expect(find.text('Model size: ~2.6GB'), findsNothing);
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
      // The ack's persisted store (cycle-43): the screen resolves the
      // override state, so the async store is installed and the ack starts
      // unrecorded (the S1 default).
      _installAckStore();
      modelDownload = ModelDownloadService();
      connectivity = ConnectivityCubit(ConnectivityService.instance);
      theme = ThemeCubit();
      ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
          false;
      ModelDownloadService.e2bAssetPresentOverrideForTest = () async => false;
      // The default device clears the 4 GB RAM floor — it may run the
      // offline model.
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          6 * 1024 * 1024 * 1024;
    });

    tearDown(() async {
      ModelDownloadService.legacyAssetPresentOverrideForTest = null;
      ModelDownloadService.e2bAssetPresentOverrideForTest = null;
      ModelDownloadService.uninstallOverrideForTest = null;
      DeviceCapabilities.offlineAiSupportedOverrideForTest = null;
      DeviceCapabilities.totalMemoryOverrideForTest = null;
      _resetAckSeams();
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

    testWidgets(
      'a device below the RAM floor sees the message and NO download CTA',
      (tester) async {
        // The lived reference device (cycle-43 plan §1.1), no ack yet.
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            _livedDeviceTotalMemoryBytes;

        await tester.pumpWidget(buildDownloadScreen());

        await _pumpUntilFound(
          tester,
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
        );
        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsOneWidget,
        );
        // The risk copy renders FIRST (warning-first, cycle-43 §6 S1) and
        // the "Download anyway" override button follows it.
        expect(
          find.text(DeviceCapabilities.underFloorRiskCopy),
          findsOneWidget,
        );
        expect(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
          findsOneWidget,
        );
        // The download affordance at all is still absent: no chip, no
        // download CTA — the override button is the only affordance (S1).
        expect(find.text('Download Offline AI'), findsNothing);
        expect(find.text('Model size: ~1.6GB'), findsNothing);
      },
    );

    testWidgets('a device below the RAM floor never starts the download', (
      tester,
    ) async {
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          2 * 1024 * 1024 * 1024;

      await tester.pumpWidget(buildDownloadScreen());

      await _pumpUntilFound(
        tester,
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
      );
      // The install would set the status to `installing`; it never ran.
      expect(modelDownload.status, ModelStatus.notInstalled);
      expect(modelDownload.progress, 0.0);
    });

    testWidgets(
      'the override tap records the ack and proceeds into the normal flow (cycle-43)',
      (tester) async {
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            _livedDeviceTotalMemoryBytes;

        await tester.pumpWidget(buildDownloadScreen());
        await _pumpUntilFound(
          tester,
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
        );

        await tester.tap(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
        );

        // The ack is recorded — in memory AND persisted (the flag
        // round-trip through the real write path).
        expect(await DeviceCapabilities.hasRamOverrideAck(), isTrue);
        expect(
          await SharedPreferencesAsync().getBool(
            DeviceCapabilities.ramOverrideAckPrefsKey,
          ),
          isTrue,
        );

        // The normal flow takes over (the same path an eligible device
        // takes): the chip renders, the first-use copy is gone, and the
        // retained risk line accompanies the enabled download.
        await _pumpUntilFound(tester, find.text('Model size: ~1.6GB'));
        expect(find.text('Model size: ~1.6GB'), findsOneWidget);
        expect(find.text(DeviceCapabilities.underFloorRiskCopy), findsNothing);
        expect(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
          findsNothing,
        );
        expect(
          find.text(DeviceCapabilities.underFloorRetainedRiskLine),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a below-floor device holding the ack gets the enabled download with the retained line — never re-nagged (cycle-43)',
      (tester) async {
        DeviceCapabilities.ramOverrideAckOverrideForTest = () async => true;
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            _livedDeviceTotalMemoryBytes;

        await tester.pumpWidget(buildDownloadScreen());

        await _pumpUntilFound(tester, find.text('Model size: ~1.6GB'));
        expect(find.text('Model size: ~1.6GB'), findsOneWidget);
        // The enabled download keeps the retained risk line (never
        // silently green) and is never re-nagged by the first-use copy.
        expect(
          find.text(DeviceCapabilities.underFloorRetainedRiskLine),
          findsOneWidget,
        );
        expect(find.text(DeviceCapabilities.underFloorRiskCopy), findsNothing);
        expect(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
          findsNothing,
        );
        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsNothing,
        );
      },
    );

    testWidgets('every device class keeps the download offer', (tester) async {
      await tester.pumpWidget(buildDownloadScreen());

      await _pumpUntilFound(tester, find.text('Model size: ~1.6GB'));
      expect(
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
        findsNothing,
      );
      // The ~1.6GB chip is UNIVERSAL (contract §6): the E2B chip is gone
      // with the E2B class.
      expect(find.text('Model size: ~1.6GB'), findsOneWidget);
      expect(find.text('Model size: ~2.6GB'), findsNothing);
      // Above-floor, the cycle-43 override copy is nowhere: the flow is
      // byte-for-byte unchanged (plan §5-P2 criterion 3).
      expect(find.text(DeviceCapabilities.underFloorRiskCopy), findsNothing);
      expect(
        find.text(DeviceCapabilities.downloadAnywayButtonLabel),
        findsNothing,
      );
      expect(
        find.text(DeviceCapabilities.underFloorRetainedRiskLine),
        findsNothing,
      );
    });

    testWidgets(
      'an arm64 device offers the SAME selected bundle with the ~1.6GB chip',
      (tester) async {
        // The ABI is NOT a selection input any more (plan §4.9): the arm64
        // device that the old table routed to E2B gets the SAME selected
        // bundle.
        DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            6 * 1024 * 1024 * 1024;

        await tester.pumpWidget(buildDownloadScreen());

        await _pumpUntilFound(tester, find.text('Model size: ~1.6GB'));
        expect(find.text('Model size: ~1.6GB'), findsOneWidget);
        // The E2B chip never appears anywhere.
        expect(find.text('Model size: ~2.6GB'), findsNothing);
        expect(
          find.text(DeviceCapabilities.incompatibleDeviceMessage),
          findsNothing,
        );
      },
    );

    testWidgets('the message-only class sees the honest message and NO chip', (
      tester,
    ) async {
      // A device BELOW the 4 GB RAM floor.
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          2 * 1024 * 1024 * 1024;

      await tester.pumpWidget(buildDownloadScreen());

      await _pumpUntilFound(
        tester,
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
      );
      expect(
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
        findsOneWidget,
      );
      // No size chip and no download affordance at all — the ONLY
      // affordance is the override button (cycle-43), and the chip stays
      // absent from the message-only state.
      expect(find.text('Model size: ~1.6GB'), findsNothing);
      expect(find.text('Model size: ~2.6GB'), findsNothing);
      expect(find.text('Download Offline AI'), findsNothing);
    });

    testWidgets('a device with UNREADABLE RAM gets the honest message', (
      tester,
    ) async {
      // The fail-closed rule (S8): a device that cannot report its RAM is
      // not offered the asset. Cycle-43: it is not offered the override
      // either — the UI never states RAM it cannot know.
      DeviceCapabilities.totalMemoryOverrideForTest = () async => null;

      await tester.pumpWidget(buildDownloadScreen());

      await _pumpUntilFound(
        tester,
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
      );
      expect(
        find.text(DeviceCapabilities.incompatibleDeviceMessage),
        findsOneWidget,
      );
      expect(find.text('Model size: ~1.6GB'), findsNothing);
      expect(find.text('Download Offline AI'), findsNothing);
      expect(find.text(DeviceCapabilities.underFloorRiskCopy), findsNothing);
      expect(
        find.text(DeviceCapabilities.downloadAnywayButtonLabel),
        findsNothing,
      );
      expect(
        find.text(DeviceCapabilities.underFloorRetainedRiskLine),
        findsNothing,
      );
    });

    test(
      'the honest message states BOTH reasons (arm64-v8a AND the RAM floor)',
      () {
        // C46 (plan §5.3; contract `offline-model-minicpm5` §3
        // message_only_class + §9 message_only_wording): the ABI clause
        // RETURNS to the wording — the message carries BOTH reasons, so it
        // names arm64-v8a AND the 4 GB RAM floor. The RAM-only wording of
        // C42-P2b is superseded on this path.
        expect(
          DeviceCapabilities.incompatibleDeviceMessage,
          contains('arm64-v8a'),
        );
        expect(DeviceCapabilities.incompatibleDeviceMessage, contains('4 GB'));
        expect(
          DeviceCapabilities.incompatibleDeviceMessage,
          'The offline AI requires a 64-bit ARM (arm64-v8a) device with at '
          'least 4 GB of RAM.',
        );
      },
    );
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

    test(
      'the card renders the message WITHOUT an action when no override applies',
      () {
        final source = File(
          'lib/presentation/chats/chats.dart',
        ).readAsStringSync();
        final start = source.indexOf(
          'Future<void> _showOfflineActionSnackBar(',
        );
        expect(start, greaterThan(-1));
        // The method ends where the override helper's doc begins.
        final end = source.indexOf(
          '\n  /// Records the under-floor override ack',
          start,
        );
        expect(end, greaterThan(start));
        final body = source.substring(start, end);
        // The plain honest branch keeps the message with no action (the
        // unreadable state, and the unsupportedAbi failure class —
        // neither is the RAM state the override consents to)...
        expect(
          body,
          contains(
            'content: Text(DeviceCapabilities.incompatibleDeviceMessage)',
          ),
        );
        // ...and the enabled branch keeps the existing CTA wiring — no new
        // CTA label (contract §6 under_floor_post_ack).
        expect(
          body,
          contains('onPressed: () => unawaited(_runOfflineAction(action))'),
        );
      },
    );

    test(
      "the card's below-floor state renders the risk copy first with the Download anyway action (cycle-43)",
      () {
        final source = File(
          'lib/presentation/chats/chats.dart',
        ).readAsStringSync();
        final start = source.indexOf(
          'selection.isMessageOnly && selection.isBelowFloor',
        );
        expect(start, greaterThan(-1));
        final body = source.substring(start, source.indexOf('return;', start));
        // The risk copy renders FIRST (warning-first, cycle-43 §6 S1), the
        // honest message-only text stays...
        expect(body, contains('DeviceCapabilities.underFloorRiskCopy'));
        expect(body, contains('DeviceCapabilities.incompatibleDeviceMessage'));
        // ...and the "Download anyway" action records the ack and routes
        // into the download flow (one flow, four entries).
        expect(
          body,
          contains('label: DeviceCapabilities.downloadAnywayButtonLabel'),
        );
        expect(body, contains('_acknowledgeOverrideAndDownload()'));
      },
    );

    test(
      "the card's enabled affordance carries the retained line on an overridden device (cycle-43)",
      () {
        final source = File(
          'lib/presentation/chats/chats.dart',
        ).readAsStringSync();
        final start = source.indexOf('final showRetainedLine =');
        expect(start, greaterThan(-1));
        final end = source.indexOf(
          '\n  /// Records the under-floor override ack',
          start,
        );
        expect(end, greaterThan(start));
        final body = source.substring(start, end);
        // The retained risk line accompanies the GET-MODEL affordance (the
        // enabled download) on a below-floor device; the RETRY-LOAD path is
        // the failure path, which this ruling leaves untouched.
        expect(body, contains('OfflineModelAction.getModel'));
        expect(body, contains('selection.isBelowFloor'));
        expect(body, contains('DeviceCapabilities.underFloorRetainedRiskLine'));
        expect(body, contains('ChatErrorClassifier.offlineNotReadyMessage'));
      },
    );
  });

  group('the one-class selection table (cycle-42 P2b, cycle-43 override)', () {
    setUp(() {
      // The ack's persisted store (cycle-43): resolve() reads the override
      // ack on every call, so the async store is installed and the cached
      // read is forgotten — each test states its own ack state.
      _installAckStore();
    });

    tearDown(() {
      _resetAckSeams();
    });

    test('EVERY device class resolves to the single selected spec', () {
      // ONE selection key (the RAM verdict): the ABI decides nothing
      // (plan §4.9), so there is no ABI input to the table at all.
      expect(
        OfflineModelSpecTable.resolveClass(hasMemoryCapacity: true),
        OfflineModelClass.singleQwen,
      );
      expect(
        OfflineModelSpecTable.specFor(OfflineModelClass.singleQwen),
        OfflineModelSpecTable.minicpm5,
      );
      final spec = OfflineModelSpecTable.specFor(OfflineModelClass.singleQwen)!;
      expect(spec.identity, 'minicpm5-2b-q4km');
      expect(spec.modelType, ModelType.llama);
      expect(spec.fileType, ModelFileType.gguf);
      expect(
        spec.url,
        'https://huggingface.co/openbmb/MiniCPM5-2B-GGUF/resolve/main/MiniCPM5-2B-Q4_K_M.gguf',
      );
      expect(spec.sizeChip, 'Model size: ~1.6GB');
    });

    test('a device below the floor gets NO model at all', () {
      expect(
        OfflineModelSpecTable.resolveClass(hasMemoryCapacity: false),
        OfflineModelClass.messageOnly,
      );
      expect(
        OfflineModelSpecTable.specFor(OfflineModelClass.messageOnly),
        isNull,
      );
    });

    test(
      'below-floor + ack resolves the SAME selected spec (the ruled verdict, cycle-43)',
      () {
        // The ruled formula (plan §4.3/§5-P2 item 1): totalMem >= floor OR
        // ack — below-floor + ack ⇒ eligible for the SAME spec, never a
        // different model (contract §3 under_floor_override).
        expect(
          OfflineModelSpecTable.resolveClass(
            hasMemoryCapacity: false,
            overrideAck: true,
          ),
          OfflineModelClass.singleQwen,
        );
        // The SAME spec — nothing re-specified.
        expect(
          OfflineModelSpecTable.specFor(OfflineModelClass.singleQwen),
          OfflineModelSpecTable.minicpm5,
        );
      },
    );

    test(
      'below-floor without the ack stays message-only (S1 — consent, never a default)',
      () {
        expect(
          OfflineModelSpecTable.resolveClass(
            hasMemoryCapacity: false,
            overrideAck: false,
          ),
          OfflineModelClass.messageOnly,
        );
        expect(
          OfflineModelSpecTable.specFor(OfflineModelClass.messageOnly),
          isNull,
        );
      },
    );

    test('above-floor is unchanged by the override term (cycle-43)', () {
      expect(
        OfflineModelSpecTable.resolveClass(
          hasMemoryCapacity: true,
          overrideAck: false,
        ),
        OfflineModelClass.singleQwen,
      );
      expect(
        OfflineModelSpecTable.resolveClass(
          hasMemoryCapacity: true,
          overrideAck: true,
        ),
        OfflineModelClass.singleQwen,
      );
    });

    test('the flag round-trips and is never auto-cleared (cycle-43)', () async {
      // The real read/write path over the in-memory async store: nothing
      // recorded → the tap records → the record survives a fresh read
      // (the cache reset proves it persisted, not just cached).
      expect(await DeviceCapabilities.hasRamOverrideAck(), isFalse);

      await DeviceCapabilities.acknowledgeRamOverride();
      expect(await DeviceCapabilities.hasRamOverrideAck(), isTrue);

      DeviceCapabilities.resetRamOverrideAckForTest();
      expect(await DeviceCapabilities.hasRamOverrideAck(), isTrue);
      expect(
        await SharedPreferencesAsync().getBool(
          DeviceCapabilities.ramOverrideAckPrefsKey,
        ),
        isTrue,
      );
    });

    test(
      "the user's device (arm64 + 3.64 GB): the C43 override path, and the GGUF installs post-ack",
      () async {
        // The lived reference device (cycle-43 plan §1.1): arm64-v8a
        // PRESENT and 3.64 GB RAM — BELOW the 4 GB floor → the C43 OVERRIDE
        // PATH (plan §5.3 / contract §3 `under_floor_override_class`):
        // the honest warning + "Download anyway", never a default download.
        addTearDown(() {
          DeviceCapabilities.offlineAiSupportedOverrideForTest = null;
          DeviceCapabilities.totalMemoryOverrideForTest = null;
        });
        DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            _livedDeviceTotalMemoryBytes;

        // BEFORE the ack: the message-only class WITH the below-floor fact —
        // the warning-first override state (no asset, no auto-download).
        final beforeAck = await OfflineModelSpecTable.resolve();
        expect(beforeAck.deviceClass, OfflineModelClass.messageOnly);
        expect(beforeAck.isBelowFloor, isTrue);
        expect(beforeAck.spec, isNull);
        expect(DeviceCapabilities.underFloorRiskCopy, contains('4 GB'));
        expect(DeviceCapabilities.downloadAnywayButtonLabel, 'Download anyway');

        // The tap — recorded through the REAL write path (the ack is a
        // persisted user preference, never a migration marker).
        await DeviceCapabilities.acknowledgeRamOverride();
        DeviceCapabilities.resetRamOverrideAckForTest();
        expect(await DeviceCapabilities.hasRamOverrideAck(), isTrue);

        // POST-ack: the SAME GGUF spec becomes eligible — the override never
        // selects a different model (below-floor + ack ⇒ eligible).
        final afterAck = await OfflineModelSpecTable.resolve();
        expect(afterAck.deviceClass, OfflineModelClass.singleQwen);
        expect(afterAck.spec, OfflineModelSpecTable.minicpm5);
        expect(afterAck.spec!.identity, 'minicpm5-2b-q4km');
        expect(afterAck.spec!.modelType, ModelType.llama);
        expect(afterAck.spec!.fileType, ModelFileType.gguf);
        expect(afterAck.spec!.expectedSize, 1561318368);

        // The GGUF installs: the install chain writes the GGUF identity.
        SharedPreferences.setMockInitialValues({
          'model_asset_v2': true,
          'model_asset_v3': true,
        });
        final download = ModelDownloadService();
        addTearDown(download.dispose);
        var installs = 0;
        download.installOverrideForTest = (token) async {
          installs++;
        };

        await download.installModel();

        expect(installs, 1);
        expect(download.status, ModelStatus.ready);
        final row = await db.query('offline_model_status');
        expect(row.first['status'], 'ready');
        expect(row.first['model_type'], 'minicpm5-2b-q4km');
      },
    );

    test('an unreadable ack store fails closed to NOT recorded (S1)', () async {
      // No platform instance → the constructor throws (the update_cubit
      // precedent) → the defensive read reports NOT recorded, and the
      // persist failure still applies the choice for this session only.
      SharedPreferencesAsyncPlatform.instance = null;
      DeviceCapabilities.resetRamOverrideAckForTest();

      expect(await DeviceCapabilities.hasRamOverrideAck(), isFalse);

      await DeviceCapabilities.acknowledgeRamOverride();
      expect(await DeviceCapabilities.hasRamOverrideAck(), isTrue);
      // The failure is honest, not sticky: nothing was persisted.
      DeviceCapabilities.resetRamOverrideAckForTest();
      expect(await DeviceCapabilities.hasRamOverrideAck(), isFalse);
    });

    test(
      'the device resolution carries the below-floor fact (cycle-43)',
      () async {
        // The lived reference device (cycle-43 plan §1.1), no ack:
        // message-only AND below-floor — the override state.
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            _livedDeviceTotalMemoryBytes;
        DeviceCapabilities.ramOverrideAckOverrideForTest = () async => false;
        final below = await OfflineModelSpecTable.resolve();
        expect(below.deviceClass, OfflineModelClass.messageOnly);
        expect(below.isMessageOnly, isTrue);
        expect(below.isBelowFloor, isTrue);

        // The same device with the recorded ack: the SAME selected spec,
        // still below-floor (the retained risk line's basis).
        DeviceCapabilities.ramOverrideAckOverrideForTest = () async => true;
        final acked = await OfflineModelSpecTable.resolve();
        expect(acked.deviceClass, OfflineModelClass.singleQwen);
        expect(acked.spec, OfflineModelSpecTable.minicpm5);
        expect(acked.hasModel, isTrue);
        expect(acked.isBelowFloor, isTrue);

        // An unreadable size is NOT below-floor — the UI never states RAM it
        // cannot know (the fail-closed rule).
        DeviceCapabilities.ramOverrideAckOverrideForTest = () async => false;
        DeviceCapabilities.totalMemoryOverrideForTest = () async => null;
        final unreadable = await OfflineModelSpecTable.resolve();
        expect(unreadable.deviceClass, OfflineModelClass.messageOnly);
        expect(unreadable.isMessageOnly, isTrue);
        expect(unreadable.isBelowFloor, isFalse);
      },
    );

    test(
      'the recorded unreadable edge — the ruled formula admits unreadable + ack (flagged, not silently resolved)',
      () async {
        // RECORDED EDGE (contract §3 under_floor_override unreadable_edge):
        // the ruled formula (`totalMem >= floor OR ack`) read literally
        // admits an UNREADABLE-totalMem device whose ack is recorded —
        // P2 implements it AS RULED and flags it for the Adviser. The
        // honest default WITHOUT an ack stays fail-closed, and the UI
        // never renders the RAM copy for such a device (isBelowFloor
        // false — no risk copy, no retained line can name its RAM).
        DeviceCapabilities.totalMemoryOverrideForTest = () async => null;
        DeviceCapabilities.ramOverrideAckOverrideForTest = () async => true;
        final edge = await OfflineModelSpecTable.resolve();
        expect(edge.deviceClass, OfflineModelClass.singleQwen);
        expect(edge.hasModel, isTrue);
        expect(edge.isBelowFloor, isFalse);
      },
    );

    test('the E2B asset left the table — only its uninstall id survives', () {
      final table = File(
        'lib/services/ai/offline_model_spec.dart',
      ).readAsStringSync();
      // No E2B row survives in the selection table: the asset is offered on
      // NO device any more (plan §4.9).
      expect(table, isNot(contains('gemma-4-e2b-it')));
      expect(table, isNot(contains('ModelType.gemma4')));
      expect(table, isNot(contains('ModelFileType.litertlm')));
      expect(table, isNot(contains('gemma-4-E2B-it.litertlm')));
      expect(table, isNot(contains('~2.6GB')));

      // The uninstall id survives ONLY where migration v4 needs it.
      final service = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      expect(
        service,
        contains("_e2bModelFileName = 'gemma-4-E2B-it.litertlm'"),
      );
      // The E2B identity survives nowhere: the app's identity is app-wide.
      expect(service, isNot(contains('gemma-4-e2b-it')));
    });

    test('the identity is app-wide — the message-only row carries it too', () {
      expect(OfflineModelSpecTable.appIdentity, 'minicpm5-2b-q4km');
      expect(OfflineModelSpecTable.minicpm5.identity, 'minicpm5-2b-q4km');
      // The identity string is written ONCE in the whole app — the spec
      // table (contract §2 identity_invariant).
      final table = File(
        'lib/services/ai/offline_model_spec.dart',
      ).readAsStringSync();
      expect("identity: 'minicpm5-2b-q4km'".allMatches(table).length, 1);
    });

    test(
      'the RAM floor is exactly 4 GB and an unreadable size never clears it',
      () {
        expect(
          DeviceCapabilities.minimumTotalMemoryBytes,
          4 * 1024 * 1024 * 1024,
        );
        expect(
          DeviceCapabilities.clearsMemoryFloor(4 * 1024 * 1024 * 1024),
          isTrue,
        );
        expect(
          DeviceCapabilities.clearsMemoryFloor(4 * 1024 * 1024 * 1024 - 1),
          isFalse,
        );
        expect(DeviceCapabilities.clearsMemoryFloor(null), isFalse);
      },
    );

    test('the device resolution follows the table', () async {
      // An arm64 device (the class the old table routed to E2B) gets the
      // selected spec: arm64-v8a AND the 4 GB RAM floor (C46, plan §5.3).
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          6 * 1024 * 1024 * 1024;
      final arm64 = await OfflineModelSpecTable.resolve();
      expect(arm64.deviceClass, OfflineModelClass.singleQwen);
      expect(arm64.spec, OfflineModelSpecTable.minicpm5);
      expect(arm64.hasModel, isTrue);
      expect(arm64.isMessageOnly, isFalse);

      // A non-arm64 device with 6 GB → the message-only class (NO model, NO
      // download CTA): the ABI RE-ENTERS the selection (C46, plan §5.3), so
      // no arm64-v8a means message-only whatever the RAM.
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => false;
      final nonArm64 = await OfflineModelSpecTable.resolve();
      expect(nonArm64.deviceClass, OfflineModelClass.messageOnly);
      expect(nonArm64.spec, isNull);
      expect(nonArm64.hasModel, isFalse);
      expect(nonArm64.isMessageOnly, isTrue);
      // The RAM fact is NOT applied on a no-arm64 device: the under-floor
      // override path is never entered (contract §3 message_only_class).
      expect(nonArm64.isBelowFloor, isFalse);

      // Back on an arm64 device: the RAM legs below are RAM-driven.
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;

      // 2 GB → the message-only class (no model).
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          2 * 1024 * 1024 * 1024;
      final messageOnly = await OfflineModelSpecTable.resolve();
      expect(messageOnly.deviceClass, OfflineModelClass.messageOnly);
      expect(messageOnly.spec, isNull);
      expect(messageOnly.hasModel, isFalse);
      expect(messageOnly.isMessageOnly, isTrue);

      // Unreadable RAM → the message-only class too (the fail-closed rule).
      DeviceCapabilities.totalMemoryOverrideForTest = () async => null;
      final unreadable = await OfflineModelSpecTable.resolve();
      expect(unreadable.deviceClass, OfflineModelClass.messageOnly);
      expect(unreadable.spec, isNull);
      expect(unreadable.hasModel, isFalse);

      DeviceCapabilities.offlineAiSupportedOverrideForTest = null;
      DeviceCapabilities.totalMemoryOverrideForTest = null;
    });

    test('the chat card offers the download on the selection class', () {
      // The selection decides whether the device has a model at all: the
      // selection class HAS one, so the card keeps the download affordance
      // (only the message-only class has none).
      final selectionClass = OfflineModelSpecTable.resolveClass(
        hasMemoryCapacity: true,
      );
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.modelMissing,
          isInstalled: false,
          isDeviceCompatible: selectionClass != OfflineModelClass.messageOnly,
        ),
        OfflineModelAction.getModel,
      );

      final messageOnlyClass = OfflineModelSpecTable.resolveClass(
        hasMemoryCapacity: false,
      );
      expect(
        resolveOfflineModelAction(
          state: OfflineModelState.modelMissing,
          isInstalled: false,
          isDeviceCompatible: messageOnlyClass != OfflineModelClass.messageOnly,
        ),
        OfflineModelAction.incompatibleDevice,
      );
    });
  });

  group('the model picker tile (cycle-40 P1, cycle-43 override)', () {
    setUp(() {
      // The default device clears the 4 GB RAM floor — it may run the
      // offline model. The ack's persisted store is installed too (cycle-43):
      // the sheet resolves the override state on every open.
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          6 * 1024 * 1024 * 1024;
      _installAckStore();
    });

    tearDown(() {
      DeviceCapabilities.offlineAiSupportedOverrideForTest = null;
      DeviceCapabilities.totalMemoryOverrideForTest = null;
      _resetAckSeams();
    });

    test(
      'an incompatible device without the below-floor fact keeps the plain message and offers no download',
      () {
        // The plain message-only state — an UNREADABLE-RAM device resolves
        // isBelowFloor false, so the UI never states RAM it cannot know
        // (the fail-closed rule; cycle-43).
        final state = offlineTileUnavailableState(isDeviceCompatible: false);
        expect(state.subtitle, DeviceCapabilities.incompatibleDeviceMessage);
        expect(state.canDownload, isFalse);
      },
    );

    test(
      'a below-floor device carries the risk copy first and routes the tap through the override (cycle-43)',
      () {
        final state = offlineTileUnavailableState(
          isDeviceCompatible: false,
          isBelowFloor: true,
        );
        // Warning-first (cycle-43 §6 S1): the risk copy renders FIRST, the
        // honest message-only text stays.
        expect(
          state.subtitle,
          startsWith(DeviceCapabilities.underFloorRiskCopy),
        );
        expect(
          state.subtitle,
          contains(DeviceCapabilities.incompatibleDeviceMessage),
        );
        // The tap is the OVERRIDE route, not a direct download: the ack is
        // recorded before the download flow opens (consent comes first).
        expect(state.canDownload, isFalse);
      },
    );

    test(
      'a below-floor device holding the ack keeps the enabled invitation with the retained line (cycle-43)',
      () {
        final state = offlineTileUnavailableState(
          isDeviceCompatible: true,
          isBelowFloor: true,
        );
        // The honesty leads, the enabled invitation follows — never
        // re-nagged, never silently green (contract §6
        // under_floor_post_ack).
        expect(
          state.subtitle,
          startsWith(DeviceCapabilities.underFloorRetainedRiskLine),
        );
        expect(state.subtitle, contains('Download to use offline'));
        expect(state.canDownload, isTrue);
      },
    );

    test(
      'a device that clears the RAM floor keeps the download invitation',
      () {
        final state = offlineTileUnavailableState(isDeviceCompatible: true);
        expect(state.subtitle, 'Download to use offline');
        expect(state.canDownload, isTrue);
      },
    );

    testWidgets(
      'the offline tile offers the Download anyway override on a device below the RAM floor (cycle-43)',
      (tester) async {
        // The lived reference device (cycle-43 plan §1.1), no ack yet.
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            _livedDeviceTotalMemoryBytes;
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

        // Warning-first (cycle-43 §6 S1): the risk copy renders FIRST and
        // the honest message stays, in the tile's subtitle.
        expect(
          find.textContaining(DeviceCapabilities.underFloorRiskCopy),
          findsOneWidget,
        );
        expect(
          find.textContaining(DeviceCapabilities.incompatibleDeviceMessage),
          findsOneWidget,
        );
        expect(find.text('Download to use offline'), findsNothing);
        // The override affordance is NAMED (the trailing label).
        expect(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
          findsOneWidget,
        );

        // The tap is the OVERRIDE: it records the ack (in memory AND
        // persisted) and routes into the download flow — one flow, four
        // entries.
        await tester.ensureVisible(find.text('AgentA Offline AI'));
        await tester.pump();
        await tester.tap(find.text('AgentA Offline AI'));
        await tester.pump();
        await tester.pump();
        expect(await DeviceCapabilities.hasRamOverrideAck(), isTrue);
        expect(
          await SharedPreferencesAsync().getBool(
            DeviceCapabilities.ramOverrideAckPrefsKey,
          ),
          isTrue,
        );
        expect(downloadRequested, isTrue);
      },
    );

    testWidgets(
      'the offline tile keeps the enabled invitation with the retained line post-ack (cycle-43)',
      (tester) async {
        DeviceCapabilities.ramOverrideAckOverrideForTest = () async => true;
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            _livedDeviceTotalMemoryBytes;

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
        await tester.pumpAndSettle();

        // The retained risk line leads, the enabled invitation follows —
        // never re-nagged, never silently green.
        expect(
          find.textContaining(DeviceCapabilities.underFloorRetainedRiskLine),
          findsOneWidget,
        );
        expect(find.textContaining('Download to use offline'), findsOneWidget);
        expect(
          find.textContaining(DeviceCapabilities.underFloorRiskCopy),
          findsNothing,
        );
        expect(
          find.text(DeviceCapabilities.downloadAnywayButtonLabel),
          findsNothing,
        );
      },
    );

    testWidgets(
      'the offline tile keeps the download invitation on a device that clears the RAM floor',
      (tester) async {
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
