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
/// Cycle-42 P2b (plan §4.9) makes the RAM verdict the ONE selection key:
/// the table in `offline_model_spec.dart` offers the Qwen `.task` asset to
/// EVERY device with at least 4 GB of total memory, whatever its ABI — the
/// MediaPipe `.task` engine is the multi-ABI engine (cycle-40 §1.1), so the
/// ABI verdict decides nothing about WHICH model a device is offered. The
/// ABI machinery STAYS here as the backstop of the load-time `unsupportedAbi`
/// failure class (cycle-40): rarely reachable now, zero risk to keep.
///
/// Cycle-43 (contract `offline-model-qwen15b` §3 `under_floor_override`)
/// adds the ONE user-consent input: the persisted "Download anyway" ack.
/// A device below the RAM floor first sees the honest risk copy (warning-
/// first, cycle-43 §6 S1); an explicit tap records the ack — a user
/// PREFERENCE, never auto-cleared, never a migration marker — and admits
/// the SAME Qwen spec (below-floor + ack ⇒ eligible, the ruled verdict
/// `totalMem >= floor OR ack`). The failure path is untouched: an OOM/kill
/// on an overridden device classifies exactly as before.
class DeviceCapabilities {
  const DeviceCapabilities._();

  /// The honest message every offline surface shows when the device cannot
  /// run the offline model.
  ///
  /// It states the RAM requirement — the ONE requirement left — and nothing
  /// else: there is no action the user can take, so no action is offered.
  /// The wording carries NO ABI mention (plan §4.9): the ABI decides
  /// nothing about the selection any more.
  static const String incompatibleDeviceMessage =
      'The offline AI requires a device with at least 4 GB of RAM';

  /// The ABI the pinned engine requires on Android.
  static const String requiredAbi = 'arm64-v8a';

  /// The RAM floor of the offline model (cycle-42, contract
  /// `offline-model-qwen15b` §3).
  ///
  /// The asset's vendor-measured peak RSS is ≈ 2.2 GB (CPU, q8 ekv4096 —
  /// contract §5), so a device with less than 4 GB of TOTAL memory cannot
  /// hold the runtime with margin. AMENDED at cycle-43 (the S8 amendment):
  /// a device below the floor is never offered the asset BY DEFAULT — it
  /// first sees the honest risk copy ([underFloorRiskCopy]) + the
  /// "Download anyway" button, and an explicit user override AFTER that
  /// warning admits the SAME asset ([hasRamOverrideAck], the informed-
  /// consent discipline, cycle-43 §6 S1).
  static const int minimumTotalMemoryBytes = 4 * 1024 * 1024 * 1024;

  /// The native channel that answers with `Build.SUPPORTED_ABIS` and
  /// `ActivityManager.MemoryInfo.totalMem`.
  static const MethodChannel _channel = MethodChannel(
    'com.agenta.agenta/device',
  );

  // ── The under-floor override copy (cycle-43) ─────────────────────────────
  //
  // The UX copy of the override state, consumed VERBATIM from contract
  // `offline-model-qwen15b` §6 (under_floor_first_use / under_floor_post_ack)
  // — these exact strings, no re-wording (the E2B contract §5 discipline).
  // The strings live beside [incompatibleDeviceMessage]: they are copy of
  // the capability state, not of any one surface.

  /// The first-use risk copy of an under-floor device (contract §6
  /// `under_floor_first_use` — VERBATIM). It renders FIRST on every
  /// message-only surface, ahead of any download affordance (warning-first,
  /// cycle-43 §6 S1). The "3.6 GB" figure is the ruled reference device's
  /// MemTotal (OPPO CPH2591 ≈ 3.64 GB, cycle-43 plan §1.1); a verified fact
  /// REFINES the figure, never the string shape (plan §10 search 1).
  static const String underFloorRiskCopy =
      'This phone has 3.6 GB RAM. The model may be closed by the system '
      'when memory runs low.';

  /// The override button's label (contract §6 `under_floor_first_use` —
  /// VERBATIM). The label names the consequence, not a yes/no (the
  /// confirmation-dialog discipline: the option summarises what happens).
  static const String downloadAnywayButtonLabel = 'Download anyway';

