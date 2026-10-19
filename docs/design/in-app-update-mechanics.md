# AgentA in-app update — Android install mechanics (design of record)

**status:** research complete (cycle-28 P1b) — feeds P4 (the download/install service + the contract amendment) and P7 (the security review)
**owner:** middle-end
**mandate:** `plans/cycle-28-in-app-update-flow.md` (ruling 4 + P1b). This document replaces the browser hand-off as the approach of record: today the update dialog and the Profile row open `downloadUrl`/`releaseUrl` in a browser; the target flow downloads and installs the APK inside the app with **no data loss**.
**scope:** mechanics only — no code in this phase. Everything below is cited; internal facts are cited to file:line.

---

## 0. Web-research declaration (per `.opencode/skills/web-research/SKILL.md`)

- `search: done - Android unknown-sources install permission model (API 26+); PackageInstaller session install API and status codes; same-certificate update semantics; app-specific storage; file:// URI ban (N+); Android 14 update ownership; pub.dev installer-plugin landscape; GitHub release-asset integrity fields`
- **Tooling note (recorded per the skill):** the `webfetch` tool failed in this environment (transport errors on every URL); all sources were fetched with `curl` instead — HTTP 200 each, 2026-10-18 — and the quotes below are taken from the saved pages.
- `unverified`: (1) the API-36-era *developer-verification* policy that the `PackageInstaller` constants anticipate [S6] — the constants exist, the policy's future applicability to this app is unconfirmed; (2) plugin behavior beyond published metadata (no source audit in P1b).

## 1. App facts (internal — from this codebase)

- Package `com.agenta.AgentA`, **minSdk 26** (`android/app/build.gradle:31-32`) — every API below exists unconditionally (all are ≤ API 26 unless noted). targetSdk = the Flutter pin (35 per the manifest comments).
- Manifest today has **no** `REQUEST_INSTALL_PACKAGES` and no storage permissions (`android/app/src/main/AndroidManifest.xml`); H7 scoped-storage policy stands.
- The update channel is the public repo; the app reads `AppConfig.githubLatestReleaseUrl` anonymously ([`contracts/update-engine.yaml`](../contracts/update-engine.yaml), `lib/core/config/app_config.dart:36-37`); the first public release `v1.3.1` carries asset `AgentA-v1.3.1.apk` — **observed via the API on 2026-10-18: `size=183012343`, `digest=sha256:eb7643c3…d4bd`** [S18].
- CI signs releases with the stable keystore from Actions secrets (`build-apk.yml`, C4 steps) — this is the load-bearing signature identity (see §4).
- The app already runs foreground downloads for the offline model (`background_downloader`, `SystemForegroundService` in the manifest) — reusable infrastructure for the APK download (P4 decision).

## 2. The permission and the per-app "Install unknown apps" grant

**What to declare.** `REQUEST_INSTALL_PACKAGES` — "Allows an application to request installing packages. Apps targeting APIs greater than 25 must hold this permission in order to use `Intent.ACTION_INSTALL_PACKAGE`." [S1]. The platform source defines it as

```xml
<permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"
    android:protectionLevel="signature|appop" />
```

[S2]. The `|appop` half is the operative mechanism for a non-system app: the user grants the app as a *trusted source*, per app, through "Install unknown apps". (The reference page renders only "signature" in its text [S1]; the AOSP source settles the reconciliation — quoted for the record.)

**The runtime gate (since Android 8.0).**

- "The Allow unknown sources system setting has been removed; in its place, the Install unknown apps permission manages unknown app installs from unknown sources." [S5]
- `PackageManager.canRequestPackageInstalls()` (API 26): "Checks whether the calling package is allowed to request package installs through package installer. Apps are encouraged to call this API before launching the package installer via intent `Intent.ACTION_INSTALL_PACKAGE`." [S3]; "To determine whether an unknown source can install apps using the package installer, you should instead use the return value of `canRequestPackageInstalls()`." [S5]
- The grant UI is routable directly: `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` (API 26) — "Show settings to allow configuration of trusted external sources. Input: Optionally, the Intent's data URI can specify the application package name to directly invoke the management GUI specific to the package name. For example `package:com.my.app`." [S4]
- Managed profiles created on 8.0+ have `DISALLOW_INSTALL_UNKNOWN_SOURCES` enabled [S5] — relevant only if this app is ever distributed inside one; not our case.

**UX consequence (binding for P5):** the first install requires the one-time per-app "allow from this source" grant (routed via `ACTION_MANAGE_UNKNOWN_APP_SOURCES` with `package:com.agenta.AgentA`); every install committed afterwards surfaces at most **one** system confirmation dialog. "Silent install with zero prompts is impossible for a non-system app" (plan ruling 4) is hereby grounded: `setRequireUserAction` (API 31) — "When unspecified for installers using the `REQUEST_INSTALL_PACKAGES` permission [it] will behave as if set to `USER_ACTION_REQUIRED`" [S7], and the session then delivers `STATUS_PENDING_USER_ACTION` — "User action is currently required to proceed. You can launch the intent activity described by `Intent.EXTRA_INTENT` to involve the user and continue." [S6]

