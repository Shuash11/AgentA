# Cycle 30 — Remove the Recovery-Code Password-Change Gate (audit output: "offline forgot password")

**status:** active
**created:** 2026-10-24
**created by:** Adviser (user audit request — forgot-password best practice + "remove the offline forgot password")
**repo:** C:\projects\aiproject (AgentA) — Flutter, branch main
**level:** 3 (Complex) — touches the auth factor set for password change; single repo, no contract/schema change
**version bump:** none (folds into active release-v1.2.5; final, push agent must not re-decide)

## Ground truth (verified 2026-10-24)

**Terminology ruling:** there is NO offline password reset in this app. Nothing that changes a password works offline. What the user calls the "offline forgot password" is the recovery-code gate that sits in front of the in-app password change. Two separate systems exist:

| System | Entry point | Flow | Works offline? |
|---|---|---|---|
| Cloud forgot password | `login.dart:1090-1092` "Forgot Password?" → `login.dart:912-915` → `ForgotPasswordScreen` (`forgot_password.dart`) | email → `AuthService.sendOtpForReset` (`auth_service.dart:538-541`, `signInWithOtp(shouldCreateUser: false)` sends 6-digit OTP) → `resetPasswordWithOtp` (`auth_service.dart:548-563`, `verifyOTP(type: email)` then `updatePassword`) → `signOutOnly()` → back to login | NO — fails with generic error offline (`forgot_password.dart:87-94`) |
| Recovery-code gate → password change | `profilepage.dart:407-417` "Change Password" tile → `RecoveryCodePage` (`confirmation.dart:15-147`) → `ChangePasswordPage` (`change_pass_page.dart`) | enter recovery code → `UserRepository.verifyRecoveryCode` (`user_repository.dart:96-98` → `:82-94`, SHA-256 compare client-side against `profiles.recovery_code`) → `ChangePasswordPage` requires internet (`change_pass_page.dart:32-39`), `reauthenticate` + `updatePassword` (`:50-54`) | NO — both stages need Supabase |

**Supporting facts, each verified:**

