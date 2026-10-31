import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The device capability that decides whether the on-device model can run.
///
/// ONE source of truth for the whole offline surface (the app gate, the
/// download screen, the chat card and the model picker): the pinned
/// LiteRT-LM engine ships its native stack for `android_arm64` only, so on
/// every other ABI the model can NEVER load — the plugin throws a
/// deterministic `UnsupportedError` (flutter_edge_ai_litertlm 1.8.6,
/// `litert_lm_client.dart:606-611`). Offering the 2.59 GB download there
/// wastes the transfer and ends in a retry loop that can never succeed
/// (cycle-40 P1).
///
/// Detection reads `android.os.Build.SUPPORTED_ABIS` over a MethodChannel
/// (the cycle-28 native-channel precedent, `MainActivity.kt`). No package
/// dependency was added: the pubspec carries no ABI-reporting dependency
/// (`device_info_plus` is absent), and the plan pre-authorizes the native
/// channel as the fallback.
class DeviceCapabilities {
  const DeviceCapabilities._();

  /// The honest message every offline surface shows on an incompatible
  /// device. It states the requirement and nothing else: there is no action
  /// the user can take, so no action is offered.
  static const String incompatibleDeviceMessage =
      'The offline AI requires a 64-bit ARM (arm64-v8a) device';

  /// The ABI the pinned engine requires on Android.
  static const String requiredAbi = 'arm64-v8a';

  /// The native channel that answers with `Build.SUPPORTED_ABIS`.
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

  /// Whether the offline model can run on this device.
  ///
  /// Resolves to `true` when the device cannot be asked (non-Android
  /// platforms, a missing native handler): the gate is an honesty
  /// improvement, not a security control, so an unknown device keeps the
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
}
