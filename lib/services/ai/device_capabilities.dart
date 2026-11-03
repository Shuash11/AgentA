import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device capabilities the offline surface reads.
///
/// ONE source of truth for the app's offline-model capability facts: the
/// device's ABI (`android.os.Build.SUPPORTED_ABIS`) and its total memory
/// (`ActivityManager.MemoryInfo.totalMem`), both over the SAME
/// MethodChannel (the cycle-28 native-channel precedent, `MainActivity.kt`).
/// No package dependency was added: the pubspec carries no ABI-reporting
/// dependency (`device_info_plus` is absent), and the plan pre-authorizes
/// the native channel as the fallback.
///
/// Cycle-46 P2 (plan §5.3, contract `offline-model-minicpm5` §3) re-keys
/// the eligibility table: the GGUF asset's engine ships Android native
/// libraries for arm64-v8a (and x86_64) only, so the ABI is a selection
/// input AGAIN (it was RAM-only from C42-P2b to C45):
///
///   * arm64-v8a ∈ SUPPORTED_ABIS AND totalMem ≥ 4 GB → eligible: the GGUF
///     spec and the normal download CTA;
///   * arm64-v8a AND totalMem < 4 GB → the C43 override path: the honest
///     estimated-peak warning + "Download anyway", never a default;
///   * NO arm64-v8a → message-only, NO download CTA — the ABI is the
///     reason, so the memory fact and the override ack are not applied.
///
/// Cycle-43 (contract `offline-model-minicpm5` §3 `under_floor_override_class`,
/// carrying `offline-model-qwen15b` §3) adds the ONE user-consent input: the
/// persisted "Download anyway" ack. A device below the RAM floor first sees
/// the honest risk copy (warning-first, cycle-43 §6 S1); an explicit tap
/// records the ack — a user PREFERENCE, never auto-cleared, never a migration
/// marker — and admits the SAME spec (below-floor + ack ⇒ eligible on an
/// arm64 device, the ruled verdict `totalMem >= floor OR ack`). The failure
/// path is untouched: an OOM/kill on an overridden device classifies exactly
/// as before.
class DeviceCapabilities {
  const DeviceCapabilities._();

  /// The honest message every offline surface shows when the device cannot
  /// run the offline model (contract `offline-model-minicpm5` §3
  /// `message_only_class`, §9 `message_only_wording`).
  ///
  /// It states BOTH eligibility requirements — arm64-v8a support AND the
  /// 4 GB RAM floor — and offers no action: a no-arm64 device can never be
  /// repaired by a download, and the below-floor state carries its own
  /// consent copy ([underFloorRiskCopy]).
  static const String incompatibleDeviceMessage =
      'The offline AI requires a 64-bit ARM (arm64-v8a) device with at '
      'least 4 GB of RAM.';

  /// The ABI the pinned engine requires on Android.
  static const String requiredAbi = 'arm64-v8a';

  /// The RAM floor of the offline model (contract `offline-model-minicpm5`
  /// §3 and §5, carrying the C42/C43 machinery).
  ///
  /// The asset's peak RSS is an UNVERIFIED ESTIMATE of ≈ 2.0–2.3 GB on
  /// Android (plan §2.5: no vendor-measured figure exists for this asset),
  /// so a device with less than 4 GB of TOTAL memory cannot hold the
  /// runtime with margin. A device below the floor is never offered the
  /// asset BY DEFAULT — it first sees the honest risk copy
  /// ([underFloorRiskCopy]) + the "Download anyway" button, and an explicit
  /// user override AFTER that warning admits the SAME asset
  /// ([hasRamOverrideAck], the informed-consent discipline, cycle-43 §6 S1).
  static const int minimumTotalMemoryBytes = 4 * 1024 * 1024 * 1024;

  /// The native channel that answers with `Build.SUPPORTED_ABIS` and
  /// `ActivityManager.MemoryInfo.totalMem`.
  static const MethodChannel _channel = MethodChannel(
    'com.agenta.agenta/device',
  );