- `RecoveryCodePage` has exactly ONE consumer: `profilepage.dart:413`. No unauthenticated entry point exists anywhere.
- `UserRepository.verifyRecoveryCode` has exactly ONE consumer: `confirmation.dart:11` (`RecoveryCodeService.verifyCode`).
- Dead code in `securityservice.dart`: `generateRecoveryCode` (:9), `getRecoveryCodeHash` (:21), `verifyRecoveryCode` (:39) — zero consumers (grep-verified 2026-10-24). Only `deleteAccount` (:45) is live, used by `securitypage.dart:80`.
- `SecurityPage` "View Recovery Code" copy references "the recovery screen" (`securitypage.dart:34`) — the screen this plan removes.
- Registration shows the recovery code once: `register.dart:56-64` (generator), `:78`, dialog copy "You'll need it to change your password" (`register.dart:621`). Hash stored via `RecoveryCodeHasher.hash` (`register.dart:162`, `recovery_code_hasher.dart:12-14` — unsalted SHA-256, 32^6 ≈ 30 bits of entropy).
- The offline-account claim path carries the recovery hash (`login.dart:505,544-549,571`) — it does NOT use the recovery code for proof; proof is the local Argon2id password hash (`login.dart:490-500`).
- `change_pass_page.dart` already enforces OWASP's change-password requirements on its own: active session + current-password verification via `AuthService.reauthenticate` (`:50-53`) — a fresh `signInWithPassword` against Supabase.
- Local/offline credential system (NOT touched by this plan): offline login fallback with `PasswordHasher.verifyPassword` (Argon2id PHC, cycle-10) + `OfflineLoginGuard` rate-limit/wipe (`login.dart:399-454`), offline account creation (`register.dart:95-103,156-170`), claim path (`login.dart:475-585`), biometric unlock (`login.dart:814-834`). All live, hardened, and load-bearing for the offline-first product.
- Tests touching the recovery surface: `test/smoke_test.dart:94-100` (`RecoveryCodeHasher` roundtrip — stays), `test/local_user_dao_upgrade_test.dart:25,40` and `test/sync_service_test.dart:191` (local test-schema `recovery_code` columns — stay, the column is not dropped). No widget test references `RecoveryCodePage`.
- gotrue version context: `auth_service.dart:545` comments cite gotrue 2.27.2 (`verifyOTP` has no `password` parameter).

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **R1** | **Recovery-code gate before password change is redundant and removable.** An authenticated user must enter a recovery code (verified client-side, unsalted SHA-256) AND then their current password — the code adds no security per OWASP (change-password requires active session + current-password verification, both already enforced by `change_pass_page.dart:50-53`), only friction. Its removal also deletes the weakest crypto on the active surface (30-bit unsalted SHA-256 client-side compare) and dead code (`securityservice.dart` ×3). **SELECTED as the cycle-30 task.** | security / UX | `profilepage.dart:413`; `confirmation.dart`; `securityservice.dart:9,21,39`; `change_pass_page.dart:50-53` | middle-end | **EXPENSIVE** |
| R2 | **Forgot-password flow lacks a post-reset notification email.** OWASP Forgot Password Cheat Sheet: "Send the user an email informing them that their password has been reset." Supabase does not send one by default for `updateUser` — Dashboard config / custom SMTP territory. | security | OWASP Forgot Password Cheat Sheet (User Resets Password section, fetched 2026-10-24); `auth_service.dart:528-534` (dashboard-config TODO) | user action / backend (when unblocked) | EXPENSIVE (cloud) |
| R3 | **No cross-device session invalidation after reset.** OWASP: "Ask the user if they want to invalidate all of their existing sessions, or invalidate the sessions automatically." App signs out only the reset-created session (`forgot_password.dart:120`). Other devices' sessions survive a reset. Separate cycle if pursued; needs Supabase support verification (gotrue session list/revoke API — unverified). | security | `forgot_password.dart:114-120`; OWASP Forgot Password Cheat Sheet | middle-end | EXPENSIVE |
| R4 | **UNVERIFIED: `signInWithOtp` behavior for non-existent emails.** If GoTrue succeeds silently with `shouldCreateUser: false` for an unknown email, the UI advances to the OTP stage and claims "OTP sent!" (`forgot_password.dart:70-74`) when no email exists — enumeration-adjacent UX and a false-positive success state. Supabase documents this silent-success behavior for `resetPasswordForEmail` (its canonical reset flow) but not for `signInWithOtp`. Verify against the pinned gotrue source before acting. | security / UX | `forgot_password.dart:67-86`; Supabase docs (Resetting a password note, fetched 2026-10-24); claim UNVERIFIED | middle-end | CHEAP (verification pass) |
| R5 | **Recovery-code storage is unsalted fast-hash, client-verified (H8/F5).** 30-bit code hashed with plain SHA-256, compared client-side against a `profiles.recovery_code` row any session can read. Blast radius is low today (no unauthenticated consumer after R1 lands), but the H8 target — server-side `verify_recovery_code` RPC — remains undeployed. Standing cloud-blocked escalation (F5, 10+ cycles). Only matters if a future unauthenticated recovery flow consumes the code. | security | `recovery_code_hasher.dart:12-14`; `user_repository.dart:11-14,82-94`; cycle-10 backlog F5 | backend / user action | EXPENSIVE (cloud) |
| R6 | Optional improvement, NOT in scope: Supabase now supports `updateUser({password, current_password})` (supabase-js v2.102.0+; Dart support unverified for the pinned gotrue 2.27.3 — `pubspec.lock:522`; the `auth_service.dart:545` comment cites 2.27.2) which would replace the `reauthenticate` + `updatePassword` pair with a single server-verified call. Verify Dart client support before considering. | security / logic | `change_pass_page.dart:50-54`; Supabase docs "Verifying the current password" (fetched 2026-10-24) | middle-end | EXPENSIVE |
| R7 | Cycle-10 backlog carryovers unchanged: F11 part 3 (bloc 9 + lints 6), F11 part 4 (^11 fss, gated on next release tag), F13 (HttpClient per probe), F18 (Gradle/AGP below warn thresholds), F4/F5/F12 (cloud-blocked). Tracked in `plans/done/cycle-10-password-hash-hardening.md:26-32`. | maintainability / CI | cycle-10 plan | middle-end / backend | EXPENSIVE |

