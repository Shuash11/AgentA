# Cycle 32 — Screen-lock OR-gate: PIN-only devices must receive the device-credential prompt (cycle-31 residual)

**status:** active
**created:** 2026-10-27
**created by:** Adviser (cycle-31 closure row, 2026-10-27: recorded residual of the second-factor matrix)
**repo:** C:\projects\aiproject (AgentA) — Flutter, branch main; predecessor `plans/done/cycle-31-second-factor-password-change.md` (closed green at `3b3c5d8`, release v1.5.0 published)
**level:** **3 (Complex)** — touches the auth surface (the device-credential probe gating two step-up flows). Classification signal: "touches auth" escalates one level from the Level-2 default; same surface as cycle-31. The production diff is small (~10 lib lines), but level follows observable signals, not effort.
**version bump:** **patch `1.5.0+1 → 1.5.1+1` — FINAL** (`pubspec.yaml:4` currently `1.5.0+1`). Reason: this makes the device-credential step-up feature shipped in 1.5.0 actually function on PIN-only devices — a bug fix of an existing user-facing feature, not a new feature (`docs/versioning.md:33`: "Bug fix / small improvement, no new features → patch"). No breaking change, no data migration, so no major. Build number restarts at `+1` per release precedent. The push agent must not re-decide. Tag/release cut is DEFERRED — see Push guidance.

## Ground truth (verified 2026-10-27)

All file:line references below were read this date; plugin sources read from the pub cache at the exact pinned versions (`pubspec.lock`: local_auth 3.0.2 @ :675-682, local_auth_android 2.2.0 @ :683-690, local_auth_darwin 2.0.4 @ :691-698, local_auth_platform_interface 1.1.0 @ :699-706, gotrue 2.27.3 @ :515-522).

**The current probe (the defect):**

- `biometric_auth_service.dart:12-19` — `isSupported()` = `await _auth.isDeviceSupported() && await _auth.canCheckBiometrics` (AND), try/catch → false.
- Its four consumers (grep-verified, complete list):
  1. `login.dart:226-239` `_checkBiometric` — `_biometricReady = isSupported() && isEnrolled()` → the login fingerprint chip.
  2. `login.dart:836-839` `_offerBiometricEnroll` — `if (!await isSupported()) return;` → the post-sign-in "Quick unlock?" offer.
  3. `change_pass_page.dart:109-110` — `PasswordChangeFactorGate.deviceCredentialPromptAvailable() => BiometricAuthService.isSupported()` (the P3 step-up pre-probe; consumed at `:407-422` — probe true → prompt required, probe false → degrade notice "This phone has no screen lock…").
  4. `offline_password_service.dart:78-84` — `deviceCredentialPromptAvailable() => BiometricAuthService.isSupported()` (the P4 pre-probe; consumed at `:149-158` — same probe/prompt/degrade shape).
- The P3/P4 prompt itself: `biometric_auth_service.dart:124-147` `confirmDeviceCredential` → `authenticate(biometricOnly: false, persistAcrossBackgrounding: true)`.

**Why the AND gate degrades PIN-only devices (pinned-source-verified, both platforms):**

- Android (`local_auth_android-2.2.0/android/.../LocalAuthPlugin.kt`): `isDeviceSupported()` (Kotlin :44-46) = `keyguardManager.isDeviceSecure || canAuthenticateWithBiometrics()` → **TRUE on a PIN-only device**; `deviceCanSupportBiometrics()` (:48-50) = `hasBiometricHardware()` (:150-154, `canAuthenticate(BIOMETRIC_WEAK) != ERROR_NO_HARDWARE`) → **FALSE with no biometric hardware**. Dart mapping (`local_auth-3.0.2/lib/src/local_auth.dart:85-89`): `canCheckBiometrics` → `deviceSupportsBiometrics()`; `isDeviceSupported()` documented as "capable of checking biometrics or is able to fail over to device credentials". So AND = `true && false` = false → degrade. The plugin's own `authenticate()` gate (:100-103) uses `isDeviceSupported()` **alone**, and `allowCredentials` (:108, `!biometricOnly && canAuthenticateWithDeviceCredential()` :156-164) enables the credential prompt → with `biometricOnly: false` the PIN prompt WOULD show. The gate is the only thing blocking it.
- iOS (`local_auth_darwin-2.0.4/darwin/.../LocalAuthPlugin.swift`): `deviceCanSupportBiometrics()` (:115-135) = `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` → requires **enrolled** biometrics (biometryNotEnrolled → false) → false on a passcode-only iPhone; `isDeviceSupported()` (:157-159) = `canEvaluatePolicy(.deviceOwnerAuthentication)` (biometrics OR passcode) → true. Same AND-degrade, same OR-fix.