  // ── The under-floor override copy (cycle-43, re-figured at C46) ─────────
  //
  // The UX copy of the override state, carrying the C43 warning-first
  // discipline VERBATIM (contract `offline-model-qwen15b` §6
  // under_floor_first_use / under_floor_post_ack) and the C46 figures
  // (contract `offline-model-minicpm5` §9 `under_floor_override_copy`).
  // The strings live beside [incompatibleDeviceMessage]: they are copy of
  // the capability state, not of any one surface.

  /// The first-use risk copy of an under-floor device (contract
  /// `offline-model-minicpm5` §9 `under_floor_override_copy`). It renders
  /// FIRST on every message-only surface, ahead of any download affordance
  /// (warning-first, cycle-43 §6 S1).
  ///
  /// The ~1.6 GB figure is the GGUF asset's download size (contract §1);
  /// the 2.0–2.3 GB peak is the plan §2.5 ESTIMATE — the copy says so, and
  /// it must never be presented as measured (plan §9 S6).
  static const String underFloorRiskCopy =
      'This phone has less than 4 GB of RAM. The model is a ~1.6 GB '
      'download, and its peak memory use is estimated at about 2.0–2.3 GB '
      '— an estimate, not a measurement. The system may close it when '
      'memory runs low.';

  /// The override button's label (contract §6 `under_floor_first_use` —
  /// VERBATIM). The label names the consequence, not a yes/no (the
  /// confirmation-dialog discipline: the option summarises what happens).
  static const String downloadAnywayButtonLabel = 'Download anyway';

  /// The retained risk line shown after the recorded ack, whenever the
  /// download is enabled on an under-floor device (contract
  /// `offline-model-minicpm5` §9 `under_floor_override_copy`, carrying the
  /// C43 `under_floor_post_ack` discipline — VERBATIM). Never re-nagged
  /// (the full risk copy and the button do not repeat), never silently
  /// green (the line always accompanies the enabled download).
  static const String underFloorRetainedRiskLine =
      'Low-RAM device: the model may be closed when memory runs low.';

  /// The cached verdict — a resolved VALUE, never a Future.
  ///
  /// A cached Future is poison across `testWidgets` cases: a future created
  /// inside a finished fake-async zone registers its listeners in that dead
  /// zone, so awaiting it in a later case never resumes and the caller hangs
  /// forever. The verdict is cached instead, and every call gets a fresh
  /// future of its own.
  static bool? _cachedSupport;

  /// Test seam: replaces the native detection entirely.
  ///
  /// A test sets it to simulate an incompatible device; production never
  /// sets it.
  @visibleForTesting
  static Future<bool> Function()? offlineAiSupportedOverrideForTest;

  /// Whether the device reports the ABI the offline engine requires on
  /// Android: `arm64-v8a` membership in `Build.SUPPORTED_ABIS`.
  ///
  /// This is the ABI key of the C46 eligibility table (plan §5.3,
  /// contract `offline-model-minicpm5` §3): a device without arm64-v8a is
  /// the message-only class, whatever its RAM. [totalMemoryBytes] and
  /// [hasRamOverrideAck] are qualified by this verdict, so the spec table's
  /// existing `hasMemoryCapacity || overrideAck` formula resolves the three
  /// states correctly and a no-arm64 device never enters the RAM-override
  /// path.
  ///
  /// Resolves to `true` when the device cannot be asked (non-Android
  /// platforms, a missing native handler): an unknown device keeps the
  /// current behaviour and the load-time failure class is the backstop.
  static Future<bool> isOfflineAiSupported() {
    final override = offlineAiSupportedOverrideForTest;
    if (override != null) return override();
    final cached = _cachedSupport;
    if (cached != null) return Future<bool>.value(cached);
    return _detectAndCache();
  }

