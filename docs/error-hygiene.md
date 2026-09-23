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