## 3. Install API: PackageInstaller sessions (RECOMMENDED) vs the `ACTION_VIEW` + `FileProvider` hand-off

**Recommendation: the PackageInstaller session flow.** Rationale, all cited:

| | PackageInstaller session (recommended) | `ACTION_VIEW` + `FileProvider` hand-off |
|---|---|---|
| Result reporting | Full status via `Session.commit(IntentSender)` — `EXTRA_STATUS` / `EXTRA_STATUS_MESSAGE` [S6][S8] (`STATUS_SUCCESS`, `STATUS_PENDING_USER_ACTION`, `STATUS_FAILURE*`) | None — the intent leaves the app; no completion signal, cancel is invisible |
| API status | Current, first-class [S6-8] | `ACTION_INSTALL_PACKAGE` is "deprecated in API level 29. use PackageInstaller instead" [S9] |
| File exposure | Streamed into the session (`Session` write/fsync/close then `commit`) — **no URI ever leaves the app, no FileProvider needed** | A `content://` URI must be built (`file://` is banned on N+: "If an intent containing a file URI leaves your app, the app fails with a `FileUriExposedException`" [S10]) and a `FileProvider` added [S10][S11] |
| Contract fit | Supports `installing` → `installed`/`installFailed(reason)` (P5 needs exactly this) | Cannot distinguish installed vs failed |

The P7 security review's "FileProvider scope" line therefore resolves favorably: the recommended design exposes **no file URI at all**.

**Session blueprint (for P4):**

1. Precondition: `canRequestPackageInstalls()` [S3]; if false → route the grant (§2), do not start.
2. `PackageInstaller.createSession(new SessionParams(MODE_FULL_INSTALL))`, set `setSize(bytes)` — "Optionally indicate the total size (in bytes) of all APKs that will be delivered in this session." [S7].
3. `openSession(sessionId)` → write the staged APK fully → `fsync` → `close` [S8].
4. `commit(statusReceiver)` — "Attempt to commit everything staged in this session." [S8]; the receiver gets `STATUS_PENDING_USER_ACTION` first (launch `EXTRA_INTENT` — the one system confirmation [S6]) and then a terminal `STATUS_SUCCESS` / `STATUS_FAILURE*`.
5. Map the receiver: `STATUS_SUCCESS` → `installed`; `STATUS_PENDING_USER_ACTION` → keep `installing`; user declined → the aborted failure class [S6]; everything else carries `EXTRA_STATUS_MESSAGE` for the failure reason [S6].
6. `setRequestUpdateOwnership` is **not applicable**: enforcement "can only be enabled on initial installation… the installer must have the `ENFORCE_UPDATE_OWNERSHIP` permission" [S7] — a no-op for this app; do not call it.

**Process-death note (design-relevant):** replacing the running app kills its process — "updating an app that is actively in use … leads to the app's running processes being killed" [S14]. The `installed` state may therefore be observable only pre-death; the reliable post-update confirmation is the next launch comparing the running version against the offered one.

### 3.1 Plugin landscape — recommendation: hand-rolled MethodChannel

Surveyed 2026-10-18 via the pub.dev package API [S17] (dates = latest publish):

| Package | Latest | Published | Notes |
|---|---|---|---|
| `open_filex` | 5.0.0 | 2026-10-15 | Maintained; a generic file-**opener** (intent-based). No install-session status surface — fine for opening links/support pages, not the install mechanism. |
| `install_plugin` | 2.1.0 | 2023-07-11 | The classic APK-install plugin; ~3.3 years without a publish — stale; behavior on modern Android unaudited. |
| `apk_sideload` | 0.0.2 | 2025-10-05 | Purpose-built ("install APK files … with FileProvider support and permission flow") but pre-1.0 (0.0.x) and thin history. |
| `flutter_app_installer` | 2.0.0 | 2026-03-19 | Claims intent **or "silent"** install; a silent path is impossible for a non-privileged installer (§2) — treat the claim skeptically. |
| `app_installer` | 1.3.1 | 2024-12-03 | General app-store/install helper; ~2 years old. |
| `apk_installer` | 0.0.4 | 2023-10-24 | Stale, pre-1.0. |
| `install_plugin_v2` | 1.0.0 | 2021-11-07 | Abandoned fork. |
| `android_package_installer` | 0.0.3 | 2025-05-04 | Thin PackageInstaller wrapper; pre-1.0. |