  /// Runs the detection once and remembers its verdict.
  ///
  /// The ABI cannot change while the process runs, so the answer is cached
  /// for every later caller. A caller that arrives while the detection is
  /// still running performs its own (cheap, local) read instead of joining
  /// the in-flight future: sharing that future across zones is what breaks
  /// the widget tests.
  static Future<bool> _detectAndCache() async {
    final supported = await _detect();
    _cachedSupport = supported;
    return supported;
  }

  /// The pure C46 ABI-membership verdict (the eligibility key).
  ///
  /// `arm64-v8a` must be PRESENT in the platform's list (contract
  /// `offline-model-minicpm5` §3: `arm64-v8a ∈ SUPPORTED_ABIS`). This is
  /// deliberately membership, not the first-64-bit rule of
  /// [isCompatibleAbi]. An empty or null list means "unknown" and fails
  /// open (the load-time failure class is the backstop).
  @visibleForTesting
  static bool hasRequiredAbi(List<String>? supportedAbis) {
    if (supportedAbis == null || supportedAbis.isEmpty) return true;
    return supportedAbis.contains(requiredAbi);
  }

  /// The historical first-64-bit ABI guard (cycle-40).
  ///
  /// NOT the C46 eligibility key any more — [hasRequiredAbi] is (membership,
  /// contract `offline-model-minicpm5` §3). This pure rule remains the
  /// recorded provenance of the load-time `unsupportedAbi` failure-class
  /// mapping: the app process runs the device's FIRST 64-bit ABI, so under
  /// the old arm64-only engine an x86_64 emulator that also listed
  /// arm64-v8a could not load the model. The current selection never
  /// calls it.
  @visibleForTesting
  static bool isCompatibleAbi(List<String>? supportedAbis) {
    if (supportedAbis == null || supportedAbis.isEmpty) return true;
    for (final abi in supportedAbis) {
      if (!_is64BitAbi(abi)) continue;
      return abi == requiredAbi;
    }
    return false;
  }

  /// Whether [abi] names a 64-bit architecture.
  static bool _is64BitAbi(String abi) =>
      abi == 'arm64-v8a' || abi == 'x86_64' || abi == 'riscv64';

