// The offline-model selection table (cycle-42 P2, amended by P2b).
//
// ONE source of truth for WHICH model a device runs. The table is the
// authoritative implementation of `contracts/offline-model-qwen15b.yaml`
// §3 — the ONE-class selection table the lived-evidence amendment recorded
// (plan §4.9: the user's directive "make the qwen the main model offline").
//
// ONE key, read from the EXISTING capability seam
// (`device_capabilities.dart`):
//
//   * RAM verdict — the device's total memory against the 4 GB floor.
//
// ABI IS NOT A SELECTION INPUT (plan §4.9): the MediaPipe `.task` engine
// is the multi-ABI engine (cycle-40 §1.1), so the ABI verdict decides
// nothing about WHICH model a device is offered. The verdict machinery
// STAYS in `device_capabilities.dart` — the `unsupportedAbi` failure-class
// mapping still lives in `gemma_service.dart` (rarely reachable, zero risk
// — less churn than removal).
//
// E2B LEFT SELECTION ENTIRELY (plan §4.9): no device is offered the asset
// anymore, and migration v4 uninstalls it wherever it is stranded
// (contract §4). Its uninstall id survives in
// `model_download_service.dart`; this table carries the ONE asset the app
// offers.
//
// The table resolves ONCE per device (the verdict is a cached value) and
// every consumer — the install chains, the identity sites, the four UI
// surfaces and the migration trigger — reads the SAME resolved spec. The
// plugin holds one active model, so exactly one spec per device keeps that
// constraint satisfied by construction.
//
// The spec table is also the ONLY place the identity string and the asset
// URL are written: the identity sites (contract §2) reference the resolved
// spec, so the DAO row and the plugin identity can never drift.
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import 'device_capabilities.dart';

/// The device classes of the selection table (contract §3).
enum OfflineModelClass {
  /// EVERY device (any ABI) with totalMem >= 4 GB — Qwen 2.5 1.5B Instruct
  /// via the MediaPipe `.task` engine. THE one selection class.
  singleQwen,

  /// totalMem < 4 GB OR totalMem UNREADABLE — NO model at all. The honest
  /// message-only state: the RAM-reason message, no download CTA, no retry.
  messageOnly,
}

/// One asset of the selection table: everything a consumer needs to install,
/// load and label it.
class OfflineModelSpec {
  /// A stable id for the asset (used in logs and tests).
  final String id;

  /// The model identity the DB rows and the plugin carry (contract §2).
  final String identity;

  /// The install URL of the asset.
  final String url;

  /// The model type the install chain claims.
  final ModelType modelType;

  /// The file type that selects the engine — never inferred from the URL.
  final ModelFileType fileType;

  /// The size chip the download gate renders for this asset (contract §6).
  final String sizeChip;

  const OfflineModelSpec({
    required this.id,
    required this.identity,
    required this.url,
    required this.modelType,
    required this.fileType,
    required this.sizeChip,
  });
}

/// The selection resolved for one device.
class OfflineModelSelection {
  /// The class this device falls into.
  final OfflineModelClass deviceClass;

  /// The asset this device runs — null for the message-only class, which
  /// has no model at all.
  final OfflineModelSpec? spec;

  const OfflineModelSelection({required this.deviceClass, this.spec});

  /// Whether this device may run an offline model.
  bool get hasModel => spec != null;

  /// Whether this device keeps the honest message-only state: no model, no
  /// download CTA, no retry.
  bool get isMessageOnly => deviceClass == OfflineModelClass.messageOnly;
}

/// The selection table itself.
class OfflineModelSpecTable {
  const OfflineModelSpecTable._();

  // §1 THE TABLE — the ONE asset.
  //
  // Every figure is verbatim from `contracts/offline-model-qwen15b.yaml`
  // §1-§2 (v1.1.0): install URL, size 1,598,556,720 B ≈ 1.60 GB, identity
  // `qwen2.5-1.5b-it`, `ModelType.qwen` + `ModelFileType.task` on the
  // EXISTING MediaPipeEngine.

  /// Qwen 2.5 1.5B Instruct via the MediaPipe `.task` engine — the ONE
  /// selection class (every device with at least 4 GB of total memory).
  ///
  /// The q8 ekv4096 build is mandatory: its 4096-token KV ceiling covers the
  /// app's 2048-token context window (the ekv1280 build would clamp it).
  /// Ungated, 1,598,556,720 B (≈1.60 GB), no token needed.
  static const OfflineModelSpec qwen15b = OfflineModelSpec(
    id: 'qwen2.5-1.5b',
    identity: 'qwen2.5-1.5b-it',
    url:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
    sizeChip: 'Model size: ~1.6GB',
  );

  //
  // §2 THE PURE SELECTION — the one-key table as a pure function.
  //

  /// The PURE selection table: the class of a device profile.
  ///
  /// * the RAM verdict clears the floor → the single Qwen class (ANY ABI);
  /// * the RAM verdict does not clear it (too little RAM, or unreadable) →
  ///   the message-only class (no model at all).
  ///
  /// There is no ABI input: the ABI decides nothing about the selection
  /// (plan §4.9).
  @visibleForTesting
  static OfflineModelClass resolveClass({required bool hasMemoryCapacity}) {
    if (hasMemoryCapacity) return OfflineModelClass.singleQwen;
    return OfflineModelClass.messageOnly;
  }

  /// The asset of a class — null for the message-only class, which has no
  /// model at all.
  static OfflineModelSpec? specFor(OfflineModelClass deviceClass) {
    switch (deviceClass) {
      case OfflineModelClass.singleQwen:
        return qwen15b;
      case OfflineModelClass.messageOnly:
        return null;
    }
  }

  //
  // §3 THE DEVICE RESOLUTION — the table applied to this device.
  //

  /// Resolves THIS device's selection from the capability seam.
  ///
  /// The RAM verdict is a cached value, so the table is resolved once per
  /// device and every consumer sees the same spec. An UNREADABLE memory
  /// size never clears the floor: the device keeps the message-only
  /// honesty (the fail-closed rule, plan §6 S8).
  static Future<OfflineModelSelection> resolve() async {
    final hasMemoryCapacity = await DeviceCapabilities.hasMemoryCapacity();
    final deviceClass = resolveClass(hasMemoryCapacity: hasMemoryCapacity);
    return OfflineModelSelection(
      deviceClass: deviceClass,
      spec: specFor(deviceClass),
    );
  }

  /// The asset this device runs — null for the message-only class.
  ///
  /// A caller that needs an asset MUST handle the null: the message-only
  /// class has nothing to install.
  static Future<OfflineModelSpec?> currentSpec() async =>
      (await resolve()).spec;

  //
  // §4 THE IDENTITY — what the DB rows carry.
  //

  /// The app's offline-model identity — APP-WIDE (contract §3).
  ///
  /// The identity is the app's offline-model NAME, not the installed asset:
  /// the message-only row never installs anything, yet its DB rows still
  /// record the app's identity (`qwen2.5-1.5b-it`). The identity string is
  /// written HERE and NOWHERE else in `lib/` (contract §2
  /// identity_invariant).
  static String get appIdentity => qwen15b.identity;
}