  /// The retained risk line shown after the recorded ack, whenever the
  /// download is enabled on an under-floor device (contract §6
  /// `under_floor_post_ack` — VERBATIM). Never re-nagged (the full risk
  /// copy and the button do not repeat), never silently green (the line
  /// always accompanies the enabled download).
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

  /// Whether the device's ABI would let the LiteRT-LM engine load a model.
  ///
  /// NOT a selection input any more (plan §4.9): the table in
  /// `offline_model_spec.dart` offers the MediaPipe `.task` asset to every
  /// device that clears the RAM floor, whatever the ABI. The verdict stays
  /// as the recorded ABI fact and as the backstop of the load-time
  /// `unsupportedAbi` failure class (cycle-40).
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

  /// The pure ABI verdict.
  ///
  /// The app process runs the device's FIRST 64-bit ABI — Android prefers
  /// the 64-bit variant of an app whenever the device supports it — so the
  /// model can only run when that ABI is `arm64-v8a`. A device that reports
  /// no 64-bit ABI at all is a 32-bit device and can never run the model.
  ///
  /// The FIRST 64-bit entry matters: an x86_64 emulator lists `arm64-v8a`
  /// in its supported ABIs (ARM translation) while the app itself runs
  /// x86_64, where the LiteRT-LM stack does not exist. An empty list means
  /// "unknown" and is treated as compatible (fail open).
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
    // The engine's ABI guard is Android-specific: the FFI path also serves
    // arm64 iOS/macOS/Linux, so only Android is checked here.
    if (!Platform.isAndroid) return true;
    try {
      final abis = await _channel.invokeListMethod<String>('supportedAbis');
      return isCompatibleAbi(abis);
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

  // ── Total memory (cycle-42 P2) ──────────────────────────────────────────
  //
  // The ONE key of the offline-model selection: the RAM floor of the Qwen
  // `.task` asset. It extends the SAME channel as the ABI probe
  // (`ActivityManager.MemoryInfo.totalMem`, MainActivity.kt) — no new
  // package, no new permission (contract §3, plan §6 S3).

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
  /// read (a missing native handler, a non-Android host, a failed read).
  static Future<int?> totalMemoryBytes() {
    final override = totalMemoryOverrideForTest;
    if (override != null) return override();
    if (_totalMemoryDetected) {
      return Future<int?>.value(_cachedTotalMemoryBytes);
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

  /// Whether the device clears the RAM floor of the offline model.
  ///
  /// An UNREADABLE memory size does NOT clear the floor: a device whose RAM
  /// cannot be verified is not offered the asset — the honest state for it
  /// is the message-only class (the fail-closed rule, plan §6 S8).
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
    // honesty (the fail-closed rule, plan §6 S8).
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

  // ── The under-floor override ack (cycle-43) ──────────────────────────────
  //
  // The ONE user-consent input of the selection table (contract §3
  // under_floor_override): a persisted PREFERENCE — NOT a migration marker
  // (no DAO / model_asset-marker implications) — recorded when the user
  // taps "Download anyway" after the honest risk copy. NEVER auto-cleared:
  // the warning served its purpose once, and the failure-class layer is
  // the honest backstop afterwards. Read through `SharedPreferencesAsync`
  // (the modern-API precedent — online_ai_service.dart, update_cubit.dart,
  // the cycle-29 P1 precedent).

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

  /// Whether the user has recorded the "Download anyway" override ack
  /// (cycle-43, contract §3 `under_floor_override`).
  ///
  /// Defaults to `false` — the warning-first default (cycle-43 §6 S1): a
  /// device without the recorded ack keeps the message-only state, and no
  /// download may start without it. An unreadable preferences store also
  /// reads as NOT recorded (the fail-closed rule); the read failure never
  /// blocks the feature.
  static Future<bool> hasRamOverrideAck() {
    final override = ramOverrideAckOverrideForTest;
    if (override != null) return override();
    if (_ackRead) return Future<bool>.value(_cachedOverrideAck);
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
  /// (contract §3 under_floor_override, plan §4.1).
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
