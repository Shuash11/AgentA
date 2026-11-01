import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  /// hold the runtime with margin. A device below the floor is never
  /// offered the asset: it keeps the honest message-only state (the
  /// RAM-floor honesty discipline, plan §6 S8).
  static const int minimumTotalMemoryBytes = 4 * 1024 * 1024 * 1024;

  /// The native channel that answers with `Build.SUPPORTED_ABIS` and
  /// `ActivityManager.MemoryInfo.totalMem`.
  static const MethodChannel _channel = MethodChannel(
    'com.agenta.agenta/device',
  );

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
}
