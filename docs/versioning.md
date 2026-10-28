# Versioning & Release Convention (AgentA)

The repeatable convention for cutting releases and how the app's built-in
update-check feature ("new version has arrived") detects and surfaces them.
Everything below reflects the shipped code; file paths, keys, and workflow step
names are exact.

---

## 1. Versioning scheme

**SemVer `major.minor.patch` + a pubspec build number.**

- `pubspec.yaml` carries `version: x.y.z+b` (e.g. `version: 1.1.0+2`).
- Every **user-facing release bumps the SemVer** (`x.y.z`). By convention the
  build number `+b` is **metadata only — never compared** (the update engine
  records it but ignores it in the decision rule).
- Releases are tagged `vX.Y.Z` (e.g. `v1.1.0`) and pushed explicitly; the
  convention is an annotated tag (`git tag -a`), and the CI tag guard
  accepts annotated and lightweight tags alike. The tag must equal the
  pubspec SemVer — enforced by CI (see the release checklist).
- Parsing is strict: `lib/core/utils/semver.dart` → `SemVer.tryParse` accepts
  only `^\d+\.\d+\.\d+$` (rejects `latest`, prereleases like `1.2.0-rc1`,
  build metadata, junk); `SemVer.tryParseTag` strips a leading `v`/`V` from tag
  names. `compareTo` orders major → minor → patch.

### When to bump what

| Change | Bump | Example |
|---|---|---|
| Breaking change / incompatible data or storage migration | **major** | `1.2.0 → 2.0.0` |
| New user-facing feature (e.g. the update dialog itself) | **minor** | `1.1.0 → 1.2.0` |
| Bug fix / small improvement, no new features | **patch** | `1.1.0 → 1.1.1` |
| Rebuild of the same SemVer (never re-tag an already-released version — bump instead, see edge cases) | build number only | `1.1.0+2 → 1.1.0+3` |

