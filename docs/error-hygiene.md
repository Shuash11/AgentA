# Error-message hygiene

Convention: **raw exception text never reaches the UI.** User-facing
strings are friendly and static; the raw detail goes to `kDebugMode`
logs and to a bounded in-app diagnostics toggle.

## Sanitized sites

| Site | UI shows | Raw detail goes to |
| --- | --- | --- |
| `lib/main.dart` app-config load failure | `App configuration failed to load. Please try again.` | `debugPrint('[Main] AppConfig.init failed: $e')` |
| `lib/main.dart` database init failure | `App data failed to initialize. Please try again.` | `kDebugMode` log at the throw site |
| `lib/presentation/profile/editprofile.dart` save failure | `Could not save your profile. Please try again.` (SnackBar) | `debugPrint('[EditProfile] save failed: $e')` |
| `lib/presentation/auth/login.dart` `_mapGoogleError` | `Google sign-in failed (<code>).` / `Google sign-in failed. Please try again.` / `... Check your connection.` | `debugPrint('[Login] Google sign-in failed: $e | $stack')` + typed `GoogleSignInFailure` |
| `lib/presentation/dashboard/dashboard.dart` load failure | `Couldn't load your conversations.` + Retry button (never the empty state) | `debugPrint('[Dashboard] load chats failed: $e')` |
| `lib/presentation/chats/chats.dart` generation-error path | `ChatErrorClassifier.friendly(...)` static strings (offline-ready, no-internet, provider, generic fallback) | raw exception text, classified in `lib/core/utils/chat_error_classifier.dart` (unit-tested) |

## Bounded diagnostics

Dynamic detail (plugin internals, server messages) is truncated at the
throw sites via `GoogleSignInFailure.truncateDetail`
(`lib/services/auth/auth_service.dart`):

- Bound: `maxDetailLength = 200` chars, longer input cut with a `...` suffix.
- Null/empty/whitespace-only input normalizes to `null` (never an empty string).
- The `GoogleSignInFailure` object is in-memory only — never persisted.

## Show details toggle

`login.dart` renders a `Show details` / `Hide details` toggle under the
friendly message. When expanded it shows the bounded typed contract only:

```text
code: <code>
detail: <detail or '(none)'>
hint: <hint>
```

## Log pattern

When adding a new failure path, follow this shape:

```dart
} catch (e) {
  if (kDebugMode) {
    debugPrint('[Tag] what failed: $e');
  }
  // UI: friendly static text only. Dynamic detail only via truncateDetail.
}
```

## CI guard

`.github/workflows/build-apk.yml` (`Guard - no raw exception text in UI`)
greps `lib/` for the exact removed leak strings (e.g.
`Failed to save: ${e.toString()}`, `Failed to load app config: $e`).
It is intentionally narrow: broad `toString` matching would
false-positive on the legitimate `kDebugMode` logs and the bounded
`displayDetail`/hint classification above. `test/` is excluded so
fixtures may quote such strings.

## Offline model download failures

`ModelDownloadService` maps every install failure to a friendly static
string (raw plugin detail stays in `kDebugMode` logs):

| Failure | UI shows | Note |
| --- | --- | --- |
| Silent stall (no progress for 3 min) | `Download stalled. Please try again.` | App-side watchdog; retryable, cancels the native task via `CancelToken` |
| Overall timeout (30 min) | `Download timed out. Please try again.` | Belt-and-braces ceiling around the whole install |
| User cancellation | silent (previous state kept) | `CanceledError` / `CancelToken.isCancel` map to `null` |
| No connectivity | `No internet connection. Download will resume when you are back online.` | Typed `NetworkError` |
| Other typed errors | `Download failed. Please try again.` (or the specific not-found / rejected / rate-limited text) | See `_friendlyDownloadError` |

Crash fix: the download runs as a foreground service with `dataSync`
type, which on Android 14+ requires the `SystemForegroundService`
declaration (`android:foregroundServiceType="dataSync"`) in the merged
manifest. The plugin merges only its own service, so the app declares
it in `android/app/src/main/AndroidManifest.xml` (`tools:node="merge"`).
CI verifies it (`Guard - foreground service in merged manifest`): a
node-aware grep on the source manifest plus every release merged
manifest produced by the build — naive string greps would false-pass on
comments and on the plugin's own `dataSync` service.

Experiment override: `FOREGROUND_DOWNLOAD` (default `true`; `'false'`
falls back to the background path without a rebuild) via
`AppConfig.foregroundDownload`.

Retry budget: `maxDownloadRetries: 3` in `lib/main.dart`. Each attempt
can run up to the 30-min install ceiling above, so a larger budget
could never complete within the timeout — 3 keeps the worst case
inside a plausible session while transient errors still get retried.