Ranking rationale: R1 is the user's direct ask, is fully unblocked (no cloud dependency), removes both a UX friction point and dead/weak crypto, and is small. R2–R5 are cloud-dependent or verification-gated; R4's verification rides P1 of this cycle for free (one source read).

## Selected task (single)

**Audit rulings (recorded for the audit trail):**

1. **"Is forgot password best practice?"** — The cloud flow substantially follows current practice per OWASP Forgot Password + Authentication cheat sheets and Supabase docs (fetched 2026-10-24): side-channel 6-digit code, `shouldCreateUser: false`, generic error copy, no auto-login (sign-out after reset per OWASP "Don't automatically log the user in"), server-side rate limits. Named gaps go to the backlog (R2, R3, R4). The offline local-credential system is NOT a best-practice violation: OWASP explicitly lists "Offline methods" as a legitimate recovery category while requiring backend authentication for legitimacy — satisfied here (offline login only unlocks the local experience; the claim path proves ownership via the same Argon2id hash before creating a cloud account).
2. **"Can we remove the offline forgot password?"** — Reframed: there is no offline password reset to remove. The removable piece is the recovery-code gate (R1). The offline LOGIN/credential system must STAY — offline-first is core product; removing it would lock out offline-created accounts and break the claim path, biometric unlock, and the offline model.

**Objective:** "Change Password" in the profile routes directly to `ChangePasswordPage`; the recovery-code gate, its service, the dead `SecurityService` recovery methods, and the two now-false copy strings are removed. Password-change security posture is unchanged or improved (the authoritative check — active session + current password via Supabase reauthenticate — is untouched; a weaker client-side check is deleted).

**Version bump decision: none** — the change rides the active `plans/release-v1.2.5.md` release cycle per docs/versioning.md; no separate tag. Final; the push agent must not re-decide.

**Contract implications: none** — no API shape, status code, or error shape changes; no Supabase schema change (`profiles.recovery_code` column stays; claim path still writes it). `contracts/update-engine.yaml` is unaffected. No contractor phase required.