  /// Reads the device's supported ABIs over the native channel.
  static Future<bool> _detect() async {
    // The ABI key is an ANDROID fact — the channel handler lives in
    // MainActivity.kt. A non-Android host cannot be asked and fails open.
    if (!Platform.isAndroid) return true;
    try {
      final abis = await _channel.invokeListMethod<String>('supportedAbis');
      return hasRequiredAbi(abis);
    } on MissingPluginException {
      // No native handler (unit tests, a host platform): keep the current
      // behaviour instead of blocking the offline AI.
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DeviceCapabilities] ABI detection failed: $e');
      }
      return true;
    }
  }

  // ── Total memory (cycle-42 P2; ABI-qualified at C46) ────────────────────
  //
  // The RAM key of the offline-model selection, read over the SAME channel
  // as the ABI probe (`ActivityManager.MemoryInfo.totalMem`,
  // MainActivity.kt) — no new package, no new permission (contract §3).

  /// The cached memory verdict — a resolved VALUE, never a Future.
  ///
  /// Same reason as the ABI verdict above: a cached Future created inside a
  /// finished fake-async zone never resumes for a later `testWidgets` case.
  /// The total memory cannot change while the process runs, so the value is
  /// cached and every caller gets a fresh future of its own.
  static int? _cachedTotalMemoryBytes;

  /// Whether the memory read already ran. A null [_cachedTotalMemoryBytes]
  /// means "the device could not be asked", which is a verdict of its own —
  /// so the flag, not the value, marks the read as done.
  static bool _totalMemoryDetected = false;

  /// Test seam: replaces the native memory detection entirely.
  ///
  /// A test sets it to simulate a device above or below the RAM floor;
  /// production never sets it.
  @visibleForTesting
  static Future<int?> Function()? totalMemoryOverrideForTest;

  /// The device's total physical memory in bytes, or null when it cannot be
  /// read (a missing native handler, a non-Android host, a failed read)
  /// OR when the device has no arm64-v8a support.
  ///
  /// C46 (contract `offline-model-minicpm5` §3): RAM alone no longer selects
  /// a model. A no-arm64 device is the message-only class whatever its
  /// memory, so its memory figure is not an eligibility fact and is
  /// deliberately not reported here — this is what keeps the spec table's
  /// below-floor flag (a RAM state, not an ABI state) false on an
  /// ABI-refused device. Null still means "not an applicable or readable RAM
  /// fact", never "zero memory".
  static Future<int?> totalMemoryBytes() async {
    if (!await isOfflineAiSupported()) return null;
    final override = totalMemoryOverrideForTest;
    if (override != null) return override();
    if (_totalMemoryDetected) {
      return _cachedTotalMemoryBytes;
    }
    return _detectTotalMemoryAndCache();
  }

  /// Runs the memory read once and remembers its verdict.
  static Future<int?> _detectTotalMemoryAndCache() async {
    final total = await _detectTotalMemory();
    _cachedTotalMemoryBytes = total;
    _totalMemoryDetected = true;
    return total;
  }

  /// Whether an ABI-eligible device clears the RAM floor of the offline
  /// model (the RAM key of the C46 table).
  ///
  /// A no-arm64 device reads as `false` here even with ample RAM: its
  /// [totalMemoryBytes] is not an eligibility fact. An UNREADABLE memory
  /// size also does NOT clear the floor: a device whose RAM cannot be
  /// verified is not offered the asset — the honest state for it is the
  /// message-only class (the fail-closed rule, contract §3
  /// `message_only_class`).
  static Future<bool> hasMemoryCapacity() async {
    return clearsMemoryFloor(await totalMemoryBytes());
  }

  /// The pure RAM verdict: does [totalMemoryBytes] clear the floor?
  ///
  /// Null (unknown) never clears it.
  @visibleForTesting
  static bool clearsMemoryFloor(int? totalMemoryBytes) {
    if (totalMemoryBytes == null) return false;
    return totalMemoryBytes >= minimumTotalMemoryBytes;
  }

  /// Reads the device's total memory over the native channel.
  static Future<int?> _detectTotalMemory() async {
    // The memory figure is an ANDROID fact — the channel handler lives in
    // MainActivity.kt. A host that cannot report RAM reads as unreadable,
    // which never clears the floor: such a device keeps the message-only
    // honesty (the fail-closed rule, contract §3 `message_only_class`).
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<int>('totalMem');
    } on MissingPluginException {
      // No native handler (unit tests, a host platform).
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DeviceCapabilities] memory detection failed: $e');
      }
      return null;
    }
  }

  // ── The under-floor override ack (cycle-43; ABI-qualified at C46) ───────
  //
  // The ONE user-consent input of the selection table (contract
  // `offline-model-minicpm5` §3 `under_floor_override_class`): a persisted
  // PREFERENCE — NOT a migration marker (no DAO / model_asset-marker
  // implications) — recorded when the user taps "Download anyway" after the
  // honest risk copy. NEVER auto-cleared: the warning served its purpose
  // once, and the failure-class layer is the honest backstop afterwards.
  // Read through `SharedPreferencesAsync` (the modern-API precedent —
  // online_ai_service.dart, update_cubit.dart, the cycle-29 P1 precedent).

  /// The persisted key of the under-floor override ack (cycle-43, contract
  /// §3 `under_floor_override`).
  static const String ramOverrideAckPrefsKey = 'offline_ram_override_ack';

  /// The cached override-ack verdict — a resolved VALUE, never a Future.
  ///
  /// Same reason as the verdicts above: a cached Future created inside a
  /// finished fake-async zone never resumes for a later `testWidgets`
  /// case. The ack is read once per process and cached; the one runtime
  /// change ([acknowledgeRamOverride]) updates the cache itself. A FAILED
  /// read is cached too — a device whose preferences cannot be asked has
  /// the honest verdict "not recorded" (the S1 default: warning-first).
  static bool _cachedOverrideAck = false;

  /// Whether the ack read already ran. A failed read is a verdict of its
  /// own ("not recorded"), so the flag — not the value — marks it done.
  static bool _ackRead = false;

  /// Test seam: replaces the persisted ack read entirely.
  ///
  /// A test sets it to simulate a device with or without the recorded
  /// override; production never sets it.
  @visibleForTesting
  static Future<bool> Function()? ramOverrideAckOverrideForTest;

  /// Test seam: forgets the cached ack read so the next
  /// [hasRamOverrideAck] re-reads the persisted value (or re-hits the
  /// platform). Production never calls it — the cache is the process
  /// verdict; only the ack write may change it.
  @visibleForTesting
  static void resetRamOverrideAckForTest() {
    _cachedOverrideAck = false;
    _ackRead = false;
  }

  /// Whether the C43 under-floor override APPLIES to this device: the
  /// device is ABI-eligible AND the user has recorded the "Download anyway"
  /// ack (contract `offline-model-minicpm5` §3
  /// `under_floor_override_class`).
  ///
  /// A no-arm64 device never gets the override — state 3 has NO CTA
  /// (contract §3 `message_only_class`) — so a stored ack is deliberately
  /// ignored there. Defaults to `false` on an eligible device without the
  /// ack: the warning-first default (cycle-43 §6 S1). An unreadable
  /// preferences store also reads as NOT recorded (the fail-closed rule);
  /// the read failure never blocks the feature.
  static Future<bool> hasRamOverrideAck() async {
    if (!await isOfflineAiSupported()) return false;
    final override = ramOverrideAckOverrideForTest;
    if (override != null) return override();
    if (_ackRead) return _cachedOverrideAck;
    return _readAckAndCache();
  }

  /// Runs the ack read once and remembers its verdict.
  static Future<bool> _readAckAndCache() async {
    final ack = await _readAckFromPrefs();
    _cachedOverrideAck = ack;
    _ackRead = true;
    return ack;
  }

  /// The persisted ack, or `false` when it cannot be read.
  static Future<bool> _readAckFromPrefs() async {
    try {
      // SharedPreferencesAsync (the new API, not the legacy singleton).
      // Its constructor throws StateError when the platform is unset
      // (unit tests) — the same defensive guard the update_cubit
      // SharedPreferences reads run under.
      final prefs = SharedPreferencesAsync();
      return await prefs.getBool(ramOverrideAckPrefsKey) ?? false;
    } catch (e) {
      // Defensive: unreadable prefs must never block the feature — and
      // must never grant the override either (the S1 default).
      if (kDebugMode) {
        debugPrint('[DeviceCapabilities] override ack read failed: $e');
      }
      return false;
    }
  }

  /// Records the override ack — the "Download anyway" tap (cycle-43).
  ///
  /// The in-memory verdict is applied FIRST (the tap is the consent; the
  /// session proceeds immediately), then persisted best-effort: a persist
  /// failure still applies the choice for this session, and the next
  /// launch re-reads the honest default (the online_ai_service precedent).
  /// The ack is NEVER auto-cleared by any code path — the warning served
  /// its purpose, and the failure-class layer is the honest backstop
  /// (contract `offline-model-minicpm5` §3 under_floor_override_class).
  /// It only ever APPLIES on an ABI-eligible device ([hasRamOverrideAck]);
  /// recording it on a no-arm64 device is inert.
  static Future<void> acknowledgeRamOverride() async {
    _cachedOverrideAck = true;
    _ackRead = true;
    try {
      await SharedPreferencesAsync().setBool(ramOverrideAckPrefsKey, true);
    } catch (e) {
      // Persist failure — the choice still applies for this session.
      if (kDebugMode) {
        debugPrint('[DeviceCapabilities] override ack persist failed: $e');
      }
    }
  }
}
