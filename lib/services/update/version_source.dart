/// Source of remote version information for the update-check engine —
/// GitHub Releases in production; fakes in unit tests.
///
/// Contract: `contracts/update-engine.yaml` (cycle-27, §2). Every fetch is
/// classified as a [ReleaseFetchResult] — the source NEVER throws, and a
/// failure is never read as "up to date".
abstract class VersionSource {
  /// Fetches the latest release, always classified (see the contract).
  Future<ReleaseFetchResult> fetchLatestRelease();

  /// Rate-limit backoff deadline — null when not rate-limited (or when the
  /// source does not rate-limit). While this is in the future, no request may
  /// be retried: sources refuse to issue one, and [VersionCheckService]
  /// short-circuits before even calling the source.
  DateTime? get backoffUntil => null;
}

/// Classified outcome of [VersionSource.fetchLatestRelease]
/// (contract §2, `release_fetch_result`).
sealed class ReleaseFetchResult {
  const ReleaseFetchResult();
}

/// 200 with usable content — the release as reported by the source.
final class ReleaseFetched extends ReleaseFetchResult {
  final RemoteRelease release;

  const ReleaseFetched(this.release);
}

/// 404 — no release info. Covers both "no releases published yet" and an
/// endpoint that is not anonymously reachable (private repository). Never
/// reads as "up to date"; user-initiated checks surface it as `noRelease`.
final class ReleaseNotFound extends ReleaseFetchResult {
  const ReleaseNotFound();
}

/// 403/429 — rate limited until [retryAt]. Also returned while the source is
/// still inside a previously applied backoff window.
final class ReleaseRateLimited extends ReleaseFetchResult {
  final DateTime retryAt;

  const ReleaseRateLimited(this.retryAt);
}

/// Transport-level failure (DNS, connect, TLS) — the network is unreachable
/// for this request.
final class ReleaseOffline extends ReleaseFetchResult {
  const ReleaseOffline();
}

/// The request deadline (8s) elapsed.
final class ReleaseTimedOut extends ReleaseFetchResult {
  const ReleaseTimedOut();
}

/// Anything else: an HTTP status outside the contract, or a 200 whose content
/// was unusable. [statusCode] is the received status (200 for content
/// rejections, null when no response was received at all).
final class ReleaseUnexpected extends ReleaseFetchResult {
  final int? statusCode;

  const ReleaseUnexpected({this.statusCode});
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
