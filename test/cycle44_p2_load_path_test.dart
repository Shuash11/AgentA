// cycle-44 P2 — the Branch-A load-path repair (the device-scout verdict (A):
// a Gemma file was answering).
//
// The proof surface of this file:
//   * migration v5 — the three legs (foreign file / foreign active / the
//     lie), the COMPOSITE probe, the marker semantics and the four
//     compositions the ruling names;
//   * the four compositions against the C46 GGUF spec (plan §5.4,
//     contract `offline-model-minicpm5` §4): the shipped `.task` + the E2B
//     straggler are swept as foreign, the healthy GGUF device mutates
//     NOTHING, and the message-only device (no arm64-v8a) is swept once
//     with no uninstall loop and no download;
//   * ensureModelActive() — the load-time VERIFICATION: a foreign active
//     spec is cleared and the selected spec ends ACTIVE;
//   * the caller guard — the restored foreign active spec now REACHES the
//     verification;
//   * the two riders — the short spec-driven instruction and the honest
//     picker copy.
//
// The plugin is faked through the app's OWN seam
// (`ModelDownloadService.pluginOverrideForTest`), so the fake mirrors the
// pinned plugin's semantics (flutter_edge_ai 1.11.4):
//   * the repository ids are persisted FILENAMES;
//   * the active model carries the spec name — the persisted filename after
//     a restore, the extension-stripped basename after an install;
//   * `uninstallModel` THROWS on an unknown id and does NOT clear the
//     active identity.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/core/config/app_config.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/offline_model_dao.dart';
import 'package:aiproject/services/ai/ai_model.dart';
import 'package:aiproject/services/ai/device_capabilities.dart';
import 'package:aiproject/services/ai/gemma_service.dart';
import 'package:aiproject/services/ai/model_download_service.dart';
import 'package:aiproject/services/ai/offline_model_spec.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  SharedPreferences.setMockInitialValues({});

  late Database db;
  late ModelDownloadService service;
  late FakeOfflineModelPlugin plugin;

  /// The selected asset's persisted filename — the id the plugin keys the
  /// model by.
  const String selectedFileName =
      'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task';

  /// The superseded Gemma 3 1B asset — the foreign file the user's device
  /// still held.
  const String legacyFileName = 'gemma3-1b-it-int4.task';

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
    service = ModelDownloadService();
    plugin = FakeOfflineModelPlugin();
    await db.delete('offline_model_status');
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // The device clears the RAM floor — the ONE selection class.
    DeviceCapabilities.totalMemoryOverrideForTest = () async =>
        6 * 1024 * 1024 * 1024;
    // v3/v4 never fire in this file: their probes are the legacy assets,
    // not the state under test. Their own logic stays byte-for-byte
    // untouched.
    ModelDownloadService.legacyAssetPresentOverrideForTest = () async => false;
    ModelDownloadService.e2bAssetPresentOverrideForTest = () async => false;
    ModelDownloadService.uninstallOverrideForTest = (modelId) async {};
    ModelDownloadService.pluginOverrideForTest = plugin;
    ModelDownloadService.ensureInstallOverrideForTest = null;
  });

  tearDown(() {
    service.dispose();
    ModelDownloadService.legacyAssetPresentOverrideForTest = null;
    ModelDownloadService.e2bAssetPresentOverrideForTest = null;
    ModelDownloadService.uninstallOverrideForTest = null;
    ModelDownloadService.pluginOverrideForTest = null;
    ModelDownloadService.ensureInstallOverrideForTest = null;
    DeviceCapabilities.totalMemoryOverrideForTest = null;
    // The ABI verdict is a C46 selection key (arm64-v8a ∈ SUPPORTED_ABIS):
    // a test that refuses the ABI must not leak into the next case.
    DeviceCapabilities.offlineAiSupportedOverrideForTest = null;
  });

  group('cycle-44 P2 — the selected asset identity', () {
    test('the selected filename is the asset\'s persisted filename', () {
      expect(
        ModelDownloadService.selectedFileNameFor(OfflineModelSpecTable.qwen15b),
        selectedFileName,
      );
    });

    test(
      'the identity comparison accepts the plugin\'s two representations',
      () {
        // The RESTORE path names the model by the persisted filename; the
        // INSTALL path names it by the extension-stripped basename. Both are
        // the SAME model — a raw-string comparison would call the app's own
        // freshly installed model "foreign".
        expect(
          ModelDownloadService.isSameModelIdentity(
            selectedFileName,
            selectedFileName,
          ),
          isTrue,
        );
        expect(
          ModelDownloadService.isSameModelIdentity(
            'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096',
            selectedFileName,
          ),
          isTrue,
        );
        // A foreign model never matches — not by name, not by extension.
        expect(
          ModelDownloadService.isSameModelIdentity(
            legacyFileName,
            selectedFileName,
          ),
          isFalse,
        );
        expect(
          ModelDownloadService.isSameModelIdentity(
            'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
            selectedFileName,
          ),
          isFalse,
        );
        expect(
          ModelDownloadService.isSameModelIdentity(null, selectedFileName),
          isFalse,
        );
      },
    );
  });

  group('cycle-44 P2 — migration v5: the three legs', () {
    test(
      'leg (a): a foreign file is swept and the selected file is never touched',
      () async {
        plugin = FakeOfflineModelPlugin(
          installed: [legacyFileName, selectedFileName],
        );
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        expect(plugin.uninstalled, [legacyFileName]);
        // The sweep NEVER touches the derived selected filename — the
        // selected asset's file survives, so no re-download is forced.
        expect(plugin.uninstalled, isNot(contains(selectedFileName)));
        expect(plugin.installedIds, contains(selectedFileName));
      },
    );

    test('leg (b): a foreign active model is cleared', () async {
      plugin = FakeOfflineModelPlugin(
        installed: [selectedFileName],
        activeModelName: legacyFileName,
        hasActive: true,
      );
      ModelDownloadService.pluginOverrideForTest = plugin;

      await service.checkModelExists();

      // The plugin's uninstallModel does NOT clear the identity — the
      // reconciliation does, which is what stops the next-launch
      // resurrection.
      expect(plugin.clearCount, 1);
      expect(plugin.hasActive, isFalse);
    });

    test(
      'leg (c): the lie is detected by the composite probe and the row is reset',
      () async {
        // The user's device: the DAO claims the asset is installed, the
        // plugin says the file is gone, and a foreign model is active.
        await OfflineModelDao().setModelReady(
          modelType: OfflineModelSpecTable.appIdentity,
        );
        plugin = FakeOfflineModelPlugin(
          installed: [legacyFileName],
          activeModelName: legacyFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        // The DAO reconciles to plugin truth...
        final row = await db.query('offline_model_status');
        expect(row.first['status'], 'notInstalled');
        expect(row.first['model_type'], 'qwen2.5-1.5b-it');
        // ...and the gate's readiness read honestly offers the fresh install.
        expect(service.status, ModelStatus.notInstalled);
      },
    );

    test(
      'the composite probe: a lying file probe alone never resets the row',
      () async {
        // The file IS installed (the plugin probe says so) while the active
        // model is foreign: the composite probe disagrees, so the row is
        // NOT touched — a single lying probe can never loop the download.
        await OfflineModelDao().setModelReady(
          modelType: OfflineModelSpecTable.appIdentity,
        );
        plugin = FakeOfflineModelPlugin(
          installed: [selectedFileName],
          activeModelName: legacyFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        final row = await db.query('offline_model_status');
        expect(row.first['status'], 'ready');
      },
    );

    test(
      'the composite probe: a lying active probe alone never resets the row',
      () async {
        // The file is gone (the plugin probe says so) while the active
        // identity names the SELECTED model: the composite probe disagrees,
        // so the row is NOT touched.
        await OfflineModelDao().setModelReady(
          modelType: OfflineModelSpecTable.appIdentity,
        );
        plugin = FakeOfflineModelPlugin(
          installed: const <String>[],
          activeModelName: selectedFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        final row = await db.query('offline_model_status');
        expect(row.first['status'], 'ready');
      },
    );

    test(
      'the sweep is tolerant: an unknown id never breaks the pass',
      () async {
        final prefs = await SharedPreferences.getInstance();
        plugin = FakeOfflineModelPlugin(installed: [legacyFileName]);
        // The pinned core throws 'Model not found' for an id it does not know.
        plugin.unknownIds.add(legacyFileName);
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        // The throw was swallowed — the pass continued and the gate is still
        // readable.
        expect(plugin.uninstalled, isEmpty);
        expect(service.status, ModelStatus.notInstalled);
        // The state is NOT clean (the file is still there) → no marker.
        expect(prefs.getBool('model_asset_v5'), isNull);
      },
    );
  });

  group('cycle-44 P2 — migration v5: the marker semantics', () {
    test('the marker is written only after a verified-clean state', () async {
      final prefs = await SharedPreferences.getInstance();

      // A foreign file that cannot be removed → NOT clean → NO marker.
      plugin = FakeOfflineModelPlugin(installed: [legacyFileName]);
      plugin.failingUninstalls.add(legacyFileName);
      ModelDownloadService.pluginOverrideForTest = plugin;

      await service.checkModelExists();

      expect(prefs.getBool('model_asset_v5'), isNull);

      // The next pass removes it → the state is verified clean → the marker
      // is written. (The marker-first pattern would have stranded the
      // repair after the first failure — the ruled deviation.)
      plugin.failingUninstalls.clear();

      await service.checkModelExists();

      expect(plugin.uninstalled, [legacyFileName]);
      expect(prefs.getBool('model_asset_v5'), isTrue);
    });

    test(
      'the marker skips ONLY the sweep leg — a foreign active is still repaired',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('model_asset_v5', true);
        plugin = FakeOfflineModelPlugin(
          installed: [legacyFileName, selectedFileName],
          activeModelName: legacyFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        // The sweep leg is skipped by the marker (the recorded edge: a file
        // introduced behind the marker lingers)...
        expect(plugin.uninstalled, isEmpty);
        // ...but leg (b) still ran: the foreign identity is cleared.
        expect(plugin.clearCount, 1);
      },
    );

    test(
      'the marker skips ONLY the sweep leg — the lie is still detected',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('model_asset_v5', true);
        await OfflineModelDao().setModelReady(
          modelType: OfflineModelSpecTable.appIdentity,
        );
        plugin = FakeOfflineModelPlugin(
          installed: const <String>[],
          activeModelName: legacyFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        // Leg (c) ran even though the marker is set.
        final row = await db.query('offline_model_status');
        expect(row.first['status'], 'notInstalled');
      },
    );
  });

  group('cycle-44 P2 — migration v5: the compositions', () {
    test(
      'both assets: the foreign file goes, the selected file AND row survive',
      () async {
        await OfflineModelDao().setModelReady(
          modelType: OfflineModelSpecTable.appIdentity,
        );
        plugin = FakeOfflineModelPlugin(
          installed: [legacyFileName, selectedFileName],
          activeModelName: legacyFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        expect(plugin.uninstalled, [legacyFileName]);
        // The selected file survives — no re-download is forced.
        expect(plugin.installedIds, contains(selectedFileName));
        // ...and its row survives: the readiness read FINDS the model.
        final row = await db.query('offline_model_status');
        expect(row.first['status'], 'ready');
        expect(service.status, ModelStatus.ready);
      },
    );

    test(
      "the user's device: the gemma file goes, the identity is cleared, the row is reset",
      () async {
        await OfflineModelDao().setModelReady(
          modelType: OfflineModelSpecTable.appIdentity,
        );
        plugin = FakeOfflineModelPlugin(
          installed: [legacyFileName],
          activeModelName: legacyFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        expect(plugin.uninstalled, [legacyFileName]);
        expect(plugin.clearCount, 1);
        final row = await db.query('offline_model_status');
        expect(row.first['status'], 'notInstalled');
        // The gate offers the fresh install — the honest state.
        expect(service.status, ModelStatus.notInstalled);
      },
    );

    test('the healthy selected device: zero mutations', () async {
      // The healthy GGUF device: arm64-v8a present (the C46 ABI key) and
      // the RAM floor cleared (setUp: 6 GB), with the GGUF installed AND
      // active.
      DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;
      await OfflineModelDao().setModelReady(
        modelType: OfflineModelSpecTable.appIdentity,
      );
      plugin = FakeOfflineModelPlugin(
        installed: [selectedFileName],
        activeModelName: selectedFileName,
        hasActive: true,
      );
      ModelDownloadService.pluginOverrideForTest = plugin;

      await service.checkModelExists();

      expect(plugin.uninstalled, isEmpty);
      expect(plugin.clearCount, 0);
      final row = await db.query('offline_model_status');
      expect(row.first['status'], 'ready');
      expect(service.status, ModelStatus.ready);
    });

    test('the message-only device holding a file: the file is swept', () async {
      // Below the RAM floor → the message-only class → NO legal asset, so
      // EVERY file is foreign.
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          2 * 1024 * 1024 * 1024;
      plugin = FakeOfflineModelPlugin(
        installed: [legacyFileName],
        activeModelName: legacyFileName,
        hasActive: true,
      );
      ModelDownloadService.pluginOverrideForTest = plugin;

      await service.checkModelExists();

      expect(plugin.uninstalled, [legacyFileName]);
      expect(plugin.clearCount, 1);
    });

    // ── cycle-46 ladder (plan §5.1 rung (b), stop rule S6): the FOUR
    // compositions against the RESTORED .task spec. The v5 reconciliation
    // generalizes: the leftover MiniCPM5 GGUF (the failed cycle-46 attempt
    // still installed on real devices) and any E2B straggler are FOREIGN
    // the moment the spec points back at the .task, so NO new migration
    // code (and NO v6 marker) is needed.

    test(
      "both foreign assets: the leftover MiniCPM5 GGUF AND the E2B straggler are swept",
      () async {
        // The ruling names the TWO assets by their persisted filenames
        // (contract §4 `ruling_no_new_marker`): the leftover MiniCPM5 GGUF
        // from the reverted attempt and the E2B straggler. v3/v4 never fire
        // here (their probes are
        // stubbed off in setUp) — the v5 sweep alone must carry both.
        const String leftoverGgufFileName = 'MiniCPM5-2B-Q4_K_M.gguf';
        const String e2bStragglerFileName = 'gemma-4-E2B-it.litertlm';

        // The device lies: the DAO row claims a model is installed while
        // the plugin holds only the two foreign assets.
        await OfflineModelDao().setModelReady(
          modelType: OfflineModelSpecTable.appIdentity,
        );
        plugin = FakeOfflineModelPlugin(
          installed: [leftoverGgufFileName, e2bStragglerFileName],
          activeModelName: leftoverGgufFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        // BOTH foreign assets are swept — the selected .task filename is
        // NEVER swept (no_stranded_downloads is absolute).
        expect(plugin.uninstalled, [
          leftoverGgufFileName,
          e2bStragglerFileName,
        ]);
        expect(plugin.uninstalled, isNot(contains(selectedFileName)));
        expect(plugin.installedIds, isNot(contains(selectedFileName)));
        // The stale active identity is cleared (leg b).
        expect(plugin.clearCount, 1);
        expect(plugin.hasActive, isFalse);
        // The LYING DAO row is reset (leg c) → the gate honestly offers the
        // fresh .task install.
        final row = await db.query('offline_model_status');
        expect(row.first['status'], 'notInstalled');
        expect(service.status, ModelStatus.notInstalled);
        // The v5 marker records the verified-clean state — and NO v6 marker
        // exists (the composition needed no new migration code).
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('model_asset_v5'), isTrue);
        expect(prefs.getBool('model_asset_v6'), isNull);
      },
    );

    test(
      'the message-only device (no arm64-v8a) holding files: swept once, no loop, no download',
      () async {
        // C46 §5.3: NO arm64-v8a → the message-only class (no legal asset),
        // so EVERY id is foreign and the v5 sweep removes them (contract §4
        // composition 4). The sweep runs ONCE — the verified-clean marker
        // gates the next pass, so the device never enters an uninstall
        // loop — and the message-only class NEVER starts a download.
        DeviceCapabilities.offlineAiSupportedOverrideForTest = () async =>
            false;
        const String shippedTaskFileName =
            'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task';

        // The device resolves the message-only class: no asset → no CTA.
        final selection = await OfflineModelSpecTable.resolve();
        expect(selection.deviceClass, OfflineModelClass.messageOnly);
        expect(selection.spec, isNull);
        expect(selection.hasModel, isFalse);

        plugin = FakeOfflineModelPlugin(
          installed: [shippedTaskFileName],
          activeModelName: shippedTaskFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;

        await service.checkModelExists();

        // The file is swept (every id is foreign when spec == null) and the
        // stale active identity is cleared.
        expect(plugin.uninstalled, [shippedTaskFileName]);
        expect(plugin.clearCount, 1);

        // NO uninstall loop: the next pass sweeps NOTHING (the marker
        // records the verified-clean state).
        await service.checkModelExists();
        expect(plugin.uninstalled, [shippedTaskFileName]);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('model_asset_v5'), isTrue);

        // NO download: the message-only class has no asset to install.
        var installs = 0;
        service.installOverrideForTest = (token) async {
          installs++;
        };
        await service.installModel();

        expect(installs, 0);
        expect(service.status, ModelStatus.notInstalled);
      },
    );
  });

  group('cycle-44 P2 — the load seam: ensureModelActive', () {
    test(
      'a foreign active spec is cleared and the selected spec ends ACTIVE',
      () async {
        // The user's device: the plugin restored the legacy model, so the
        // old `hasActiveModel()` early return blessed it forever.
        plugin = FakeOfflineModelPlugin(
          installed: [legacyFileName],
          activeModelName: legacyFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;
        var installs = 0;
        ModelDownloadService.ensureInstallOverrideForTest = (spec) async {
          installs++;
          plugin.activateInstalled();
        };

        final active = await ModelDownloadService.ensureModelActive();

        expect(active, isTrue);
        expect(installs, 1);
        // The foreign identity is gone...
        expect(plugin.clearCount, greaterThan(0));
        // ...and the SELECTED model is the active one.
        expect(
          ModelDownloadService.isSameModelIdentity(
            plugin.activeModelName,
            selectedFileName,
          ),
          isTrue,
        );
      },
    );

    test("the plugin's install-path identity IS the selected model", () async {
      // The plugin names the model after the extension-stripped basename
      // when it installs. A raw-string comparison would call the app's own
      // freshly installed model "foreign" — clearing the identity and
      // re-installing on EVERY load.
      plugin = FakeOfflineModelPlugin(
        installed: [selectedFileName],
        activeModelName: FakeOfflineModelPlugin.selectedInstallPathName,
        hasActive: true,
      );
      ModelDownloadService.pluginOverrideForTest = plugin;
      var installs = 0;
      ModelDownloadService.ensureInstallOverrideForTest = (spec) async {
        installs++;
        plugin.activateInstalled();
      };

      final active = await ModelDownloadService.ensureModelActive();

      expect(active, isTrue);
      // A verified match returns WITHOUT an install and WITHOUT a clear.
      expect(installs, 0);
      expect(plugin.clearCount, 0);
    });

    test(
      'a restored identity with a missing file triggers the repair',
      () async {
        // The identity names the right model but the file is gone — the
        // device-scout lie. The verification must NOT trust the identity.
        plugin = FakeOfflineModelPlugin(
          installed: const <String>[],
          activeModelName: selectedFileName,
          hasActive: true,
        );
        ModelDownloadService.pluginOverrideForTest = plugin;
        var installs = 0;
        ModelDownloadService.ensureInstallOverrideForTest = (spec) async {
          installs++;
          plugin.activateInstalled();
        };

        final active = await ModelDownloadService.ensureModelActive();

        expect(active, isTrue);
        expect(installs, 1);
        // The lying identity was cleared before the repair.
        expect(plugin.clearCount, 1);
      },
    );

    test('one repair pass per call — the install runs at most once', () async {
      plugin = FakeOfflineModelPlugin(
        installed: const <String>[],
        activeModelName: legacyFileName,
        hasActive: true,
      );
      ModelDownloadService.pluginOverrideForTest = plugin;
      var installs = 0;
      ModelDownloadService.ensureInstallOverrideForTest = (spec) async {
        installs++;
        plugin.activateInstalled();
      };

      await ModelDownloadService.ensureModelActive();

      expect(installs, 1);
    });

    test(
      'the message-only class: nothing is installed and the load is refused',
      () async {
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            2 * 1024 * 1024 * 1024;
        var installs = 0;
        ModelDownloadService.ensureInstallOverrideForTest = (spec) async {
          installs++;
        };

        final active = await ModelDownloadService.ensureModelActive();

        expect(active, isFalse);
        expect(installs, 0);
      },
    );
  });

  group('cycle-44 P2 — the caller guard is dropped', () {
    test('the load calls the verification unconditionally', () {
      final source = File(
        'lib/services/ai/gemma_service.dart',
      ).readAsStringSync();
      final body = _methodBody(source, 'Future<void> _performLoad()');
      expect(body, isNotEmpty);
      expect(body, contains('await ModelDownloadService.ensureModelActive();'));
      // The old guard skipped the verification on a device that HAD an
      // active model — exactly the user's device, where the plugin restored
      // the legacy model.
      expect(body, isNot(contains('!FlutterEdgeAi.hasActiveModel()')));
    });

    test('a restored foreign active spec REACHES the verification', () async {
      // The user's device state: the plugin restored the legacy model, so
      // `hasActiveModel()` is TRUE. With the old guard the repair was
      // never reached in exactly this state — and the foreign model
      // answered.
      plugin = FakeOfflineModelPlugin(
        installed: [legacyFileName],
        activeModelName: legacyFileName,
        hasActive: true,
      );
      ModelDownloadService.pluginOverrideForTest = plugin;
      var installs = 0;
      ModelDownloadService.ensureInstallOverrideForTest = (spec) async {
        installs++;
        plugin.activateInstalled();
      };

      final gemma = GemmaService();
      // The native engine is absent in a unit test, so the load fails —
      // AFTER the verification ran.
      await expectLater(gemma.loadInstalled(), throwsA(anything));

      // The verification ran: the foreign identity was cleared and the
      // selected spec was activated.
      expect(plugin.clearCount, greaterThan(0));
      expect(installs, 1);
      gemma.dispose();
    });
  });

  group('cycle-44 P2 — the riders', () {
    test(
      'the system instruction is short, spec-driven and carries the identity line',
      () {
        final instruction = OfflineModelSpecTable.systemInstruction;

        // The opener stays — the §10 grep anchor.
        expect(instruction, startsWith('You are AgentA'));
        // The English rule stays.
        expect(instruction, contains(AppConfig.aiEnglishRule));
        // ONE direct-answer directive (Bug A).
        expect(
          instruction,
          contains("Answer the user's latest message directly and correctly."),
        );
        expect(instruction, contains('Show the working for math.'));
        // The identity line, VERBATIM.
        expect(
          instruction,
          contains(
            "If asked what model you are, say you are AgentA's built-in "
            'offline assistant.',
          ),
        );
        // The ~700-char rule-list is retired.
        expect(instruction, isNot(contains('Rules:')));
        expect(instruction, isNot(contains('Formatting rules:')));
        expect(instruction.length, lessThan(400));
      },
    );

    test('the chat seam consumes the spec-driven instruction', () {
      final source = File(
        'lib/services/ai/gemma_service.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('systemInstruction: OfflineModelSpecTable.systemInstruction'),
      );
      // The retired rule-list const is gone from the chat service.
      expect(source, isNot(contains('_systemInstruction')));
    });

    test('the picker copy states the honest ~1.6GB download', () {
      expect(
        AIModel.gemma.description,
        'Smarter offline AI — ~1.6GB download, runs on your device',
      );
    });

    test('the stale 2.6GB wording is retired from lib/', () {
      final hits = <String>[];
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        if (file.readAsStringSync().contains('2.6GB')) hits.add(file.path);
      }
      expect(hits, isEmpty);
    });
  });
}

/// The body of the method whose signature is [signature] (the source-level
/// assertion seam the existing service tests use).
String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) return '';
  // Methods of these classes are indented by two spaces, so the first
  // two-space closing brace ends the body (nested blocks close deeper).
  final end = source.indexOf('\n  }', start);
  if (end == -1) return '';
  return source.substring(start, end);
}

/// The fake plugin the load-path repair reads.
///
/// Mirrors the pinned plugin's semantics (flutter_edge_ai 1.11.4):
///   * the installed ids are the persisted FILENAMES;
///   * the active model carries the spec name;
///   * `uninstallModel` throws on an id the repository does not know and
///     does NOT clear the active identity;
///   * `clearActiveInferenceIdentity` clears the in-memory identity AND the
///     persisted one.
class FakeOfflineModelPlugin implements OfflineModelPlugin {
  FakeOfflineModelPlugin({
    List<String> installed = const <String>[],
    this.activeModelName,
    this.hasActive = false,
    List<String>? installedFiles,
  }) : _installed = List<String>.of(installed),
       _installedFiles = Set<String>.of(installedFiles ?? installed);

  /// The plugin's install-path identity of the selected asset — the
  /// extension-stripped basename (`inference_installation_builder.dart:419`
  /// — `FileNameUtils.getBaseName(...)` strips the `.gguf`).
  static const String selectedInstallPathName =
      'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096';

  final List<String> _installed;
  final Set<String> _installedFiles;

  /// The active model's identity (the plugin's spec name).
  String? activeModelName;

  /// Whether the plugin holds an active inference model.
  bool hasActive;

  /// The ids passed to `uninstallModel`, in order.
  final List<String> uninstalled = <String>[];

  /// How many times the active identity was cleared.
  int clearCount = 0;

  /// The ids whose uninstall FAILS (the real plugin throws 'Model not
  /// found' on an id it does not know; a file-delete failure behaves the
  /// same way).
  final Set<String> failingUninstalls = <String>{};

  /// The ids the plugin's repository does not know — `uninstallModel`
  /// throws for them, exactly like the pinned core.
  final Set<String> unknownIds = <String>{};

  /// The ids the plugin still holds.
  List<String> get installedIds => List<String>.unmodifiable(_installed);

  /// Mirrors the plugin's install path: the model is ACTIVATED and its
  /// identity is the extension-stripped basename.
  void activateInstalled() {
    activeModelName = selectedInstallPathName;
    hasActive = true;
  }

  @override
  Future<List<String>?> listInstalledModels() async =>
      List<String>.of(_installed);

  @override
  bool hasActiveModel() => hasActive;

  @override
  String? activeModelSpecName() => activeModelName;

  @override
  Future<bool?> isModelInstalled(String fileName) async =>
      _installedFiles.contains(fileName);

  @override
  Future<void> uninstallModel(String modelId) async {
    if (unknownIds.contains(modelId) ||
        failingUninstalls.contains(modelId) ||
        !_installed.contains(modelId)) {
      throw Exception('Model not found: $modelId');
    }
    _installed.remove(modelId);
    _installedFiles.remove(modelId);
    uninstalled.add(modelId);
  }

  @override
  Future<void> clearActiveInferenceIdentity() async {
    clearCount++;
    activeModelName = null;
    hasActive = false;
  }
}
