# Cycle 9 — Secure-Storage Lattice (F11 part 2 / F21) — Data-Safe Migration

**status:** active
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 9 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 52d96b8
**predecessors:** plans/done/cycle-1..8 (all closed, CI green; latest runs 38331155451 / 38332174842)

## Cycle 9 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` (strict lints) | **"No issues found!" exit 0** — 9th consecutive clean cycle |
| `flutter test` | **208/208 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| Secure-storage blast radius | **2 files only**: `lib\services\auth\biometric_auth_service.dart` (import :2, instance :10 — biometric enabled-flag + uid keys) and `lib\services\auth\session_manager.dart` (import :2, instance :25 — session credentials / stashed password state) |
| The lattice (pub outdated, cycle-6/9 evidence) | flutter_secure_storage 9.2.4 → 11.2.0; flutter_secure_storage_windows 3.1.2 → 4.2.2; win32 5.15.0 → 6.4.0; package_info_plus 9.0.1 → 10.2.2; transitive discontinued flutter_secure_storage_macos + js resolve only past this lattice |
| Data-loss warning (cycle-6 research, to be re-verified in P1) | fss 9→11 direct jump "can LOSE DATA — data saved using deprecated algorithms/features unusable"; explicit 9→10 upgrade step documented; 11.1.0 adds `checkUpgradeStatus()` reporting loss |
| CI | runs 38331155451 / 38332174842 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F21 / F11 part 2** | **The secure-storage lattice.** Breaking it: resolves 2 discontinued transitives (macos, js), moves the credentials stack onto maintained code (fss 11.2.0, fss_windows 4.2.2, win32 6.4.0), and unblocks package_info_plus 10.2.2. **Carries REAL user-data-loss risk** — secure storage holds biometric state, uid, and session credentials; the documented 9→11 jump can lose data. **SELECTED as the cycle-9 task** — with the mandated evidence-first design and a binding STOP rule below. | maintainability / data-risk | pub outdated; 2-file usage inventory | middle-end | **EXPENSIVE** |
| **F11 part 3** | **Remaining blocked majors** (flutter_bloc 9.1.1, connectivity_plus 7.3.2, flutter_dotenv 6.0.1, cupertino_icons 2.0.0, flutter_lints 6.0.0, flutter_launcher_icons 0.14.4) — OUT of scope this cycle (separate constraint-edit cycles; keep the blast radius one lattice at a time). | maintainability | pub outdated | middle-end | EXPENSIVE |
| **F6** | **Local passwords = salted SHA-256** (no work factor); argon2 upgrade path documented ("minimum bar"). Deliberately sequenced AFTER the lattice: F6's new hash storage should land on the NEW secure-storage stack, not the old one (avoids doing the work twice). | security | lib/services/auth/password_hasher.dart | security | EXPENSIVE |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — deliberate deferral; AGP 9 + Built-in-Kotlin migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15 residue** | Duplicate-semver guard live (cycle 8); force-pushed never-released tags remain a process rule (documented). | CI | build-apk.yml guard | — | accepted |
| **F16 / F19** | promote-landing staleness fallback / zombie queued run — accepted, no action. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (9th cycle).** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: with 9 clean cycles and the cheap backlog exhausted, the biggest remaining debt is the lattice — and it gates F6's sequencing. The data-loss risk is real but the blast radius is 2 files, the migration has documented APIs (upgrade step + checkUpgradeStatus), and the STOP rule bounds the downside: if documentation alone cannot establish a safe migration, nothing ships and the evidence becomes the deferral record.

---

## Selected task (single): F11 part 2 / F21 — the secure-storage lattice, data-safe

**Objective:** [RULING 2026-10-13, P1-ratified — staged target] flutter_secure_storage **^10.3.4** + package_info_plus **^10.2.2** + win32 6.4.x (transitive) on maintained majors with **zero user data loss by design**: the 9→10 migration is AUTOMATIC on first access (`migrateOnAlgorithmChange: true`, default — no boot hook required for ^10), direct 9→11 is documented data loss ("upgrade to v10 first"), and the ^11 move (with the `checkUpgradeStatus()` boot hook, design already recorded in P1) is a **follow-up cheap cycle gated on a ^10 release shipping to users** (a user skipping the ^10 release and landing on ^11 from ^9 would hit the documented data-loss path — the staged rollout is the safety mechanism, so the ^11 cycle waits for the user to cut the next release tag). Verified by gates + e2e + CI.

**Version bump decision: none** — dependency maintenance is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **P2 is EXPENSIVE (runtime dependency + data behavior), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch.