**Recommendation: hand-rolled MethodChannel over the PackageInstaller session API** (the §3 blueprint). Reasons: (a) the contract (§7) needs the session status channel for `installed`/`installFailed(reason)` — the maintained candidate does not expose it, and the ones that might are years stale or pre-1.0; (b) the platform surface required is small and fully documented (§3); (c) zero third-party code on the security-sensitive executable-install path (P7-favorable); (d) the download half reuses existing in-app infrastructure. `open_filex` remains acceptable for non-install link opens if ever needed — it is not the install route.

## 4. Same-signature in-place update = data preserved — and the keystore dependency

Cited rule [S13]: "App upgrade: When the system is installing an update to an app, it compares the certificate(s) in the new version with those in the existing version. **The system allows the update if the certificates match.** If you sign the new version with a different certificate, you must assign a different package name to the app — in this case, the user installs the new version as a completely new app."

Data preservation (derived from two cited behaviors): an in-place update does **not** take the uninstall path, and "When the user uninstalls your app, the files saved in app-specific storage are removed" [S12] — i.e., app data (including the local DB) survives update-over; only an uninstall or a signature-mismatched "new app" install clears it. This satisfies the user's "no uninstall / no data loss" requirement by construction.

**The CI keystore dependency (flagged per the plan).** "Users can only update your app if the update is signed with the same signing key" [S13]. The fleet's signing identity is the CI keystore (Actions secrets `ANDROID_KEYSTORE_BASE64` etc., `build-apk.yml` C4). "If you lose or misplace your key, you will not be able to publish updates to your existing app. You cannot regenerate a previously generated key." [S13] → **losing the keystore breaks all future in-app updates** (installs would fail the certificate comparison). Mitigation is operational (keystore backup/rotation handling — already referenced by `docs/backend-rls.md` §C1/C4), restated here because the in-app flow is what makes it user-visible.

## 5. Download location (scoped-storage-safe, no runtime permission)

- Target directory: **app-internal files** — `getFilesDir()/updates/` (or the app support dir). Cited: "Your app doesn't require any system permissions to read and write to files in these directories. Other apps cannot access files stored within internal storage." [S12]; on Android 10+ these locations are encrypted [S12].
- Do **not** use the cache dir for the pending APK: "When the device is low on internal storage space, Android may delete these cache files to recover space." [S12] The APK must survive from download to install; delete it explicitly after `installed`/`installFailed`/cancel.
- No runtime storage permission, no shared/external storage — consistent with the manifest's H7 posture (no storage permissions today).

## 6. Integrity floor (TLS + API-derived URL + size/semver cross-check; SHA256 decision)

- **TLS:** all endpoints are HTTPS (`api.github.com`, `github.com` download URLs). Baseline: cleartext is disabled by default from Android 9 (API 28) [S15]; minSdk 26 devices (26-27) would permit cleartext by default, but nothing in this flow uses it. No change required; optional hardening (an explicit cleartext-disabled network security config) is P7's call.
- **API-derived URL only:** the download URL comes exclusively from the `releases/latest` payload (`assets[].browser_download_url`, [contract `update-engine`] and `github_releases_source.dart:212-227`). Never accept a URL from any other source.
- **Size cross-check:** the GitHub asset object exposes `size` [S16] — compare it against the bytes received; our live v1.3.1 asset reports `size=183012343` [S18]. (Also compare the release semver against the offered version, and gate on `versionCode` rolling forward.)
- **SHA256 — recommendation: verify against the GitHub API `digest` field; no new workflow asset is required.** The REST asset object includes `"digest": "sha256:…"` [S16], and our live asset already carries it: `digest=sha256:eb7643c3…d4bd` [S18]. P4 should hash the downloaded APK and compare with the API digest when present. Fallback (if a future asset lacks `digest`): publish the sidecar `AgentA-vX.Y.Z.apk.sha256` from CI — note the workflow nuance: the release step's `files: dist/*.apk` glob does not match a `.sha256` file; the glob would need extending — and the P5 anonymous guard could assert `digest != null` as a publish-time check. Decision for P4 with the Adviser; the floor (TLS+URL+size+semver) holds regardless.
- **Optional pre-install sanity (defense in depth):** `PackageManager.getPackageArchiveInfo(path, flags)` — "Retrieve overall information about an application package defined in a package archive file" [S3] — can assert `packageName == com.agenta.AgentA` and a sane `versionName/versionCode` before committing the session.

## 7. Proposed `contracts/update-engine.yaml` amendment (install-flow states)

