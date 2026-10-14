# Google Sign-In Setup Runbook — AgentA

Package: `com.agenta.AgentA`
Supabase project: `pmeygoyubqiaqvsuyjzm`
Server client type: **Web OAuth client** (`GOOGLE_SERVER_CLIENT_ID`).

> Symptom this fixes: on Android the Google sheet dismisses instantly with
> "cancelled" even though the user never tapped cancel. That is almost always
> a **config-cancel** (SHA / OAuth client / Supabase mismatch), not a
> user-cancel. See [Diagnosing cancel vs config-cancel](#5-diagnosing-user-cancel-vs-config-cancel).

---

## 1. Package and signing facts

- `android/app/build.gradle`: `namespace` and `applicationId` are both
  `com.agenta.AgentA` (case-sensitive — the capital `A` matters).
- Every SHA-1 you register in Google Cloud Console must be under this exact
  package name. A SHA registered under `com.agenta.agenta` will not work.
- Current signing strategy (C4 fixed): `android/app/build.gradle` reads
  `android/key.properties` (CI secrets) for a real `signingConfigs.release`;
  without the file it falls back to debug keys for local
  `flutter run --release` only. Tag builds fail CI without a keystore.

## 2. Collect SHA-1 fingerprints

Run `keytool` against each keystore that will ever sign this package.
`keytool` ships with the JDK (same one used by `actions/setup-java` in CI).

### 2a. Local debug keystore (default dev machine)

```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android
```

Copy the `SHA1:` line.

### 2b. CI debug keystore

CI runners generate a fresh `~/.android/debug.keystore` unless you upload one.
Either:

- Option A (simple): log the fingerprint during a debug build and register it,
  or
- Option B (stable): commit an encrypted debug keystore as a repo secret and
  restore it in `build-apk.yml` before `flutter build`.

To print the CI fingerprint without changing the build output, add a
temporary step:

```yaml
- run: keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep SHA1
```

Register the printed SHA-1 as an Android OAuth client (Section 3), then
remove the temporary step or keep it as documentation.

### 2c. Release keystore (self-managed)

```bash
keytool -list -v -keystore /path/to/release.keystore -alias <your-alias>
```

### 2d. Play App Signing (once the app is in Play)

1. Play Console → your app → Setup → App integrity → App signing.
2. Copy the **App signing key certificate → SHA-1**.
3. Also copy the **Upload key certificate → SHA-1**.
4. Register **both** as Android OAuth clients (Section 3). The upload SHA
   covers pre-Play internal builds; the signing SHA covers everything users
   download.

## 3. Google Cloud Console steps

Project: the GCP project linked to Supabase project `pmeygoyubqiaqvsuyjzm`
(or whichever GCP project owns the OAuth consent screen users see).

1. APIs & Services → Credentials → Create Credentials → **OAuth client ID**.
2. Create **one Web application** client first. This is the
   `GOOGLE_SERVER_CLIENT_ID` (ends with `.apps.googleusercontent.com`).
   - Never paste an Android client ID into `GOOGLE_SERVER_CLIENT_ID`.
   - Copy the Web Client ID **and** Client Secret for Section 4.
3. Create **one Android client per SHA-1** from Section 2:
   - Application type: Android.
   - Package name: `com.agenta.AgentA` (exact case).
   - SHA-1: paste one fingerprint per client.
   - Repeat for local debug, CI debug, release/upload, and Play signing SHAs.
4. OAuth consent screen → Test users: add tester accounts while the app is in
   Testing mode, otherwise sign-in returns access-denied that looks like a
   cancel on some devices.

## 4. Supabase Dashboard steps

Project `pmeygoyubqiaqvsuyjzm` → Authentication → Providers → Google:

1. Enable the Google provider toggle.
2. **Client ID (for OAuth):** paste the **Web** Client ID from Section 3.
3. **Client Secret:** paste the matching Web Client Secret.
4. **Authorized Client IDs / allowlist:** add the Web Client ID (some
   Supabase versions also accept the Android client IDs here — add them if
   the field accepts multiple values).
5. **Skip nonce checks: ON** for native Android (`google_sign_in` /
   Credential Manager flow). Leaving it OFF is a common cause of the
   instant-cancel symptom.
6. Save. Then re-test on a real device — Dashboard changes can take ~1 min
   to propagate.

## 5. Diagnosing user-cancel vs config-cancel

Use `adb logcat` on a device that reproduces the issue:

```bash
adb logcat -c
adb logcat | grep -Ei "CredentialManager|CredMan|reauth|ApiException|GoogleSignIn|AuthCredential|supabase"
```

Then tap Google sign-in once and read the burst:

| What you see | Meaning |
|---|---|
| `User canceled` / `canceled by user` with no exception code | True user-cancel. No config fix needed. |
| `ApiException: 10` (`DEVELOPER_ERROR`) | SHA-1 + package not registered, or wrong GCP project. Recheck Sections 2-3. |
| `ApiException: [16]` / `CANCELED` right after `reauth` or `CredentialManager` request | Config-cancel. First check the **APK signing key**: a debug-fallback CI build has a different random SHA-1 every run, so no OAuth Android client can match it (see Section 7). Otherwise nonce / serverClientId / Supabase provider mismatch — check Web vs Android client confusion and Skip-nonce setting. |
| `redirect_uri_mismatch` or `invalid_client` | Supabase has the wrong Web ID/secret. Recheck Section 4. |
| Nothing at all in logcat | Button never fired (missing `GOOGLE_SERVER_CLIENT_ID` at build time — app reports "not configured"). Check the CI secret (dart-define). |

## 6. Test device requirements

A correctly configured app still fails on a bad device image. Use:

- A device/emulator with **Google Play Services** installed (not a bare AOSP image).
- A **Play Store system image** (`Google Play` tab in AVD Manager), signed into a real Google account.
- Updated **Chrome** (Custom Tabs handle the OAuth fallback) and updated Play Services.
- Android 8+ (`minSdk 26`) with network access to `accounts.google.com`.

## 7. Signing strategy (CI)

`android/app/build.gradle` signs release builds with
`signingConfigs.release` (from `android/key.properties`) and falls back to
`signingConfigs.debug` only when `key.properties` is absent.

CI (`.github/workflows/build-apk.yml`) restores the release keystore from
these repository secrets:

| Secret | Purpose |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of the release `.jks`/`.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` | store password |
| `ANDROID_KEY_ALIAS` | key alias inside the keystore |
| `ANDROID_KEY_PASSWORD` | key password (PKCS12: same as store password) |

### Why the keystore is mandatory, not optional

Without it, CI signs with the runner's **debug** key, and GitHub generates a
**new random debug keystore on every run**. That means:

- Google Sign-In always fails with `[16] Account reauth failed` — no OAuth
  Android client SHA-1 can ever match a per-build fingerprint.
- APK updates are rejected (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`), so users
  must uninstall/reinstall for every release.

The workflow therefore **fails the build** when Google sign-in is configured
(`GOOGLE_AUTH_STATUS=ok`) but no release keystore is present.

### Getting the fingerprint to register

Every build prints the APK's signing certificate into the run summary
(`Report APK signing fingerprint (C4)` step) and as a job notice:

```
Signer #1 certificate SHA-1 digest: aa:bb:...
Signer #1 certificate SHA-256 digest: ...
```

Register that SHA-1 (Section 3) as an **Android** OAuth client for
`com.agenta.AgentA`. Because the keystore is stable, this is a one-time step.

Locally:

```bash
keytool -list -v -keystore /path/to/release.jks -alias <alias> | grep SHA1
```

> Keep the keystore file and its passwords backed up. If they are lost you
> cannot publish updates for already-installed apps.

---

## Quick checklist (copy into PRs)

- [ ] `com.agenta.AgentA` SHAs registered: local / CI / release / Play signing / Play upload
- [ ] CI signed with the stable release keystore (`ANDROID_KEYSTORE_*` secrets) — its SHA-1 comes from the build summary, not a guess
- [ ] Web client ID used for `GOOGLE_SERVER_CLIENT_ID` (ends `.apps.googleusercontent.com`)
- [ ] Supabase → Google provider enabled, Web ID + secret set, Skip nonce ON
- [ ] Tested on Play Services image with updated Chrome
- [ ] `adb logcat` shows no `ApiException: 10` / `[16]`
