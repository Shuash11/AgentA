/// Source of remote version information for the update-check engine —
/// GitHub Releases in production; fakes in unit tests.
abstract class VersionSource {
  /// Fetches the latest release.
  ///
  /// Returns null when no release info is available (no releases published
  /// yet, rate-limited, or network failure). Null must NEVER be treated as
  /// "up to date" — callers decide only on non-null results.
  Future<RemoteRelease?> fetchLatestRelease();
}

/// A release as reported by a [VersionSource] (Adviser contract).
class RemoteRelease {
  /// Strict semver, e.g. "1.1.0" — from `tag_name`, 'v'-stripped,
  /// strict-semver-validated by the source.
  final String version;

  /// e.g. "1.0.0" — from the body marker line `min-version: x.y.z`;
  /// null = no forced update.
  final String? minVersion;

  /// First `*.apk` asset's browser_download_url; falls back to [releaseUrl].
  final String? downloadUrl;

  /// `html_url` — the release page.
  final String? releaseUrl;

  /// Release body (trimmed).
  final String? notes;

  final DateTime? publishedAt;

  const RemoteRelease({
    required this.version,
    this.minVersion,
    this.downloadUrl,
    this.releaseUrl,
    this.notes,
    this.publishedAt,
  });

  @override
  String toString() => 'RemoteRelease(v$version, min: $minVersion)';
}