Contract-first: P4 amends the authoritative file **before** the P5 consumer; the change is additive → proposed version bump `1.0.0 → 1.1.0` (Adviser's versioning call). Proposed block (wording to be finalized at P4):

```yaml
install_flow:              # proposed (cycle-28 P1b); recorded by P4
  owner: middle-end (P4 service) — consumed by the updater UI (P5)
  state:
    type: "sealed class InstallState (or equivalent stream states)"
    variants:
      downloading:      "bytesReceived: int, totalBytes: int|null, startedAt: DateTime"
      readyToInstall:   "apkPath: String (app-internal), version: String, sizeBytes: int, sha256: String|null, verified: bool"
      installing:       "committed; awaiting the system status — STATUS_PENDING_USER_ACTION keeps this state"
      installed:        "version: String — may only be observable pre-process-death; confirm by version compare on next launch"
      installFailed:    "reason: InstallFailureReason"
  failure_reasons: [download, network, timeout, storage, sizeMismatch, checksumMismatch, permissionDenied, userCancelled, signatureMismatch, invalidPackage, unknown]
  transition_rules:
    - "readyToInstall requires verified == true on the floor checks (size; sha256 when present) + the archive sanity check"
    - "permissionDenied is produced by the pre-install canRequestPackageInstalls() gate — the UI routes ACTION_MANAGE_UNKNOWN_APP_SOURCES; it is not an install attempt"
    - "userCancelled ← the aborted failure status (the user declined the single system confirmation)"
    - "signatureMismatch ← the certificate-comparison failure class (§4)"
    - "STATUS_PENDING_USER_ACTION is NOT a failure — launch EXTRA_INTENT and stay installing"
  notes:
    - "the browser hand-off is replaced; no server-side change (GitHub Releases stays the source)"
    - "the download itself keeps the existing silence rules (auto paths) — install is user-initiated only"
```

## 8. Feasibility verdict (the P1b STOP check)

**FEASIBLE — no STOP.** Every required mechanism is public API available since ≤ API 26 (minSdk 26), requires only user grants (one-time unknown-sources + one confirmation per install — plan ruling 4), and preserves data via the same-certificate in-place update with the stable CI keystore. There is no Play dependency and no server-side change. Open operational risks, flagged not blocking: keystore loss (§4), the `digest`-vs-sidecar choice (§6), and the API-36-era developer-verification constants [S6] whose future policy impact is `unverified` (§0).

## 9. Open items for P4 / P7

- P4: pick the download engine (reuse `background_downloader` vs plain `http` + progress); Kotlin MethodChannel surface (small: `canInstall()`, `startInstall(path, size)`, status events); session receiver mapping; cleanup rules for the staged APK.
- P4: amend the contract (§7) before the service, then the service, then hand P5 the states.
- P7 (security review): provenance chain (TLS → API-derived URL → size → digest), no file-URI exposure (recommended design has none), permission necessity (exactly `REQUEST_INSTALL_PACKAGES`), storage location, failure paths (no partial-APK commits; `abandon()` on every failure [S8]).

## Sources (all fetched 2026-10-18, HTTP 200, via curl)

- [S1] developer.android.com — `Manifest.permission` (REQUEST_INSTALL_PACKAGES entry)
- [S2] AOSP platform source — `frameworks/base/core/res/AndroidManifest.xml` (android.googlesource.com)
- [S3] developer.android.com — `PackageManager` (`canRequestPackageInstalls`, `getPackageArchiveInfo`)
- [S4] developer.android.com — `provider.Settings` (`ACTION_MANAGE_UNKNOWN_APP_SOURCES`)
- [S5] developer.android.com — Android 8.0 behavior changes (unknown sources)
- [S6] developer.android.com — `PackageInstaller` (statuses, extras, developer-verification constants)
- [S7] developer.android.com — `PackageInstaller.SessionParams` (`setRequireUserAction`, `setSize`, `setRequestUpdateOwnership`)
- [S8] developer.android.com — `PackageInstaller.Session` (`commit`, `abandon`, `fsync`)
- [S9] developer.android.com — `Intent` (`ACTION_INSTALL_PACKAGE` deprecation)
- [S10] developer.android.com — Android 7.0 behavior changes (`FileUriExposedException`)
- [S11] developer.android.com — `androidx.core.content.FileProvider`
- [S12] developer.android.com — App-specific storage
- [S13] developer.android.com — App signing (App upgrade / certificate comparison; key loss)
- [S14] developer.android.com — Android 14 features (update ownership; process kill on update)
- [S15] developer.android.com — Network security configuration (cleartext defaults)
- [S16] docs.github.com — REST releases reference (asset `size`, `digest`)
- [S17] pub.dev package APIs — `open_filex`, `install_plugin`, `apk_sideload`, `flutter_app_installer`, `app_installer`, `apk_installer`, `install_plugin_v2`, `android_package_installer` (versions/published dates, §3 decision context)
- [S18] live observation — `GET api.github.com/repos/Shuash11/AgentA/releases/latest` (v1.3.1 asset size + digest)