> Rule of thumb: **every tag you ever push bumps `x.y.z`**. Re-using a SemVer
> for a second tag is forbidden, and CI now catches the duplicate-**release**
> path: the tag guard's duplicate-semver check fails a fresh run when a
> published release already exists for that version (or when the tag no longer
> points at the run's commit). Legitimate re-runs of the publishing run still
> pass. Residual process rule: a force-pushed tag for a version that was
> **never released** has no release record to compare against.

---

## 2. Release process (step-by-step checklist)

Releases are cut from `main`. The GitHub **"Build APK"** workflow
(`.github/workflows/build-apk.yml`) builds, guards, and publishes on every
`v*` tag push.

1. **Bump the version** in `pubspec.yaml` → `version: 1.2.0+1` (SemVer bump;
   build number can restart per release).
2. **Commit** on `main` (no secrets in the commit; keep `.env` out — CI
   asserts no `.env` asset and that it is not bundled).
3. **Create the annotated tag**: `git tag -a v1.2.0 -m "Release 1.2.0"`.
4. **Push the tag**: `git push origin v1.2.0`.
5. **CI guard validates tag == pubspec**: the workflow step **"Assert v\* tag
   matches pubspec version"** extracts the tag (`v1.2.0` → `1.2.0`), asserts
   strict semver, and fails the build (`::error::` + non-zero exit) if it does
   not equal the `version:` in `pubspec.yaml` (build number not compared).
6. **Build APK publishes the release**: the same workflow runs the existing
   guards (C1/C4/H9/H11/M15/M21), builds the release APK with dart-define
   secrets, and the **`softprops/action-gh-release@v2`** step publishes a
   GitHub release on the tag with the APK asset and
   `generate_release_notes: true`.
7. **(Forced releases only) Add the `min-version:` marker to the published
   release body**: the workflow auto-generates the release notes
   (`generate_release_notes: true`) and does NOT add the marker — edit the
   release body on GitHub (Releases → the new release → edit) and add the line
   `min-version: x.y.z` (see §3). This must happen **after** the release
   publishes; it cannot be injected via the automated notes.
8. **In-app dialog auto-detects**: installed apps pick the release up on their
   next scheduled check (see §3) and show the update dialog — including fresh
   installs of an older APK (pre-login, over the login screen).

Existing tags: `v1.0.0`, `v1.1.0`, `v1.2.0`, `v1.2.1`, `v1.2.2`, `v1.2.3`, `v1.2.4`, `v1.2.5`, `v1.3.1`, `v1.4.0`, `v1.4.1`, `v1.5.0`, `v1.5.1`. Current version: `1.7.0+1`.

---

## 3. Forced updates (`min-version` marker)

A forced (non-dismissible) update is declared **at release time** by adding one
marker line to the release notes body:

```
min-version: 1.0.0
```

- `min-version: x.y.z` = the oldest version still allowed to run the app.
- Decision rule (in `lib/services/update/version_check_service.dart`):
  - `minVersion != null && current < minVersion` → **forced** (non-dismissible,
    Update-only, stays open until the new version is installed);
  - else `latest > current` → **available** (soft, dismissible);
  - else none.
- A malformed marker (e.g. `min-version: banana`) is treated as **no forced
  update** and only debug-logged — the engine never forces on junk.
- So: when cutting a forced release, bump the SemVer, tag it, then — **after
  the workflow publishes the release — edit the published release body on
  GitHub to add the `min-version: x.y.z` marker line**. The workflow
  auto-generates the notes (`generate_release_notes: true`, see the release
  checklist) and does not add the marker automatically, so this manual
  post-publish edit is required. Everyone below the threshold gets the
  non-dismissible dialog on their next check (apps that already ran a check
  before the edit pick it up on the next scheduled check).

---

## 4. How the in-app update check works

Engine (`lib/services/update/`, no UI) + dialog (UI, `lib/presentation/shared/`).

### Checks and scheduling — `version_check_service.dart`

- `VersionCheckService.instance.init()` is called **post-first-frame** from
  `main.dart` (`_startMainApp` → `addPostFrameCallback`), never before
  `runApp` — `PackageInfo.fromPlatform` before the first frame is a known
  plus_plugins issue (#309). Fire-and-forget; never blocks boot.
- **Scheduling (all throttled through one gate — min 5 min between network
  calls):** startup check; re-check on `AppLifecycleState.resumed`; a periodic
  timer every 30 min while foregrounded; a connectivity-restored hook (via
  `ConnectivityService.instance`).
- **Debug builds skip checks entirely** (`kReleaseMode` gate) — no dev noise;
  unit tests inject a fake `VersionSource` instead.
- The last successful response is cached in memory with a timestamp, but the
  cache **never** drives emitted results or UI — dialogs only ever surface
  from a fresh network check.
- Rate-limited (403/429) → the source parses `retry-after` /
  `x-ratelimit-reset` into a `backoffUntil` deadline; **no request is retried
  until it passes**.

### State machine — `lib/cubit/update/update_cubit.dart`

- `UpdateCubit` subscribes to the service's `resultStream` and maps levels to
  `UpdateStatus { idle, checking, available, forced }`.
- Soft update is shown **once per version**: the dismissal is persisted under
  the `update_dismissed_version` key via the NEW `SharedPreferencesAsync` API
  (not the legacy singleton). A **newer** release automatically re-triggers
  the dialog.

### Dialog — `update_available_dialog.dart` + `update_dialog_host.dart`

- The host is mounted via `MaterialApp builder:` (with the root navigator key
  `UpdateDialogHost.navigatorKey`), so the dialog overlays **any** screen —
  login, model-download gate, shell — including pre-login.
- **Update** opens the APK asset URL externally (`launchUrl`); **Later**
  dismisses once per version; **forced** is non-dismissible (Update-only).
- A fresh install of an older APK shows the dialog on the startup check, even
  before login. Offline never blocks: a failed check emits nothing and the
  app keeps its previous state.

---

## 5. Version-source contract

`lib/services/update/version_source.dart` defines the seam:

```dart
abstract class VersionSource {
  Future<RemoteRelease?> fetchLatestRelease();
}

class RemoteRelease {
  final String version;      // "1.1.0" — from tag_name, 'v'-stripped, strict semver
  final String? minVersion;  // "1.0.0" — from the body marker "min-version: x.y.z"; null = no forced update
  final String? downloadUrl; // first *.apk asset's browser_download_url; fallback html_url
  final String? releaseUrl;  // html_url (release page)
  final String? notes;       // release body (trimmed)
  final DateTime? publishedAt;
}
```

- Production source: `github_releases_source.dart` against
  `GET https://api.github.com/repos/Shuash11/AgentA/releases/latest`
  (const `AppConfig.githubLatestReleaseUrl` — public URL, not a secret).
- **Rate limit:** unauthenticated GitHub is 60 req/hour/IP — hence the
  aggressive client-side throttling (min 5 min) + in-memory cache; 403/429
  expose a `backoffUntil` deadline and are never retried until it passes.
- 200 parses a JSON subset with defensive re-checks (`draft == false`,
  `prerelease == false`, strict-semver `tag_name`); 404 → null (no releases
  yet); network errors → silent failure (debug log only). Null is never
  treated as "up to date".
- **Future fallback (not yet implemented):** a Supabase `app_releases` table
  could back a second `VersionSource` implementation behind the same
  interface — no code exists for it today (no migration in
  `supabase/migrations/`).

---

## 6. Edge cases

| Situation | Behavior |
|---|---|
| **Offline / network failure** | Silent failure (debug log only); nothing emitted; the app keeps its previous state. Never blocks boot or the UI. |
| **Rate-limited (403/429)** | `backoffUntil` from `retry-after` / `x-ratelimit-reset` (fallback: 1-hour window if headers are missing). No request retried until it passes — at source and service level. |
| **404 (no releases yet)** | `fetchLatestRelease` → null → nothing emitted; not an error, no backoff. |
| **Non-semver tag (e.g. `latest`, `v1.2`, prerelease)** | Engine: `SemVer.tryParseTag` → null → release ignored. CI: the tag guard fails the build with `::error::`. |
| **Rebuild the same SemVer (re-tag `v1.1.0` on a new commit, pubspec unchanged)** | **Caught by CI — duplicate-release path**: when a published release already exists for that version, the tag guard fails a fresh run (attempt 1 — i.e. the tag ref was re-pushed/re-created, or the workflow was dispatched on the tag) with `::error::` + non-zero exit before the release step; it also fails if the tag no longer points at the run's commit. Re-runs of the publishing run (attempt ≥ 2) pass — the duplicate-release path no longer publishes silently. Residual process rule: a force-pushed tag for a version that was **never released** has no release record to compare against. |
| **Tag without matching pubspec version** | CI guard fails with `::error::` + non-zero exit before any build. |
| **Fresh install of an older APK** | Startup check fires post-first-frame → dialog shows pre-login (over login screen), soft or forced per the marker. |
| **Debug builds (`kDebugMode`)** | All checks skipped (`kReleaseMode` gate) — no network calls, no dialogs, no dev noise. Tests exercise the engine with a fake `VersionSource`. |
| **User dismissed a version, newer release arrives** | `update_dismissed_version` only suppresses the exact dismissed version; a newer release re-triggers the dialog automatically. |
| **Launch failure (browser/open error)** | Snackbar fallback with the URL; the dialog stays open (always when forced). |
| **`PackageInfo.fromPlatform` failure** | Current version unknown → checks skip (no emit); never crashes. |

---

## 7. Quick reference

| What | Where |
|---|---|
| Strict semver comparator | `lib/core/utils/semver.dart` |
| Version-source interface + model | `lib/services/update/version_source.dart` |
| GitHub Releases source | `lib/services/update/github_releases_source.dart` |
| Check scheduling + decision | `lib/services/update/version_check_service.dart` |
| Update state machine | `lib/cubit/update/update_cubit.dart` |
| Dialog + host | `lib/presentation/shared/update_available_dialog.dart`, `update_dialog_host.dart` |
| Release endpoint const | `lib/core/config/app_config.dart` → `githubLatestReleaseUrl` |
| CI tag guard | `.github/workflows/build-apk.yml` → step **"Assert v\* tag matches pubspec version"** |
| Release publish step | `.github/workflows/build-apk.yml` → `softprops/action-gh-release@v2` |
| Dismissal persistence key | `update_dismissed_version` (`SharedPreferencesAsync`) |
| Tests | `test/semver_test.dart`, `test/github_releases_source_test.dart`, `test/version_check_service_test.dart`, `test/update_feature_test.dart` |
