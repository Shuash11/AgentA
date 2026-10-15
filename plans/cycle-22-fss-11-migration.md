# Cycle 22 — fss 10→11 Migration + checkUpgradeStatus() Integration (F11 part 4) — Data-Safe, Map-First

**status:** active
**created:** 2026-10-15
**created by:** Adviser (self-improvement cycle 22 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ bc1479c
**predecessors:** plans/done/cycle-1..21 (all closed, CI green; **v1.2.4 is LIVE** — release verified, 20 cycles of improvements in users' hands)

## Cycle 22 ground truth (fresh evidence, 2026-10-15)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 22nd consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only the plans bookkeeping from the cycle-21 close |
| `flutter pub outdated` | fss 10.3.4 → **11.2.0** (the task); flutter_edge_ai 1.11.4→2.3.3 + mediapipe 1.0.8→1.2.2 (held per F26); fss_darwin 0.3.2→0.4.3 (transitive, follows) |
| **THE UN-GATE** | **v1.2.4 is LIVE** (tag verified: guard OK, duplicate-guard OK, release created, Promote green; `AgentA-v1.2.4.apk` 183,012,379 B on the Latest release). The cycle-9 staged-rollout precondition — **^10 in users' hands** — is now satisfied: v1.2.4 ships fss 10.3.4, and its 9→10 auto-migration runs on first access after update. |
| **fss consumer surface** | **exactly 2 files** (re-verified): `biometric_auth_service.dart` + `session_manager.dart` (one `FlutterSecureStorage()` instance each). Tests mock the abstraction. |
| **Cycle-9 P1 design (recorded, cited)** | 9→10 auto-migration (shipped in v1.2.4); **direct 9→11 documented data-loss** ("upgrade to v10 first"); **`checkUpgradeStatus()`** (11.1.0+, read-only, boot-before-first-access, Android-only — reports whether data was lost in a past/aborted upgrade); graceful handling = biometric re-enroll + re-login (the app already degrades gracefully on missing keys). |
| CI | runs 38601012205 (tag, release created) / 38603218778 green; F28 observation: softprops/action-gh-release@v2 Node-20 deprecation (release-step-only). |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F11 part 4** | **fss 10→11 + `checkUpgradeStatus()` integration.** The un-gated follow-up (v1.2.4 shipped ^10). The 10→11 step is the documented-safe path FOR USERS ON v1.2.4; the skip-path (v1.2.3 straight to the fss-11 release) hits the documented data-loss semantics — the `checkUpgradeStatus()` boot hook makes that detectable (degrade to re-login/re-enroll, never silent). **SELECTED as the cycle-22 task — map-first, data-safety scrutiny (the cycle-9 standard).** | maintainability / data-risk | pub outdated; the 2-file surface; cycle-9 P1 design | middle-end | **EXPENSIVE** |
| **F26** | flutter_edge_ai 2.x engine-major migration (mediapipe 1.2.2 needs core ^2.3.0) — deferred-with-trigger (when 1.x stops receiving fixes or a 2.x feature is needed; same discipline as F18). | maintainability | pub outdated; cycle-15 F25 ruling | middle-end | EXPENSIVE |
| **F28** *(new, from the v1.2.4 tag run)* | **softprops/action-gh-release@v2 runs on deprecated Node 20** (the tag run's 4th annotation; release-step-only, no gate impact). Check whether a newer major exists when next convenient; fold with any future CI-actions touch. | CI (nit) | tag-run 38601012205 annotations | backend | CHEAP |
| **F27** | sqflite-family in-range accrual (13 locked; sqflite 2.4.4+1→+2, sqflite_common_ffi 2.4.3→2.4.4) — routine in-range refresh #2; schedulable after the ^11 cycle. | maintainability | F25 record | middle-end | CHEAP |
| **F18** | Gradle/AGP below Flutter warn thresholds (deferred-with-trigger) + the Ubuntu 26 runner watch (due ~Oct 19 — 4 days out; first post-date run = observation point). | CI / toolchain | cycle-19 plan | backend | EXPENSIVE |
| **B2** | Desktop-identity — PARKED pending user direction. | branding | cycle-17 ruling | — | CHEAP (when triggered) |
| **F4 / F5 / F12** | Schema versioning / H8 recovery RPC / offline-signup Edge Function — **CLOUD-BLOCKED (20 cycles) — still the single biggest blocker to remaining value.** | contract / security / logic | cycle-1 plan | backend / security | EXPENSIVE |
| **F15 residue / F16 / F19** | Guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |

Ranking rationale: the release un-gated the highest-value remaining item; the design is already recorded (cycle 9 P1); the data-safety playbook is proven (cycle 9's staged migration); the blast radius is 2 files. The staged-rollout condition is now met — this is the right cycle for it.

---

## Selected task (single): F11 part 4 — fss 10→11 + checkUpgradeStatus() integration

**Objective:** flutter_secure_storage ^11.2.0 live with the **boot-time `checkUpgradeStatus()` integration** (read-only loss detection, graceful degradation per the cycle-9 design); the 2-consumer API surface adapted mechanically per the map; **users on v1.2.4 (fss-10 data) migrate safely; skip-path users get DETECTED degradation (re-login/re-enroll), never silent loss or crashes**; all gates + e2e + CI green.

**Version bump decision: none** — dependency migration is not a release; the next user-facing tag (1.2.5 or as warranted) is the user's cut, and per the staged-rollout design it should follow v1.2.4 adoption (the trigger is the user's; the code becomes ready this cycle). Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **P2 is EXPENSIVE (secure-storage data behavior), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch.

**STOP RULE (binding, cycles 7/9/10/12/13/15/16/17 precedent):** P1 maps the 10→11 migration from the official changelog/docs ALONE. **If the API breaks are not mechanically mappable, the `checkUpgradeStatus()` contract differs from the cycle-9 record, or the skip-path handling cannot be designed gracefully → STOP**, record, and the Adviser re-scopes (deferral is acceptable — the staged rollout already delivered the 9→10 safety; ^11 can wait).

**RISK ACKNOWLEDGMENT (honest, plan-level):** on-device migration behavior is not gate-coverable. Non-gating advisory: after green, the user smoke-tests (1) an upgrade-in-place from a v1.2.4 install (credentials survive), and (2) the documented skip-path behavior on a test device. The 2-file blast radius, the read-only hook, and the graceful-degradation design are the mitigations.

---

## Phase 1 — The 10→11 migration map (read-only evidence pass)

- **Phase id:** P1
- **Objective:** the complete old→new map for the 2 consumers + the `checkUpgradeStatus()` integration design — or an honest STOP.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only)
- **Implementation steps:**
  1. Extract the official 10→11 breaking-change list with verbatim changelog citations (pub.dev/packages/flutter_secure_storage CHANGELOG 10.3.4→11.0.0→11.2.0; candidate areas: options constructors, method signatures, platform-interface changes — HYPOTHESES to verify against the cycle-9 record).
  2. Map the 2 consumers' API usage (the `FlutterSecureStorage()` const ctor, read/write/delete/readAll per cycle 9) against 11.x: mechanical or not.
  3. `checkUpgradeStatus()` integration design: exact API sequence, boot placement (before AuthService/SessionManager first read — the main.dart ordering per cycle 9's design), the loss-report handling (biometric re-enroll + re-login with friendly text per docs/error-hygiene.md), and platform scope (Android-only per the cycle-9 record — verify).
  4. Skip-path design: what a v1.2.3→fss-11 user experiences (the documented data-loss semantics + the hook's detection) — confirm the degradation is graceful and documented.
  5. Confirm version pin: `flutter_secure_storage: ^11.2.0` resolves with the current lattice (fss_windows/fss_darwin transitives follow — verify no win32 re-entanglement).
  6. **STOP decision:** any non-mechanical break, contract mismatch, or unresolvable skip-path gap → STOP; record everything.
- **Acceptance criteria:** the 2 consumers mapped with citations; the hook design complete; the skip-path behavior documented; or STOP with the specific gap.
- **Verification:** **CHEAP** — read-only; no e2e impact.
- **Dependencies / sequencing:** first; P2 executes only a clean map.
- **Expected result:** P2 fully determined, or an honest deferral (the staged rollout already delivered its safety value).

## Phase 2 — Apply the migration + the boot hook

- **Phase id:** P2
- **Objective:** fss ^11.2.0 live; the 2 consumers adapted; the boot hook integrated; gates green.
- **Responsible subagent:** middle-end
- **Files to change:** `pubspec.yaml` (fss ^11.2.0), `pubspec.lock`, `lib/core/config/app_config.dart` or `lib/main.dart` (the hook, per the map), `lib/services/auth/biometric_auth_service.dart` + `lib/services/auth/session_manager.dart` (API adaptation per the map), possibly test seams
- **Implementation steps:**
  1. Apply the map mechanically: constraint bump; consumer updates strictly per the map; the hook per the design (loss report → graceful degradation, never a crash).
  2. Preserve semantics: the storage keys, the biometric flow, and the session contract identical for same-version data.
  3. Local validation: `flutter analyze` exit 0 (flutter_lints 6), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` → 222/222 (test-count changes only if the map demands new seams — report explicitly).
  4. **STOP-and-revert on any non-mechanical gap** (fallback rule).
- **Acceptance criteria:** constraint = the designed line; consumer diffs = the map; the hook integrated per design; gates green.
- **Verification:** **EXPENSIVE** — secure-storage data behavior. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: analyze ×2, 222/222, format 0, enforce-lockfile idempotent, the lattice post-state (fss 11.2.0, fss_darwin 0.4.x, win32 6.4.x unchanged), hook-placement audit.
- **Dependencies / sequencing:** after P1's clean map (STOP forbids P2). P2 is the only application phase.
- **Expected result:** the credentials stack on the latest maintained major with loss detection integrated; F11 part 4 closed.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `feat(storage): migrate to flutter_secure_storage 11 with checkUpgradeStatus loss detection (F11 part 4)` — pubspec.yaml, pubspec.lock, the mapped files. Atomic (constraint + required code never split).
- Commit 2 (conditional, cycle-6 rule): `chore: regenerate plugin registrants to match updated dependencies` — ONLY if registrant diffs exist at push time; otherwise SKIP.
- Commit 3: `docs(plans): close cycle 21 and open cycle 22 plan` — stage `plans/` explicitly (deletion of old cycle-21 path, `plans/done/cycle-21-...md`, new cycle-22 file). Never root-wide `git add -A`/`git add .`
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); no other pubspec constraints (edge_ai stays held per F26).
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — the runner compiles the migrated storage stack (fss_windows 4.2.x unchanged; the Android fss artifact updates) with all guards + format gate + strict-lint analyze + 222/222 + APK build. **Failure class to name if red:** Dart compile errors at the 2 consumer files or test failures in the auth suites — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase = scoped revert to ^10.3.4 (the staged rollout's value is already shipped — a revert never loses user data).
- **Watch F18:** the Ubuntu 26 runner date (~Oct 19) — record the runner image on this run.
- **Promote to Landing** green as usual — the promoted APK is the upgrade-in-place smoke-test artifact (user advisory: upgrade from v1.2.4 → credentials survive; the documented skip-path degrades to re-login).
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-23 audit (pre-ranked: F27 in-range refresh #2 or F11-part-3c residue; F26/F18 deferred-with-trigger).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `flutter_secure_storage 11.0.0 changelog breaking changes from 10` (pub.dev — the official 10→11 delta, verbatim).
2. `flutter_secure_storage checkUpgradeStatus API documentation` (pub.dev/API — the exact contract: return type, platform scope, boot placement).
3. `flutter_secure_storage 11.2.0 changelog` (the resolved-version deltas).
4. `flutter_secure_storage_windows 4.2.2 win32 constraint` (the lattice link — confirm no win32 re-entanglement).

## Reviewer verification commands (single pass, after P1+P2)

1. `git diff pubspec.yaml` → exactly the fss constraint line; `pubspec.lock` → fss 11.2.0, fss_darwin 0.4.x, win32 6.4.x unchanged, fss_windows 4.2.x.
2. Consumer audit: `git diff biometric_auth_service session_manager` → matches the P1 map site-by-site; the storage keys + flows identical for same-version data.
3. Hook audit: the `checkUpgradeStatus()` integration at the designed boot location; the loss path degrades gracefully (friendly text, re-login/re-enroll, never a crash); Android-only scoping per the contract.
4. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` all-pass (quote count vs 222), `dart format --output=none --set-exit-if-changed lib test` exit 0; `flutter pub get --enforce-lockfile` idempotent.
5. Scope: no other constraints (edge_ai held); analysis_options.yaml absent; .opencode/ absent.
6. If P1 STOPped: verify clean revert (empty git diff) + recorded gaps.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-15 | Cycle-22 audit recorded; plan created `active` (task F11 part 4 — the un-gated ^11 follow-up). F28 recorded (softprops Node-20 nit). The consumer surface re-verified (2 files). The cycle-9 design cited as the baseline. |
| pending | P1 (map, CHEAP) + P2 (apply, EXPENSIVE — forbidden if P1 STOPs) → **once-per-plan e2e run (required if P2 ran)** → single Reviewer pass → Adviser push confirmation → push + CI watch → on green: close plan, open cycle-23 audit. |

- Cycle-23 pre-ranked: **F27** (sqflite in-range refresh #2 — routine) or F11-part-3c-4 residue; F26/F18 deferred-with-trigger; B2 parked; **F4/F5/F12 remain CLOUD-BLOCKED (21 cycles) — the standing user escalation.**
- This plan is `done` only when P1+P2 PASS review (after the e2e run; or the STOP-deferral is recorded and the plan closes via Adviser re-scope), the push is Adviser-approved and executed, and BOTH workflows are green.
