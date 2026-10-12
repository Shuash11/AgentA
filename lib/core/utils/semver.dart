/// Strict semantic version — `MAJOR.MINOR.PATCH`, digits only (semver core).
///
/// Used by the update-check engine (`lib/services/update/`) to compare the
/// running app version against the latest GitHub release tag. Build numbers
/// (`+N`) are deliberately NOT represented here: by convention every
/// user-facing release bumps semver, so build metadata never participates
/// in comparisons.
class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;

  const SemVer(this.major, this.minor, this.patch);

  static final RegExp _strictPattern = RegExp(r'^\d+\.\d+\.\d+$');

  /// Strict parser: accepts only `^\d+\.\d+\.\d+$`.
  ///
  /// Returns null for anything else — `latest`, prereleases (`1.2.0-rc1`),
  /// build metadata (`1.2.0+2`), extra components (`1.2.3.4`), empty, junk.
  /// Use [tryParseTag] for release tag names that may carry a leading `v`.
  static SemVer? tryParse(String raw) {
    final s = raw.trim();
    if (!_strictPattern.hasMatch(s)) return null;
    final parts = s.split('.');
    return SemVer(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// Parses a release tag name, stripping an optional leading `v`/`V`
  /// (`v1.2.0` → `1.2.0`) before strict parsing.
  ///
  /// Returns null for non-semver tags (`latest`, `v1.2`, `release-1`, empty).
  static SemVer? tryParseTag(String raw) {
    var s = raw.trim();
    if (s.length > 1 && (s.startsWith('v') || s.startsWith('V'))) {
      s = s.substring(1);
    }
    return tryParse(s);
  }

  /// Compares major → minor → patch.
  /// Returns negative / zero / positive like [Comparable.compareTo].
  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is SemVer &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
