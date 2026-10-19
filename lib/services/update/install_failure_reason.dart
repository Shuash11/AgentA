/// Why an install-flow attempt failed — the contract's shared enum
/// (`contracts/update-engine.yaml` §4, `failure_reasons`). Used by the
/// download service, the install service, and the UI-visible state machine.
enum InstallFailureReason {
  download,
  network,
  timeout,
  storage,
  sizeMismatch,
  checksumMismatch,
  permissionDenied,
  userCancelled,
  signatureMismatch,
  invalidPackage,
  unknown;

  /// Maps the native Android channel's reason string (Kotlin `reasonFor`,
  /// contract §4 `reason_mapping`) onto the enum; unrecognised → [unknown].
  static InstallFailureReason fromChannelName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return unknown;
  }
}