**ORCHESTRATION RULE (binding, mirrors cycles 7/9/10 user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run ONCE each over the whole plan — P2 is EXPENSIVE (auth-surface behavior change), so the e2e run IS REQUIRED before the single review pass. Definitive acceptance = post-push CI watch.

**STOP RULE (binding):** if P1's threat model finds any path where removing the gate enables a password change that was not previously possible (e.g., a state where the recovery code was the only working proof), P1 ends in STOP: no code change in P2, evidence recorded, Adviser re-scopes.

## Phase 1 — Design of record + security threat model (read-only)

- **Phase id:** P1
- **Objective:** a written design-of-record and threat model proving the removal cannot enable a password change that was not previously possible — or an honest STOP.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only evidence pass; findings recorded in this plan's Backlog governance table)
- **Size + check classification:** **light** (read-only, single-source verification pass), **CHEAP** (no behavior touched). Sizing reason: one agent, no file changes; it earns no e2e run.
- **Implementation steps:**
  1. Threat model: enumerate every path to `AuthService.updatePassword` (grep-verified: `change_pass_page.dart:54`, `auth_service.dart:562` from `resetPasswordWithOtp`). For each, state what authenticates it today and after removal. Confirm: in-app change = active session + current password (Supabase `signInWithPassword` reauthenticate, `change_pass_page.dart:50-53`); reset = server-verified OTP. Confirm the recovery code was never the sole proof on any path (it gates nothing authoritative: `UserRepository.verifyRecoveryCode` returns a bool that only `RecoveryCodePage._verify` consumes).
  2. Confirm R4 (unverified `signInWithOtp` non-existent-email behavior) against the gotrue version pinned in `pubspec.lock` — one source read; record the finding either way. Do NOT fix it in this cycle.
  3. Decide the fate of registration recovery-code generation: **recommended keep** (`register.dart:56-64,78,162` generation + storage stays; only the two copy strings change) so the code remains a stored account-ownership artifact for a future unauthenticated recovery flow (R5 context). Alternative (remove fully) rejected: it touches the claim path, `LocalUserDao` preservation logic (`local_user_dao.dart:18-25`), and the user model — larger blast radius for zero current value.
  4. Fix the two copy strings in the design: `securitypage.dart:34` ("Use it on the recovery screen" → code is stored, cannot be displayed, usable for account verification if ever needed) and `register.dart:621` ("You'll need it to change your password" → no longer true; replace with safe-storage wording only).
  5. Enumerate the exact P2 diff surface (the file list below) and confirm nothing else references the deleted symbols (`RecoveryCodePage`, `RecoveryCodeService`, `SecurityService.generateRecoveryCode`, `SecurityService.getRecoveryCodeHash`, `SecurityService.verifyRecoveryCode`).
- **Acceptance criteria:** threat-model table written with a per-path before/after authentication statement; R4 finding recorded with its source; generation-fate decision recorded with rationale; copy replacements drafted; P2 file list confirmed against grep. Or STOP with the specific gap.
- **Verification:** CHEAP — read-only; Reviewer confirms the table against the cited lines.
- **Dependencies / sequencing:** first; P2 executes only a clean design (STOP forbids P2).
- **Expected result:** P2 fully determined; zero ambiguity for the implementing agent.

## Phase 2 — Implement gate removal + dead-code cleanup + copy fixes

- **Phase id:** P2
- **Objective:** the exact behavior described in the objective — gate gone, dead code gone, copies truthful, zero dangling references, gates green.
- **Responsible subagent:** middle-end
- **Size + check classification:** **heavy**, **EXPENSIVE**. Sizing reason: auth-surface behavior change + more than two files + deleted file (work-sizing heavy signals: auth; >2 files; behavior). The e2e run IS REQUIRED before the Reviewer gate (orchestration rule above).
- **Files to change:**
  1. **DELETE** `lib/presentation/profile/confirmation.dart` — the file contains ONLY `RecoveryCodeService` (:9-13) and `RecoveryCodePage` (:15-147); nothing else lives there.
  2. `lib/presentation/profile/profilepage.dart` — line 18: `import 'confirmation.dart';` → `import 'change_pass_page.dart';`; lines 407-417: "Change Password" tile pushes `const ChangePasswordPage()` instead of `const RecoveryCodePage()`.
  3. `lib/presentation/profile/securityservice.dart` — delete `generateRecoveryCode` (:9-17), `getRecoveryCodeHash` incl. its doc comment (:19-35), `verifyRecoveryCode` incl. its doc comment (:37-43), and the two imports that become unused: `dart:math` (:2 — only the deleted `generateRecoveryCode` used `Random.secure`) and `recovery_code_hasher.dart` (:4 — only the deleted `verifyRecoveryCode` used `RecoveryCodeHasher`). KEEP `deleteAccount` (:45-56) and its imports (:1, :3) — used by `securitypage.dart:80`.
  4. `lib/presentation/profile/securitypage.dart` — line 34 dialog copy: remove "Use it on the recovery screen — " (the screen no longer exists). Approved final string (P1, Adviser-ratified 2026-10-24): `'For your security, the raw code was shown once at sign-up and only its hash is stored. It cannot be displayed again.'`
  5. `lib/presentation/auth/register.dart` — line 621 dialog copy: replace the second line so the full string reads `"Store this code somewhere safe.\nIt is not used to change your password."` — Adviser-approved 2026-10-24, amended from P1's draft: the "It's shown once" clause is dropped as redundant with the dialog's existing one-time notice (`register.dart:716-719`). Everything else in the dialog stays (offline banner :643-677, one-time notice :716-719).
- **Implementation steps:**
  1. Re-verify with grep that `confirmation.dart` is imported only by `profilepage.dart` and that the five deleted symbols have zero other references (current evidence says so; confirm at implementation time).
  2. Apply the five file changes above. No logic changes anywhere else; no schema change; `register.dart` generation/storage untouched (P1 decision).
  3. Tests: no existing test references the deleted symbols (verified: `test/` grep 2026-10-24). The `recovery_code` columns in `test/local_user_dao_upgrade_test.dart:25` and `test/sync_service_test.dart:191` and the `RecoveryCodeHasher` group in `test/smoke_test.dart:94-100` STAY (column and hasher remain). If `flutter test` count changes, report the delta explicitly.
  4. Local gates: `flutter analyze` exit 0 (strict lints — this also proves no unused imports remain), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` all pass.
  5. STOP-and-revert on any non-mechanical gap (fallback rule).
- **Acceptance criteria (each individually checkable):**
  - `lib/presentation/profile/confirmation.dart` does not exist.
  - `grep -r "RecoveryCodePage\|RecoveryCodeService\|SecurityService.verifyRecoveryCode\|SecurityService.generateRecoveryCode\|SecurityService.getRecoveryCodeHash" lib/ test/` returns zero hits.
  - The "Change Password" tile in `profilepage.dart` pushes `ChangePasswordPage` (read the diff).
  - Offline users still see the "Changing password needs internet" notice in `change_pass_page.dart:32-39` (unchanged).
  - `securitypage.dart` and `register.dart` contain no sentence claiming the code is used to change the password.
  - All three local gates exit 0.
- **Verification:** EXPENSIVE — behavior change on the password-change path. e2e-tester (once, whole plan): logged-in online user → Profile → Change Password lands directly on ChangePasswordPage; entering current + new password changes it; offline path still blocks with the notice; registration still shows the one-time code dialog with the corrected copy.
- **Dependencies / sequencing:** after P1's clean design (STOP forbids P2). No contract phase exists or is needed.
- **Expected result:** the recovery-code gate is gone; password-change posture unchanged (session + current password); dead code removed; copies truthful.

## Phase 3 — Test-asset + design-doc hygiene (post-e2e, pre-Reviewer)

- **Phase id:** P3
- **Objective:** the e2e-tester's regression artifact is push-ready (no cross-OS golden coupling, format-clean) and the design-of-record no longer references the deleted screen. Rulings 3 and 4 of 2026-10-24 executed.
- **Responsible subagent:** middle-end-light
- **Size + check classification:** **light**, **CHEAP**. Sizing reason: test-file + doc edits only, zero `lib/` delta, no app behavior touched — earns no e2e run (cheap check) and no separate review (it folds into the single owed Reviewer pass).
- **Files to change:**
  1. `test/cycle30_shard_b_e2e_test.dart` — delete the two `await expectLater(find.byType(MaterialApp), matchesGoldenFile(...))` blocks (the S1 block after the notice assertions, currently :168-171; the S3 block after the dialog-copy assertions, currently :200-203); amend the header comment's run line (:21-22) to drop "writes screenshot evidence" and `--update-goldens`; run `dart format` on the file (it currently FAILS format — Adviser-verified EXIT=1, trailing blank lines). Everything else stays exactly as the tester left it: real cubit/dao/hasher wiring, the three live states, state 2's `skip: true` with its in-file reason.
  2. `docs/design/ui-redesign-spec.md` :257 — delete the `profile/confirmation.dart` table row (the screen no longer exists; `ChangePasswordPage` already has its own spec coverage elsewhere in the doc).
  3. `docs/design/neumorphism-spec.md` :152 — delete the `profile/confirmation.dart` inventory bullet.
  4. DELETE `test/goldens/cycle30_offline_change_password_block.png` and `test/goldens/cycle30_security_recovery_dialog.png` from the working tree AFTER archiving copies to `C:\Users\joashua\AppData\Local\Temp\opencode\cycle30-goldens\`. They are NEVER committed (see Push guidance).
- **Why (evidence, verified 2026-10-24):** CI runs `flutter test` and `dart format --set-exit-if-changed lib test` on **ubuntu-latest** and hard-fails on any failure (`.github/workflows/build-apk.yml:21`, `:233-234`, `:259-273`). The goldens were captured on Windows in the flutter_test fallback font (the tester's own S5 finding) — pixel output is not reproducible on Linux, so committing them is a near-certain red CI, which the plan's definitive-acceptance gate forbids. The copy proof stands on the exact-text assertions (the tester's own statement). No golden-test infrastructure exists anywhere else in the repo (glob-verified) — this cycle does not introduce the first one.
- **Implementation steps:** archive the goldens to the temp path above → apply edits 1-3 → `dart format test/cycle30_shard_b_e2e_test.dart` → delete `test/goldens/` → run the gates below → report the six checks.
- **Acceptance criteria (each individually checkable):**
  - `matchesGoldenFile` appears zero times in `test/cycle30_shard_b_e2e_test.dart`.
  - `test/goldens/` does not exist in the working tree.
  - `grep -r "confirmation.dart" docs/design/` returns zero hits.
  - `dart format --output=none --set-exit-if-changed lib test` exits 0.
  - `flutter test test/cycle30_shard_b_e2e_test.dart` reports 3 passed, 1 skipped (the recorded S2 harness limitation).
  - `flutter analyze` exits 0.
- **Verification:** CHEAP — the six checks above, recorded in the governance table. No e2e, no separate review.
- **Dependencies / sequencing:** after P2 (DONE); before the Reviewer pass.
- **Expected result:** push-ready regression artifact, truthful design specs, working tree containing only the intended push surface.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `refactor(auth): remove redundant recovery-code gate before password change (R1)` — exact type per the final diff character (deletion + navigation + copy; `refactor` fits unless the Reviewer argues `feat`/`fix`). Stage the five `lib/` changes PLUS the P3-amended `test/cycle30_shard_b_e2e_test.dart` (the cycle's regression artifact; AMENDED 2026-10-24 per Ruling 3). NEVER the goldens.
- Commit 2: `docs(plans): cycle-30 plan + e2e gate record; cycle-28 governance catch-up` — stage `plans/cycle-30-recovery-code-gate-removal.md` AND `plans/cycle-28-in-app-update-flow.md` (its uncommitted 2026-10-19 governance rows — P8 ruling, premise correction, e2e Part A + Reviewer pass, cycle-29 routing — verified in the working diff; recorded governance belongs in the repo record). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn; `test/goldens/` (archived out of the tree in P3, never committed); `plans/agenta-landing-design-spec.md` and `plans/done/agenta-landing-redesign.md` (a DIFFERENT task's artifacts — excluded from cycle-30 pushes); `analysis_options.yaml` is committed state (any local diff = stop and report).
- Version bump: none (see Selected task).

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — strict-lint analyze + tests + APK build. Failure class to name if red: Dart compile errors from the deletion (unresolved imports/references) — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase scopes to the dangling reference.
- **Promote to Landing** green as usual.
- On green: Adviser marks the plan `done`, moves to `plans/done/`.

## Reviewer web searches

1. `OWASP Forgot Password cheat sheet user resets password current password` (cheatsheetseries.owasp.org — confirms the change-password requirements the post-removal flow must satisfy: active session + current-password verification).
2. `NIST SP 800-63B-4 account recovery assurance authenticator` (pages.nist.gov — context that removing a redundant recovery factor does not lower authenticator assurance below the required level).
3. `Supabase updateUser current_password dart gotrue` (supabase.com/docs — verifies the R6 backlog claim about `current_password` support; record what it says for the Dart client, do not implement).

### Waived-shard special treatment (Adviser directive to the Reviewer, 2026-10-24)

Shard A (the online password-change e2e) was WAIVED by user directive — recorded in the governance table. The executable evidence for the primary changed behavior therefore does not exist; the Reviewer compensates statically and names this explicitly in its report:

1. Treat the routing diff (`profilepage.dart`: import swap + tile → `ChangePasswordPage`) as the highest-scrutiny item; read it line-by-line (command 3) and confirm no other code path still references the deleted symbols.
2. Confirm `change_pass_page.dart` is byte-untouched (absent from `git diff`) — the online happy path runs unchanged, already-tested code.
3. Confirm `register.dart`'s diff is the single line-~621 hunk (lines 157-175 — the S2 BLOCKED region — untouched).
4. Run the shard-B file (folded into command 5) and report the skip as the EXPECTED S2 harness limitation, not a failure.
5. Name the residuals verbatim in its report: the online password-change path was never e2e-executed; the registration corrected copy is not regression-locked by a running test; the full LoginPage offline-unlock UI was not exercised; the fallback-font goldens were not typography evidence.

## Reviewer verification commands (single pass, after P1+P2+P3 + e2e)

1. Deletion audit: `git status` / `git diff --stat` — `confirmation.dart` deleted; exactly the five P2 `lib/` changes plus the P3-amended `test/cycle30_shard_b_e2e_test.dart` (commit 1) and the two plan files + two P3 doc-row deletions (commit 2), nothing else; no `test/goldens/` anywhere.
2. Dangling-reference audit: grep the five deleted symbol names across `lib/` and `test/` — zero hits; PLUS `grep -r "confirmation.dart" docs/design/` — zero hits (P3).
3. Posture audit: read `change_pass_page.dart:50-54` — the reauthenticate + updatePassword pair is byte-unchanged; read `profilepage.dart` diff — tile now routes to `ChangePasswordPage`.
4. Copy audit: `securitypage.dart` and `register.dart` contain no "use it to change your password" claim; registration dialog otherwise unchanged.
5. Baseline gates: `flutter analyze` exit 0 (strict lints), `flutter test` all-pass (quote count vs the pre-cycle count; the cycle-30 shard file contributes 3 passed + 1 skipped — the skip is the recorded S2 harness limitation, EXPECTED), `dart format --output=none --set-exit-if-changed lib test` exit 0.
6. Threat-model audit: P1's before/after table covers every `updatePassword` call site (`change_pass_page.dart:54`, `auth_service.dart:562`) with an authentication statement.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-24 | Cycle-30 audit recorded (user questions: forgot-password best practice; remove "offline forgot password"). Ruling: no offline password reset exists; the removable piece is the recovery-code gate (R1). Plan created `active`; level 3 (auth factor set change); version bump none; no contract impact. R4 recorded as UNVERIFIED pending the pinned-gotrue source check in P1. |
| 2026-10-24 | **P1 complete — verdict CLEAN, STOP not triggered.** Adviser re-verified every claim against source before recording (not taken on report). Threat model: exactly 2 `updatePassword` paths — `change_pass_page.dart:54` (in-app; active session + current-password reauthenticate, `change_pass_page.dart:50-53` → `auth_service.dart:565-571`) and `auth_service.dart:562` (reset; server-verified OTP, `auth_service.dart:554-562`) — authentication identical before/after removal. `RecoveryCodeService.verifyCode` result only navigates (`confirmation.dart:41-48`); the recovery code never reached `updatePassword`. Adversarial check closes STOP: a session-holder could already bypass the gate (client-readable `profiles.recovery_code` hash → 30-bit unsalted SHA-256 offline crack → pass gate, per R5), so removal widens no real capability. R4: remains UNVERIFIED (pinned gotrue is 2.27.3 per `pubspec.lock:522`; server-side `signInWithOtp` silent-success not determinable from client source) — stays in backlog, no fix attempted, per plan. Generation: KEEP ratified (`register.dart:56-64`, :78, :162; `RecoveryCodeHasher`; `profiles.recovery_code` column). Copies: `securitypage.dart:34` ratified as drafted; `register.dart:621` approved with one amendment — "It's shown once" clause dropped as redundant with the dialog's existing one-time notice (`register.dart:716-719`); final strings recorded in P2 changes 4-5. P2 surface independently confirmed: `confirmation.dart` imported only by `profilepage.dart:18` and contains only the two deleted symbols; zero `test/` references to deleted symbols; `deleteAccount` stays (consumer `securitypage.dart:80`). Plan micro-fixes applied by Adviser (mechanical, no scope change): P2 change 3 gains the `dart:math` (:2) import deletion (only `Random.secure` in the deleted method used it) and doc-comment-inclusive ranges (:19-35, :37-43); P2 changes 4-5 gain exact approved strings; step 1 "four"→"five" deleted symbols; R6 gotrue citation corrected to pinned 2.27.3. Recorded for future cycles: `UserRepository.getRecoveryCodeHash`/`verifyRecoveryCodeViaRpc`/`verifyRecoveryCode` (`user_repository.dart:61,82,96`) become caller-less after P2 by decision — kept as the R5 future-recovery-flow artifact (public API, strict-lint analyze unaffected). **P2: GO** (heavy / EXPENSIVE / middle-end; e2e + Reviewer run once over the whole plan per the binding orchestration rule; version bump none — final). |
| 2026-10-24 | **E2E GATE CLOSED UNDER USER DIRECTIVE (shard A waived; shard B = the executed e2e evidence).** Two e2e delegation attempts hung/were cancelled; the user directed hard-termination timeouts and then, after the second run, "just trust the e2e tester-2" — recorded as the binding waiver of **SHARD A** (e2e-tester, the online password-change path: CANCELLED, never executed). **SHARD B** (e2e-tester-2, preserved surfaces) EXECUTED 20m15s of a 25m hard budget, honest report: S1 offline change-password block PASS (exact notice, no navigation, golden captured); S2 registration one-time dialog BLOCKED → classified **HARNESS LIMITATION, not an app defect** (pubspec has no `integration_test` — Adviser-verified from `pubspec.yaml` dev_dependencies; adding one was forbidden; under `flutter_test` the bounded 30s×3 deterministic wait expires between submit and `_showRecoveryCodeDialog`; P2 touched none of `register.dart:157-175` — single-hunk git diff verified); test left `skip: true` with the reason in-file; S3 security-page corrected copy + Delete Account flow PASS; S4 offline-login crypto spot-check PASS (narrow: `password_hasher_v2_test` 10/10 + in-shard Argon2id round-trip; full offline-unlock UI NOT executed); S5 visual evidence PARTIAL (goldens render in the flutter_test fallback font — copy proven by exact-text assertions, not pixels); zero processes alive at exit; two over-long diagnostics killed per protocol. Adviser re-verified the report against the tree before accepting: the 5-file diff is exactly the P2 scope (`git diff --stat`: register 1 line, confirmation −148, profilepage 4, securitypage 1, securityservice −38); `change_pass_page.dart` is byte-untouched (absent from git status); both goldens exist untracked. **RULING 2 (shard A residual risk: ACCEPTED — LOW):** P1's threat model proved authentication identical before/after on every `updatePassword` path (exactly 2: `change_pass_page.dart:54` in-app reauthenticate; `auth_service.dart:562` OTP reset) and `change_pass_page.dart` is byte-untouched, so the online happy path runs unchanged code already exercised by 323 green tests and prior dogfood; the only new online behavior is the 4-line `profilepage.dart` routing diff — statically auditable, CI-compiled, and exercised by shard B's offline drive of the same widget class; a residual wiring regression would surface in post-push dogfood. **RULING 3 (tester's three files: KEEP, AMENDED):** `test/cycle30_shard_b_e2e_test.dart` is kept as the cycle's regression artifact but loses its two `matchesGoldenFile` assertions and must be dart-formatted (both push-blocking, Adviser-verified: CI runs `flutter test` + `dart format --set-exit-if-changed lib test` on **ubuntu-latest** — `build-apk.yml:21,233-234,259-273` — and Windows fallback-font goldens are not reproducible on Linux → near-certain red CI, which the definitive-acceptance gate forbids; the file currently fails `dart format`, EXIT=1); the two PNGs are archived out of the tree and NEVER committed; the exact-text assertions remain the copy proof (the tester's own S5 statement). **RULING 4 (stale docs: FIX THIS CYCLE via new P3):** `ui-redesign-spec.md:257` + `neumorphism-spec.md:152` still reference the deleted `profile/confirmation.dart` — Adviser grep-verified these are the ONLY two stale doc refs; both entries deleted in P3. **Residuals feeding the Reviewer:** the online password-change path was never e2e-executed; the registration corrected copy is not regression-locked by a running test (S2 skipped); the full LoginPage offline-unlock UI was not exercised; the fallback-font goldens are not typography evidence. New **P3** (test-asset + design-doc hygiene, light/CHEAP) added below; the single Reviewer pass covers P1+P2+P3. |
| 2026-10-24 | **NEXT-GATES RULING:** **NO standalone UX-review gate** — the plan's binding orchestration rule (all phases first, no mid-plan gates, then e2e once → Reviewer once) declares no UX phase; P1 already produced the Adviser-ratified copy strings (the design of record) and shard B verified both rendered copies by exact text on the changed surfaces; a mid-plan UX gate would add undeclared process depth. **GO for the single Reviewer pass AFTER P3**, with the waived-shard special treatment below (Reviewer section). Push confirmation only after that PASS. |
- Cycle-31 pre-ranked: R3 (cross-device session invalidation after reset) if unblocked, else R7 carryover (F11 part 3 — bloc 9 + lints 6 pair).
- This plan is `done` only when P1+P2+P3 PASS review (after the required e2e run, closed under the user directive of 2026-10-24; or the STOP-deferral is recorded and the plan closes via Adviser re-scope), the push is Adviser-approved and executed, and BOTH workflows are green.