**The vendor-recommended gate (pinned README + live pub.dev, both fetched 2026-10-27):**

- `local_auth-3.0.2/README.md:25-35` and pub.dev/packages/local_auth (3.0.2 still latest, published ~3 months ago): `final canAuthenticate = canAuthenticateWithBiometrics || await auth.isDeviceSupported();` — "call `canCheckBiometrics` (if you need biometrics support) and/or `isDeviceSupported()` (if you just need some device-level authentication)". No divergence between pinned and live.

**Wipe-at-10 reachability (the ruled-out rival task):**

- `offline_login_guard.dart:44-58` — `recordFailure` prunes entries older than `lockoutWindow` (5 min, :12), appends, sets `_lockedUntil = now + 5min` when count ≥ `maxAttempts` (5, :54-56), returns count ≥ `maxFailuresBeforeWipe` (10, :57).
- Both production callers gate on `isLockedOut` BEFORE any failure can be recorded: `login.dart:399-406` returns early when locked (refusal at :399 precedes `recordFailure` at :441); `offline_password_service.dart:123-127` throws `lockedOut` (precedes `_recordFailure` at :137 → `recordFailure` at :180).
- Induction: after the 5th failure within a window the lockout refuses all further attempts; when the lockout expires (t5+5min) every stored entry is ≥ 5 min old and is pruned by the next `recordFailure`. The count can never exceed 5 through production callers → the wipe branches (`login.dart:442-454`, `offline_password_service.dart:180-191`) are **structurally unreachable dead code**. Only `test/smoke_test.dart:128` reaches 10, by calling `recordFailure` directly past the gate.

**R4 rider — `signInWithOtp` for non-existent emails (VERIFIED 2026-10-27, claim refuted):**

- App call sites: `auth_service.dart:538-541` (`sendOtpForReset`, `shouldCreateUser: false` hardcoded) and `auth_service.dart:725-734` (`sendOtpForStepUp`, default false) → pinned gotrue 2.27.3 `gotrue_client.dart:603-630` POSTs `create_user: false` and performs no client-side existence check (server behavior).
- Server behavior, current `supabase/auth` master `internal/api/otp.go` (fetched 2026-10-27): `Otp()` calls `shouldCreateUser()` first; with `CreateUser=false` and `models.IsNotFoundError` on `FindUserByEmailAndAudience` it returns `(false, nil)` → the handler returns **HTTP 422, `ErrorCodeOTPDisabled`, "Signups not allowed for otp"** — before `MagicLink` runs. Non-silent: the client throws, and `forgot_password.dart:87-94` shows "Failed to send the code. Please check the email and try again."
- Caveats recorded: (a) this is `master`; the hosted Supabase instance's auth version can lag — under an older silent-success build the user would see "code sent" with no email arriving. Both behaviors land inside the app's existing send-error / sent paths; no code change is warranted either way. (b) The cycle-31 OTP fallback (`sendOtpForStepUp`) targets the **session** account's email, which always exists for a signed-in Supabase user → the 422 path cannot fire there; zero impact on the cycle-31 matrix.

## Research citations (web-research decision: SEARCH REQUIRED — executed 2026-10-27)

Two claims depend on external, time-sensitive vendor behavior, so the search ran:

1. **local_auth OR-gate recommendation** — pub.dev/packages/local_auth fetched live (3.0.2 still latest; README identical to the pinned cache copy): the OR gate is the vendor's documented device-capability check. Plugin internals verified from the pinned pub-cache sources (Android Kotlin + iOS Swift + Dart API docs, cited in Ground truth) — the strongest possible evidence class for pinned-version behavior.
2. **Supabase `signInWithOtp` server behavior** — `supabase/auth` master `internal/api/otp.go` fetched via GitHub raw (the old `internal/handler/` path 404'd; the GitHub API tree located the current `internal/api/otp.go`). Supports the R4 refutation above.

**Search-or-skip declaration:** searched (2 live vendor sources + pinned pub-cache sources read first-hand); no claim rests on training knowledge. UNVERIFIED items are marked: the hosted Supabase instance's auth version (recorded as a caveat, not load-bearing); the exact MethodChannel/Pigeon channel the unit tests must mock (empirically determined during implementation — see P1).

## Rulings (binding)

**1. Wipe-at-10 — RULED: structurally unreachable dead code; no account-loss risk; NOT the cycle task.** The `isLockedOut`-before-`recordFailure` sequencing at both production callers caps the failure count at 5; lockout expiry always coincides with a full window prune (proof in Ground truth). The wipe can never fire, so no user can ever lose an account to it — the risk that would have outranked the OR-gate does not exist. Recorded as backlog W1 (cleanup-or-document, its own future cycle — changing rate-limit semantics deserves its own security review, not a rider). Cycle task: **the OR-gate**, as recorded in the cycle-31 closure row.

**2. API change shape — RULED: a NEW predicate; `isSupported()` semantics unchanged.**
- Add to `BiometricAuthService`: `static Future<bool> isDeviceCredentialPromptAvailable()` = `await _auth.canCheckBiometrics || await _auth.isDeviceSupported()`, wrapped in the same try/catch→false degrade shape as `isSupported()` (`biometric_auth_service.dart:12-19`), with a doc comment citing the vendor OR-gate and the PIN-only rationale.
- Swap exactly the two step-up probe seams to it: `change_pass_page.dart:109-110` and `offline_password_service.dart:83-84` (their seam names `deviceCredentialPromptAvailable()` and their consumers are otherwise untouched).
- `isSupported()` (AND) and both its login consumers (`login.dart:228`, `login.dart:838`) are **byte-untouched**. Why not change `isSupported()` to the OR: `_offerBiometricEnroll` (`login.dart:836-859`) would then offer "fingerprint unlock" on PIN-only devices, and a confirmed enroll would bind quick-unlock to a device that can only prompt the PIN — a login-surface behavior change and wrong UX, violating the recorded constraint that login biometric unlock must not change behavior. The step-up prompts (`confirmDeviceCredential`) are explicitly "biometric or the phone's PIN" factors — there the OR is the intended semantics. The OR also mirrors the plugin's own internal `authenticate()` gate (Android `LocalAuthPlugin.kt:100` uses `isDeviceSupported()` alone), so the probe can never be stricter than the prompt the platform will actually run.
- Riders on P1: (a) **R4 closes as verified-no-action** (above; recorded in the backlog, no code). (b) The cycle-31 Reviewer's record-only nit — comment precision at `change_pass_page.dart:50-64` — MAY ride P1 as a comments-only edit (no code lines touched); if the fix would touch code, drop it.

**3. N3 (validator inconsistency) — RULED: stays HELD.** `change_pass_page.dart:174-178` (≥6 chars, no composition rule) vs `AuthService.validatePassword` (`auth_service.dart:588-597`, ≥8 + letter+digit) remains inconsistent. It touches a file P1 also touches, which makes riding tempting, but N3 is a behavior change (a 6-7-char password would newly be rejected at change time) on the same auth page — cycle-31 deferred it "to keep the auth change reviewable in isolation" and that reason still stands; a validation-policy tightening also deserves an explicit user nod. It stays in the backlog for its own cycle.

**4. C27/28/29 — NOT closed this cycle.** The user has not yet confirmed the on-device v1.4.1 → v1.5.0 in-app hop. The docs commit keeps a ride-along SLOT only; the closure pass happens on user confirmation.

**Threat model ( Level-3 mini-design of record; design is folded into the plan because the audit above IS the design):** the only behavioral delta is P3/P4 probe false→true on PIN-only devices, and true only ADDS the possession-factor prompt to flows that previously degraded — strictly stronger authentication on those devices; every other device class is unchanged (biometric devices: probe already true; no-screen-lock-no-biometrics: OR still false → the recorded fail-open degrade is preserved). The login surface is pinned unchanged by keeping `isSupported()` byte-identical.

**STOP RULE (binding, mirrors cycle-31):** if implementation or review finds (a) any login-surface behavior change (chip visibility, enroll offer, unlock flow) caused by this diff, or (b) any step-up path that ends with FEWER factors than before on any device class, the phase ends in STOP: no further code, evidence recorded, Adviser re-scopes.

**Contract implications: NONE** — no app-defined endpoint, payload, status code, or error shape changes; only pinned third-party APIs (`local_auth`) and internal seams are touched; `contracts/update-engine.yaml` unaffected. No contractor phase.

## Findings backlog (Level 3 — ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **N8** | **Screen-lock OR-gate: PIN-only devices degrade instead of receiving the device-credential prompt. SELECTED as the cycle-32 task** (API shape per Ruling 2). | security / UX | `biometric_auth_service.dart:12-19`; `change_pass_page.dart:109-110`; `offline_password_service.dart:83-84`; pinned local_auth sources (Ground truth) | middle-end | **EXPENSIVE** |
| W1 | Wipe-at-10 branches in both `recordFailure` consumers are structurally unreachable dead code (lockout-at-5 caps the count; proof in Ground truth). Fix = remove the branches OR document the invariant in `offline_login_guard.dart`; changing guard semantics needs its own review. NOT this cycle (Ruling 1). | logic / maintainability | `offline_login_guard.dart:44-58`; `login.dart:399-454`; `offline_password_service.dart:123-191`; `test/smoke_test.dart:128` | middle-end | EXPENSIVE (behavior if removed) |
| R4 (CLOSED) | `signInWithOtp` silent-success-for-non-existent-emails — REFUTED against current server source: 422 `OTPDisabled` ("Signups not allowed for otp") when `create_user: false` and the email is unknown. App error path already correct. Caveat: hosted instance may lag master (both behaviors land in existing paths). No action. | security / UX | `supabase/auth` master `internal/api/otp.go` (fetched 2026-10-27); `auth_service.dart:538-541,725-734`; `forgot_password.dart:87-94` | — | — |
| N3 | Password-change validator (≥6) weaker than `AuthService.validatePassword` (≥8, letter+digit). HELD per Ruling 3. | security / consistency | `change_pass_page.dart:174-178`; `auth_service.dart:588-597` | middle-end | EXPENSIVE |
| N4b | `docs/versioning.md:77` "Existing tags" list ends at v1.2.5 — v1.3.1/v1.4.0/v1.4.1/v1.5.0 missing (cycle-31 Reviewer + Adviser-verified). Taken this cycle as P2 (CHEAP docs). | docs | `docs/versioning.md:77`; actual tags via `git tag -l` | middle-end-light | CHEAP |
| N9 | `local_auth_android` 2.3.0 published vs `pubspec.lock` pin 2.2.0 (recorded from the cycle-32 Reviewer's dependency note; the cycle-32 fix needed no bump — 2.2.0 semantics were pinned-source-verified). Dependency-refresh candidate for its own housekeeping cycle; a plugin bump touches auth-adjacent behavior, so EXPENSIVE if taken. | dependency / maintainability | cycle-32 Reviewer search note; `pubspec.lock:683-690` | middle-end | EXPENSIVE (auth plugin) |
| R2 | Forgot-password post-reset notification email (carried, cloud-dependent). | security | cycle-30/31 backlog | user action / backend | EXPENSIVE (cloud) |
| R3 | Cross-device session invalidation after password change (carried). | security | cycle-31 backlog | middle-end | EXPENSIVE |
| R5 | Recovery-code storage remains unsalted fast-hash, client-verified (cloud-blocked escalation). | security | cycle-31 backlog | backend / user action | EXPENSIVE (cloud) |
| R6 | `updateUser(password, currentPassword)` server flag `GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD` (Dashboard/cloud) — client-verified in cycle-31, server enforcement pending. | security | cycle-31 backlog | user action | EXPENSIVE (cloud) |
| R7 | Cycle-10 carryovers (F4/F5/F12 cloud-blocked; F13; F18). | maintainability / CI | cycle-10 plan | backend | EXPENSIVE |

Ranking rationale: N8 is the recorded cycle-32 residual and the only behavioral task. W1 was the rival candidate and is ruled out by the reachability proof (no account-loss risk exists). R4 closed at zero cost. N4b is the one CHEAP docs debt taken. N3 deliberately held (isolation + policy weight). R2/R3/R5/R6/R7 carried unchanged.

## Selected task (N8) — orchestration

**ORCHESTRATION RULE (binding, mirrors cycles 30/31):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run ONCE each over the whole plan — P1 is EXPENSIVE (auth-surface behavior change), so the e2e run IS REQUIRED before the single review pass. Definitive acceptance = post-push CI watch.

**No separate design phase:** the Level-3 design-of-record is this plan's Ground truth + Ruling 2 + the threat model — the audit already fixed the API shape, the blast radius, and the STOP conditions before any code phase was planned. A re-derivation phase would add ceremony without new decisions.

## Phase 1 — OR-gate predicate + step-up probe swap + tests

- **Phase id:** P1
- **Objective:** PIN-only (no biometric hardware) devices pass the P3/P4 step-up pre-probe and receive the device-credential prompt; every other device class and the whole login biometric surface behave exactly as today.
- **Responsible subagent:** middle-end
- **Files to change:**
  - `lib/services/auth/biometric_auth_service.dart` — NEW `static Future<bool> isDeviceCredentialPromptAvailable()` per Ruling 2 (OR composition, try/catch→false, doc comment with the vendor citation + PIN-only rationale). `isSupported()`, `enroll`, `unlock`, `confirmDeviceCredential` bodies byte-untouched.
  - `lib/presentation/profile/change_pass_page.dart` — the seam at `:109-110` delegates to the new predicate (one line); its doc comment stays truthful (it already says "biometric or the phone's PIN/pattern/passcode"). Optional comments-only rider: the cycle-31 nit at `:50-64` (Ruling 2b).
  - `lib/services/auth/offline_password_service.dart` — the seam at `:83-84` delegates to the new predicate (one line); update its doc comment if needed to stay truthful.
  - `test/cycle32_or_gate_test.dart` (NEW) — unit tests per the acceptance criteria.
- **Size + check classification:** **heavy**, **EXPENSIVE**. Sizing reason: auth-surface behavior (work-sizing heavy signal: auth) — even though the production diff is ~10 lines, classification follows the surface, not the line count; heavy routes to `middle-end`. EXPENSIVE because the probe change alters runtime behavior of two flows. The plan-end e2e run covers it.
- **Implementation steps:**
  1. Add the predicate per Ruling 2. Keep the OR short-circuit-free (`await` both calls, like `isSupported()` does) so both platform probes are always exercised in tests.
  2. Swap the two seams (one line each).
  3. Unit tests in `test/cycle32_or_gate_test.dart`, following the cycle-31 P2 pattern (`test/cycle31_p2_factor_layer_test.dart:25-31` mocks the local_auth MethodChannel): (a) OR-composition rows — canCheck=false + supported=true → true (the PIN-only fix); canCheck=true + supported=false → true; both false → false; both true → true; a platform throw on either probe → false; (b) regression — `isSupported()` remains AND: canCheck=false + supported=true → false. Preferred mock: a fake `LocalAuthPlatform` set on `LocalAuthPlatform.instance` (the setter is public — `local_auth_android.dart:23` pattern); if the registered platform resists faking, mock whichever channel the pinned implementation actually invokes (legacy `'plugins.flutter.io/local_auth'` per the P2 precedent, or the Pigeon per-method channels) and record which in the phase report.
  4. Run the three local gates: `flutter analyze` exit 0; `dart format --output=none --set-exit-if-changed lib test` exit 0; `flutter test` all-pass (report the count delta vs cycle-31's 383-passed baseline).
  5. Confirm zero diff in `biometric_auth_service.dart` outside the new predicate, and zero diff in `login.dart`.
- **Acceptance criteria (each individually checkable):**
  - The new predicate returns true on a PIN-only device class (canCheck=false, supported=true) — unit-tested.
  - `isSupported()` is byte-unchanged (AND semantics) and `login.dart` is byte-unchanged — read the diff.
  - P3 flow: with the probe true, `confirmDeviceCredential` is required before `updatePassword`; with the probe false, the degrade notice path is preserved (existing cycle-31 P3/P4 tests still pass unchanged — the seam swap must not alter flow behavior for either probe value).
  - P4 flow: same probe-true/probe-false pairs hold through `OfflinePasswordService.updateLocalPassword` (existing tests still pass).
  - All three local gates exit 0.
- **Verification:** EXPENSIVE — covered by the plan-end e2e run + the single Reviewer pass.
- **Dependencies / sequencing:** first; P2 is independent and may run in parallel but lands after P1's diff is final.
- **Expected result:** the cycle-31 residual closed; no login-surface change.

## Phase 2 — Docs hygiene (post-implementation, pre-Reviewer)

- **Phase id:** P2
- **Objective:** the docs statements touched by this cycle are truthful; the C27/28/29 ride-along slot exists but stays OPEN.
- **Responsible subagent:** middle-end-light
- **Files to change:** `docs/versioning.md` — fix the `:77` "Existing tags" list to match reality (`git tag -l` at fix time: add v1.3.1, v1.4.0, v1.4.1, v1.5.0; do NOT list v1.5.1 — no tag exists this cycle, see Push guidance). Keep the "Current version" line consistent with whatever `pubspec.yaml:4` holds at commit time.
- **Size + check classification:** **light**, **CHEAP**. Sizing reason: doc edits only, zero `lib/` delta. No e2e.
- **Acceptance criteria:** the tags list equals the actual `git tag -l` output at commit time; no other `docs/` changes; C27/28/29 closure docs NOT written (slot only).
- **Verification:** CHEAP — folds into the Reviewer pass.
- **Dependencies / sequencing:** after P1 (so the commit-2 diff is stable).
- **Expected result:** docs truthful; the ride-along slot recorded.

## Push guidance (FINAL — version bump patch, tag cut DEFERRED)

- Commit 1: `fix(auth): OR-gate the device-credential pre-probe so PIN-only devices get the prompt` — P1's lib + test files. Never root-wide `git add -A`.
- Commit 2: `docs(plans): cycle-32 plan + versioning tags list` — this plan file + `docs/versioning.md` (P2) + the `plans/done/cycle-31-...md` staged rename if still uncommitted. Exclusions reaffirmed: all `.opencode/` churn; `test/e2e_evidence/` (archive locally, never commit); `plans/agenta-landing-design-spec.md` + `plans/done/agenta-landing-redesign.md` (unrelated — explicit adds only, NEVER a bare `git add plans/`); `analysis_options.yaml` must show zero diff.
- Commit 3 (LAST): `chore(release): bump version to 1.5.1+1 (C32)` — `pubspec.yaml:4` version line ONLY. Precedent: cycle-31's `3b3c5d8`.
- **Tag cut DEFERRED:** no `v1.5.1` tag or GitHub release this cycle. Reason: the C27/28/29 Part B evidence is the user's on-device v1.4.1 → v1.5.0 hop, not yet confirmed; cutting v1.5.1 now would blur the hop trail and create a pubspec-vs-latest-release drift with zero user benefit. Cut `v1.5.1` only after the user confirms the v1.5.0 hop (then it becomes that closure's own release step) or on explicit user request. Main-push CI (Build APK + Promote to Landing) runs normally on `1.5.1+1`; the in-app update feed (GitHub `/releases/latest`) stays v1.5.0 until the tag exists — a self-healing intermediate state.
- Version bump: **patch 1.5.1+1, FINAL** (header). The push agent must not re-decide.

## Post-push CI watch (definitive acceptance)

- Build APK + Promote to Landing on main must conclude green at the push commit. Failure class to name if red: Dart compile errors from the new predicate, or unit-test regressions in the auth layer — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase scopes to the specific failure.
- TWO runs green (not four — no tag cut this cycle) = the push is SHIPPED. On green: Adviser marks the plan `done`, moves to `plans/done/`. The C27/28/29 closure slot stays open pending the user's device confirmation.

## Reviewer web searches

1. `local_auth flutter canCheckBiometrics isDeviceSupported OR device capabilities` — verifies the vendor OR-gate recommendation this cycle implements.
2. `local_auth android isDeviceSupported isDeviceSecure keyguard device credential` — verifies the Android semantics claim (PIN-only → isDeviceSupported true, canCheckBiometrics false).
3. `supabase signInWithOtp create_user false non-existent user signups not allowed` — spot-checks the R4 refutation against vendor docs/discussions.

## Reviewer verification commands (single pass, after P1 + P2 + e2e)

1. Diff audit: `git status` / `git diff --stat` — exactly P1's four files + P2's `docs/versioning.md` + this plan file, nothing else; `login.dart` absent from the diff; `analysis_options.yaml` zero-diff.
2. Login-surface audit: read the `biometric_auth_service.dart` diff — only the NEW predicate added; `isSupported` body byte-identical; grep confirms its only consumers remain `login.dart:228` and `login.dart:838` plus the two swapped seams.
3. Predicate audit: the new predicate is exactly the OR of the two platform calls with the try/catch→false shape of `isSupported()`; both probes awaited (no short-circuit skip).
4. Regression audit: existing cycle-31 P3/P4/e2e gate tests pass unmodified (or with only import-level churn); the probe-true and probe-false flow rows both still hold.
5. Baseline gates: `flutter analyze` exit 0; `flutter test` all-pass (quote count vs cycle-31's 383-passed baseline); `dart format --output=none --set-exit-if-changed lib test` exit 0.
6. Docs audit: `git tag -l` output equals the `docs/versioning.md:77` tags list; `pubspec.yaml:4` = `1.5.1+1` in Commit 3 only; no `v1.5.1` tag pushed.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-27 | Cycle-32 opened from the cycle-31 closure residual. Ground truth verified first-hand (app sources + pinned pub-cache plugin sources, both platforms); web-research executed (pub.dev local_auth live + supabase/auth master otp.go); **wipe-at-10 RULED structurally dead code — no account-loss risk, OR-gate stays primary (W1 recorded)**; **R4 RULED refuted** (422 for non-existent email; hosted-version caveat recorded; no action); N3 stays held; N4b (tags list) taken as P2; C27/28/29 not closed (slot only). Level 3 (auth surface); version patch 1.5.1+1 FINAL, tag cut deferred; contract: none. Plan created `active`. |
| 2026-10-27 | Single Reviewer pass: **PASS, NO CHANGE NEEDED — 8/8 acceptance criteria** (P1 5/5, P2 3/3). Gates re-run first-hand: `flutter analyze` 0, `dart format` 0 changed, `flutter test` 397 passed / 1 expected skip (+14 = the OR-gate file, reconciled vs the 383 baseline); OR-gate file re-run 14/14 first-hand. Searches 3/3 cited (local_auth 3.0.2 README OR-gate = vendor-recommended pattern, matches implementation; pinned plugin sources: Android `isDeviceSupported()` true on PIN-only / `canCheckBiometrics` false on no-hardware / `authenticate()` gates on `isDeviceSupported()` alone → the AND probe was the sole blocker; iOS darwin semantics likewise; supabase `otp.go` re-fetched, re-confirms the R4 refutation — 422 `OTPDisabled`, no silent success). Rulings: S1 fixture deviation ACCEPTED (required correction — the plan's "tests pass unmodified" was jointly unsatisfiable with its own criteria; assertions byte-preserved) riding Commit 1; S2 dual-await OR correct (short-circuit excluded by the plan's own step; lock test discriminates); blast radius pinned (`login.dart` absent from diff, `isSupported` byte-identical, `_offerBiometricEnroll` unchanged); C27/28/29 slot untouched; e2e-on-general routing = governance note. Recorded this pass: **N9 added to backlog** (local_auth_android 2.3.0 vs pin 2.2.0); docs current-version line trails pubspec by one patch post-Commit-3 (transitional by design — refresh when v1.5.1 is cut, not now: at Commit-2 time pubspec still says 1.5.0+1); Android plugin path nit (`kotlin/` vs `java/`) record-only. **Push authorized** — patch 1.5.1+1 FINAL, 3 commits with the plan's exact messages, tag cut DEFERRED until the user confirms the v1.5.0 on-device hop. Plan stays `active` until TWO CI runs (Build APK + Promote) are green. |