**STOP RULE (binding, mirrors cycle 7's fallback):** if P1 cannot establish a safe migration from official documentation ALONE — i.e., the 9→10 upgrade step is undocumented, the direct 9→11 semantics are ambiguous, or checkUpgradeStatus()'s contract is unclear — P1 ends in STOP: **no constraint edit is made in P2**, the evidence and gaps are recorded in the plan, the Adviser re-scopes the cycle (deferral with evidence, or substitution). A migration whose safety rests on guesswork NEVER ships.

**RISK ACKNOWLEDGMENT (honest, plan-level):** gates prove compile + unit integrity; CI proves the build. **Real on-device data migration (existing users' stored credentials surviving the upgrade) is not gate-coverable** — same class as cycle 7's device-inference advisory. Non-gating advisory: after green, the user smoke-tests app upgrade-in-place on a device that has stored credentials (login state + biometric enroll) using the promoted APK. The 2-file blast radius and the boot-time integration point (P1 design) are the mitigations.

---

## Phase 1 — Data-migration evidence + staged-migration design (read-only)

- **Phase id:** P1
- **Objective:** a documentation-backed answer to "how do existing users' credentials survive 9→10→11" — or an honest STOP.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only evidence pass)
- **Implementation steps:**
  1. Usage inventory (finalize): every key written/read via the 2 `FlutterSecureStorage` instances (biometric `_enabledKey`/`_uidKey`; SessionManager's keys — enumerate from the source), what each stores, and which app flows depend on them (login persistence, biometric quick-unlock).
  2. Changelog research: flutter_secure_storage **9.x → 10.0.0** (the documented upgrade step — is it a runtime API call, an automatic migration, or an OS-level re-encryption?), **10.x → 11.0.0**, and **11.1.0's `checkUpgradeStatus()`** (exact contract: what it reports, when to call it, what a loss report means).
  3. Determine **direct 9→11 vs staged**: does 11.0.0/11.1.0 perform the 10.0.0 migration automatically on first access, or must users pass through 10.x in a prior release? Cite the changelog lines verbatim.
  4. Windows/lattice check: confirm flutter_secure_storage_windows 4.2.2's win32 constraint (satisfies 6.4.0) and that package_info_plus 10.2.2's win32 requirement aligns; confirm PackageInfo API stability 9→10 (VersionCheckService is the only consumer).
  5. Design the integration: WHERE the upgrade step / `checkUpgradeStatus()` call lives at boot (before AuthService/SessionManager first read — e.g., alongside AppConfig.init in main.dart), what happens on a loss report (log + degrade gracefully — biometric re-enroll + re-login, friendly per docs/error-hygiene.md), and the exact API sequence.
  6. Enumerate API breaks 9→11 for the 2 consumer files (options constructors, method signatures) — mechanical or not.
  7. **STOP decision:** if steps 2-3 leave the migration semantics ambiguous → STOP per the binding rule; record everything.
- **Acceptance criteria:** every question above answered with verbatim doc citations, or STOP declared with the specific gap.
- **Verification:** **CHEAP** — read-only; no e2e impact.
- **Dependencies / sequencing:** first; P2 executes only a clean design.
- **Expected result:** P2 fully determined, or an honest deferral.

## Phase 2 — Apply the lattice edit + migration integration

- **Phase id:** P2
- **Objective:** the app compiles, passes the full suite, and integrates the documented migration path on maintained storage majors.
- **Responsible subagent:** middle-end
- **Files to change:** `pubspec.yaml` (the 2 constraint lines **+ the now-false win32-pin comment block at :27-30** — [RULING: in scope, comment-only] after the move the documented conflict no longer exists; leaving it would be doc-drift), `pubspec.lock`, **the 2 consumer files are expected to have ZERO diff** (API surface unchanged in 10.3.4 — any consumer-file diff = STOP-and-report)
- **Implementation steps:**
  1. Constraint edits strictly per the ratified design: `flutter_secure_storage` → `^10.3.4`, `package_info_plus` → `^10.2.2`. NO other constraints touched (flutter_bloc 9, connectivity_plus 7, dotenv 6, lints 6, cupertino_icons 2, launcher_icons 0.14 stay queued — F11 part 3).
  2. Update the pubspec.yaml win32-pin comment (:27-30) to state the new fact: the lattice conflict is resolved — fss 10.3.4 / fss_windows 4.2.x ride win32 6.x; package_info_plus 10.2.2. Comment-only.
  3. `flutter pub upgrade` the touched set; verify the lattice landed: fss_windows 4.2.x, win32 6.4.x, fss_macos + js GONE from the lock (F21 resolved).
  4. **NO code adaptations, NO boot hook, NO `migrateWithBackup`** [RULING: option (ii) excluded — see backlog governance]: auto-migration runs via the default `migrateOnAlgorithmChange: true` on first access; graceful-degradation paths (re-login / biometric re-enroll, friendly per docs/error-hygiene.md) already cover the loss case. The `migrateWithBackup` option is recorded as a candidate for the ^11 follow-up cycle, where its documented ambiguity gets fresh research.
  5. Update test mocks ONLY if the resolved API demands it (P1 says none expected — any mock diff = report explicitly).
  6. Local validation: `flutter analyze` exit 0, `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` all pass.
  7. **STOP-and-revert on any non-mechanical gap** (fallback rule).
- **Acceptance criteria:** pubspec.yaml = the 2 constraint lines + comment-only pin-comment update, nothing else; lattice post-state verified (fss 10.3.4, fss_windows 4.2.x, win32 6.4.x, package_info_plus 10.2.2, macos/js resolved); **zero diffs in the 2 consumer files**; gates green.
- **Verification:** **EXPENSIVE** — runtime dependency + data behavior. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: analyze ×2 exit 0, 208/208, format 0, lattice greps, `pub get --enforce-lockfile` idempotent.
- **Dependencies / sequencing:** after P1's clean design (STOP forbids P2).
- **Expected result:** the credentials stack on maintained majors; both discontinued transitives resolved; F11 part 2 closed (part 3 remains queued).

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `build(deps): move secure-storage lattice to maintained majors (fss 9→<target>, win32 6, package_info_plus 10)` — pubspec.yaml, pubspec.lock, the adaptation files (single atomic commit: constraints + their required code changes must never be split — a constraints-only commit would be a known-red state).
- Commit 2 (conditional, cycle-6 rule): `chore: regenerate plugin registrants to match updated dependencies` — ONLY if registrant diffs exist at push time; otherwise SKIP.
- Commit 3: `docs(plans): close cycle 8 and open cycle 9 plan` — stage `plans/` explicitly (deletion of old cycle-8 path, `plans/done/cycle-8-...md`, new cycle-9 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); no other pubspec constraints.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — the runner compiles the new storage stack (fss_windows 4.x / win32 6.x Android side is unaffected by win32 — that's Windows-desktop; Android fss artifacts are the ones exercised). Guards + format gate + strict-lint analyze + 208/208 + APK build as in run 38331155451.
- **Promote to Landing** green as usual — the promoted APK is the upgrade-in-place smoke-test artifact for the device advisory.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase (likely scoped revert to the 9.x lattice + recorded gaps). Do not retry or fix autonomously.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-10 audit (pre-ranked: F6 password-hash hardening ON the new storage stack).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `flutter_secure_storage 10.0.0 changelog upgrade from 9 migration step` (pub.dev — the documented 9→10 upgrade procedure, verbatim).
2. `flutter_secure_storage 11.0.0 11.1.0 changelog checkUpgradeStatus` (pub.dev — the 10→11 changes + the checkUpgradeStatus contract).
3. `flutter_secure_storage_windows 4.2.2 win32 6 constraint` (pub.dev — the lattice link that makes win32 6.4.0 resolvable).
4. `package_info_plus 10.0.0 breaking changes` (pub.dev — validates the 9→10 PackageInfo API stability for VersionCheckService).

## Reviewer verification commands (single pass, after P1+P2)

1. `git diff pubspec.yaml` → exactly the 2 designed constraint lines **+ the comment-only pin-comment update** (nothing else).
2. Lattice greps on pubspec.lock [P1-adapted checklist, ratified]: **flutter_secure_storage == 10.3.4; flutter_secure_storage_windows == 4.2.x; win32 == 6.4.x; package_info_plus == 10.2.2; flutter_secure_storage_macos ABSENT; js ABSENT** (F21 resolved).
3. Migration-integration audit [adapted for the staged target]: **no boot hook required for ^10** (auto-migration via default `migrateOnAlgorithmChange: true`); the 2 consumer files show **zero diffs** (graceful-degradation paths verified as already present in source); the ^11 `checkUpgradeStatus()` hook design is recorded in P1's report for the follow-up cycle.
4. Baseline gates: `flutter analyze` exit 0 (strict lints), `flutter test` all-pass (quote count vs 208), `dart format --output=none --set-exit-if-changed lib test` exit 0; `flutter pub get --enforce-lockfile` idempotent.
5. Diff audit: no other constraints touched (flutter_bloc/connectivity_plus/dotenv/lints/cupertino_icons/launcher_icons unchanged); **any diff in biometric_auth_service.dart / session_manager.dart = STOP-and-report** (P1 says zero expected).
6. If P1 STOPped: verify clean revert (empty git diff) + recorded gaps in the plan. (Moot — P1 completed clean.)

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-9 audit recorded; plan created `active` (task F11 part 2 / F21). Blast radius established: 2 files. STOP rule + risk acknowledgment recorded. F6 deliberately sequenced after the lattice. |
| 2026-10-13 | **P1 COMPLETE (no STOP) + ADVISER SCOPE RULINGS.** P1 established from official docs + shipped 10.3.4 source: 9→10 migration automatic (`migrateOnAlgorithmChange: true` default), direct 9→11 documented data loss, `checkUpgradeStatus()` contract documented (11.1.0+, read-only, boot-before-first-access, Android-only), API surface unchanged in 10.3.4 (zero adaptations expected), 2-line constraint edit resolves the entire lattice. **Rulings (binding):** (1) **P2 TARGET ^10.3.4 STAGED** — plan's line-79 pre-delegation ratified; the ^11 `checkUpgradeStatus()` move is a follow-up cheap cycle **gated on the user cutting the next release tag** (staged rollout = the safety mechanism against skip-path data loss). (2) **MIGRATE-WITH-BACKUP: EXCLUDED** (option ii) — stored data is session/biometric state (loss = re-login/re-enroll; graceful patterns exist); the option's documented README ambiguity + diff-broadening into auth constructors outweigh crash-resumability for re-loginable data; recorded as a ^11-follow-up candidate. (3) **CHECKLIST ADAPTED** per P1's proposed greps (fss==10.3.4, fss_windows==4.2.x, win32==6.4.x, pip==10.2.2, macos ABSENT, js ABSENT; boot-hook item replaced by auto-migration/graceful-degradation/^11-design-recorded). (4) **pubspec pin-comment update IN SCOPE** (comment-only — the :27-30 conflict note becomes factually false after the move). Plan sections amended: objective, P2 files/steps/acceptance, Reviewer commands, this row. |
| 2026-10-13 | **P2 IMPLEMENTED (data-safely, per all 4 rulings), REQUIRED E2E PASS, SINGLE-PASS REVIEW PASS with data-safety scrutiny SATISFIED, PUSH APPROVED by Adviser.** Adviser independently verified: pubspec.yaml = exactly the 2 constraint lines + comment-only pin update (new comment states the lattice truth + staged/data-loss rationale); **lib/ and test/ blob-identical** (migrateWithBackup exclusion honored — zero code risk surface); lattice exact — **fss 10.3.4, fss_windows 4.2.2, package_info_plus 10.2.2, win32 6.4.0, flutter_secure_storage_macos ABSENT, js ABSENT, fss_darwin 0.3.2 added** (F21 RESOLVED — both discontinued transitives gone); macOS registrant 2/2 (conditional chore fires); gates re-run — analyze exit 0, format 0 changed, 208/208. Reviewer's data-safety scrutiny: automatic 9→10 migration confirmed from 3 primary sources (README default + changelog cipher paths + shipped android_options.dart defaults); direct 9→11 data-loss documented and ^11 gated on the next release tag; zero-code-edit safety proven at API/channel/test level; failure mode graceful (resetOnError→re-login/re-enroll). Residual honesty: "zero-loss" is zero-loss-by-documented-design (residual covered by resetOnError + the plan's device-smoke-test advisory); 10.3.2/10.3.4 lack individual changelog sections (maintainer doc gap, existence verified). Commits: `build(deps): move secure-storage lattice to maintained majors (staged 9->10; direct 9->11 documented data-loss)` / `chore: regenerate plugin registrants to match updated dependencies` (fires) / `docs(plans): close cycle 8 and open cycle 9 plan`. Version bump: none; next tag carries 1.2.4 AND unlocks the ^11 follow-up cycle. |
| pending | agent-push: push main (3 commits), watch BOTH workflows → **Build APK green on the new lattice** (runner-side proof the resolved set builds and passes everything), Promote to Landing green — **the promoted APK is the device upgrade-in-place smoke-test artifact** (per the plan's risk acknowledgment: existing users' credentials surviving the fss 9→10 migration is verified on-device, not by gates). On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-10 audit (pre-ranked: F6 on the new stack; ^11 follow-up gated on the next release tag). On red: capture `gh run view --log-failed`, plan stays `active`, fix phase likely selective constraint revert (back to the 9.x lattice). |

- Cycle-10 pre-ranked: **F6** password-hash hardening on the new storage stack (argon2 rehash-on-login pattern; lockout-safe verify-first design). The **^11 `checkUpgradeStatus()` follow-up cycle** is queued but **gated on the user cutting the next release tag** (staged-rollout safety) — same family as the F4/F5/F12 cloud-blocked escalation: **user action required before scheduling**.
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing escalation to the user before scheduling (9th cycle blocked).
- This plan is `done` only when P1+P2 PASS review (after the e2e run; or the STOP-deferral is recorded and the plan closes via Adviser re-scope), the push is Adviser-approved and executed, and BOTH workflows are green.
