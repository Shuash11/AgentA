# Cycle 20 — F6-Residue Closure (the last non-gated finding) + the Formal User-Decision Escalation

**status:** active
**created:** 2026-10-14
**created by:** Adviser (self-improvement cycle 20 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 003f5c8
**predecessors:** plans/done/cycle-1..19 (all closed, CI green; latest runs 38553643776 / 38555220542)

## Cycle 20 ground truth (fresh evidence, 2026-10-14)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 20th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| `flutter pub outdated` | **ONLY the gated ^11 fss 11.2.0** — the voluntary dependency queue has been empty since cycle 17 |
| **F6-residue (current line numbers)** | `login.dart:365` and `:459` — `newHash: PasswordHasher.hashPassword(password)` evaluated as a **call argument** to `dao.tryUpgradePasswordHash(...)`: the DAO's internal never-throws catch cannot cover an argument-evaluation throw; a theoretical argon2 failure would propagate through the login flow. `:233` and `:499` are hash-**creation** sites (new account / password change) where a throw legitimately fails the operation — correct, out of scope. |
| CI | runs 38553643776 / 38555220542 green; zero deprecations |

---

## FIRST AGENDA ITEM — THE FORMAL USER-DECISION ESCALATION (for relay to the user)

**The codebase has reached the clean state the improvement loop targets:** 20 consecutive green cycles; the analyzer clean under the strictest lint set (flutter_lints 6); 222/222 tests; zero dead dependencies; credentials hardened (Argon2id/PHC); the storage lattice on maintained majors; the brand purely AgentA; docs truthful; CI green on every push with all guards. **Every remaining item is blocked on one of three user decisions. This is the critical path to further value:**

1. **CUT THE NEXT RELEASE TAG (v1.2.4).**
   - *What the user gains:* 12 cycles of work currently only on `main` ships to users — the pure-AgentA rebrand, Argon2id credential hashing (work-factor security), the secure-storage lattice (fss 10.3.4 — prerequisite for the ^11 staged migration), connectivity_plus 7, flutter_bloc 9, the probe hardening, and the docs truth.
   - *What it unlocks:* the **^11 fss `checkUpgradeStatus()` follow-up** (gated since cycle 9 by staged-rollout safety — ^10 must be in users' hands before ^11).
   - *Without it:* users keep running v1.2.3-era builds; the improvement backlog stays undelivered; the ^11 cycle stays gated.
2. **GRANT LIVE SUPABASE ACCESS** (project `pmeygoyubqiaqvsuyjzm`).
   - *What it unblocks:* **F4** (version-controlled schema — the Dart↔DB contract's source of truth), **F5** (the H8 server-side recovery-code RPC — closes a documented security TODO), **F12** (the `sync-offline-user` Edge Function — offline-created accounts currently NEVER sync).
   - *Without it:* these three remain cloud-blocked indefinitely (19 cycles and counting).
3. **RULE ON DESKTOP IDENTITY (B2).**
   - *The decision:* the linux/windows/macos runners still carry Flutter-template "aiproject" strings and `com.example.aiproject`-style ids. Either (a) rebrand them (a CHEAP config pass when triggered) or (b) formally accept them as inert (Android-first app).
   - *Without it:* B2 stays parked; the template strings remain (inert, cosmetic-only).

**Standing directive honored:** the loop does not stop — cycle 20 closes the last non-gated finding (below); subsequent cycles run the verification/watch posture (post-Oct-19 runner state, first post-tag ^11 readiness) until a decision un-gates substantive work.

---

## Findings backlog (re-ranked, uncapped) — post-escalation state

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F6-residue** | **The upgrade call sites are not exception-proof at the site level.** `newHash: PasswordHasher.hashPassword(password)` evaluated as a call argument (:365, :459) — a theoretical argon2 throw (disproven for valid inputs, but structurally possible for platform/edge failures) would propagate through login instead of degrading to skip-upgrade. **SELECTED as the cycle-20 task — the last non-gated finding.** | security / robustness (nit) | login.dart:365,459 (verified current) | middle-end | **EXPENSIVE** |
| **F18** | AGP-9 + Built-in-Kotlin toolchain migration — **DEFERRED WITH A DEFINED TRIGGER** (a Flutter release turning the warns into errors / user request / stable-runner-and-empty-queue). Tracks the Ubuntu 26 runner watch (notice-only Oct 14; due ~Oct 19). | CI / toolchain | cycle-19 plan | backend | EXPENSIVE |
| **F11 part 4** | ^11 fss `checkUpgradeStatus()` follow-up — **GATED on decision 1** (the release tag). | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **B2** | Desktop-identity — **GATED on decision 3** (user direction). | branding | cycle-17 ruling | — | CHEAP (when triggered) |
| **F4 / F5 / F12** | Schema versioning / H8 recovery RPC / offline-signup Edge Function — **GATED on decision 2** (Supabase access). | contract / security / logic | cycle-1 plan | backend / security | EXPENSIVE |
| **F23-residue** | 8 display-only ".env" UI strings — PARKED display-only-accepted (cycle-19 ruling; fold into the next UI-copy touch). Mixed tag-annotation — convention note, no action. | branding | cycle-19 closure | — | parked |
| **F15 residue / F16 / F19** | Guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |

Ranking rationale: F6-residue is the last non-gated finding. Closing it leaves the non-gated queue EMPTY — after this cycle, the loop's forward motion is verification/watch until a user decision lands. Honest ROI note: the nit is theoretical, but it is real structural debt in the credential path, the fix is small and well-understood (the cycle-10 review already designed it), and closing it makes the clean-state claim complete: **zero open non-gated findings of any severity.**

---

## Selected task (single): F6-residue — exception-proof the upgrade call sites

**Objective:** a theoretical `hashPassword` failure at either upgrade site degrades to the documented best-effort skip-upgrade (caught, logged per docs/error-hygiene.md) instead of propagating through the login flow; zero behavior change for all real inputs; the legacy/new verify contract untouched.

**Version bump decision: none** — robustness hardening is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **the phase below is EXPENSIVE (auth-path behavior), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch.

**DESIGN (from the cycle-10 review observation — already researched):** at both sites (:365, :459), the upgrade invocation becomes site-level exception-proof. Minimal shape: hoist the hash into a local inside the existing flow and wrap the `needsUpgrade` upgrade call in its own try/catch that swallows + `debugPrint`s per the error-hygiene log pattern (`[Login] upgrade skipped: $e`) — the login proceeds unconditionally (the existing post-auth flow is untouched). Alternative equivalent shape (hoisting the argument evaluation into the enclosing try) is acceptable if the diff is smaller — the implementer picks the minimal-diff shape and documents it. **The verify contract (`verification.matched`/`needsUpgrade`), the saveSession flow, and both site's surrounding logic stay byte-identical.**

**STOP RULE (binding):** if the minimal-diff shape turns out to require touching the verify/saveSession logic or the DAO contract → STOP and report (the nit is theoretical; a structural change would not be proportionate).

---

## Phase 1 — Implement the site-level exception-proofing

- **Phase id:** P1 (single phase)
- **Objective:** a theoretical `hashPassword` throw at either upgrade site cannot escape the login flow; zero behavior change for real inputs.
- **Responsible subagent:** middle-end
- **Files to change:** `lib/presentation/auth/login.dart` (the 2 upgrade sites only)
- **Implementation steps:**
  1. Apply the minimal-diff shape per the DESIGN (try/catch swallow + error-hygiene log, or the equivalent hoist — document which in the phase report).
  2. Confirm the sites' surrounding logic (verify contract, saveSession) is byte-identical.
  3. Local validation: `flutter analyze` exit 0 (flutter_lints 6), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` → 222/222.
  4. Repo-wide grep proof: no other `tryUpgradePasswordHash` call sites exist (expected: 2); no other unguarded `hashPassword` argument-evaluations in upgrade positions.
  5. **STOP-and-report on any structural surprise** (fallback rule).
- **Acceptance criteria:** both sites exception-proof; zero behavior change for real inputs (the 222 suite + code trace); diffs = the 2 sites only.
- **Verification:** **EXPENSIVE** — auth-path behavior. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: analyze ×2 exit 0, 222/222, format 0, site-diff audit, upgrade-flow trace (theoretical-throw path degrades, real-input path unchanged).
- **Dependencies / sequencing:** single phase.
- **Expected result:** the credential path is fully best-effort at both upgrade sites; the last non-gated finding is closed.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `fix(security): exception-proof the verify-then-upgrade call sites (F6-residue)` — login.dart. Atomic.
- Commit 2: `docs(plans): close cycle 19 and open cycle 20 plan` — stage `plans/` explicitly (deletion of old cycle-19 path, `plans/done/cycle-19-...md`, new cycle-20 file). Never root-wide `git add -A`/`git add .`
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); the verify/saveSession logic byte-identical.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — identical profile to run 38553643776 (guards + format gate + strict-lint analyze + 222/222 + APK build). **Failure class to name if red:** Dart compile errors at login.dart — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase = scoped revert (the nit is theoretical; revert is always safe).
- **Promote to Landing** green as usual.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-21 audit. **Post-cycle-20 posture (stated now): the non-gated queue is EMPTY** — cycle 21 opens with the user-decision escalation re-stated, the F18 Ubuntu-26/post-Oct-19 runner observation, and the verification/watch framing (the loop continues on watch + newly surfaced findings until a user decision un-gates substantive work).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

**None needed — stated honestly per the web-research skill:** the fix is repo-internal control-flow mechanics on APIs already researched and cited in cycle 10 (argon2 semantics, pointycastle). No external contract is touched.

## Reviewer verification commands (single pass, after P1)

1. Site audit: `git diff lib/presentation/auth/login.dart` → the 2 upgrade sites only; the chosen shape (try/catch swallow or hoist) matches the documented design; the verify contract + saveSession logic byte-identical.
2. Exception-path audit: trace both sites — a theoretical `hashPassword` throw lands in a catch (degrades to skip-upgrade, logged), never propagates past the login flow.
3. Creation-site audit: :233/:499 untouched (a throw there legitimately fails the operation — correct).
4. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` 222/222, `dart format --output=none --set-exit-if-changed lib test` exit 0.
5. Scope: login.dart only; analysis_options.yaml absent; .opencode/ absent.
6. STOP-echo audit: if the implementer STOPped on a structural surprise, verify clean revert + recorded gaps.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-14 | Cycle-20 audit recorded; plan created `active` (task F6-residue — the LAST non-gated finding). **THE FORMAL USER-DECISION ESCALATION stated as the first agenda item** (v1.2.4 tag / Supabase access / desktop direction). Post-cycle-20 posture stated: the non-gated queue will be EMPTY; the loop enters verification/watch until a decision un-gates substantive work. |
| 2026-10-14 | **P1 IMPLEMENTED, REQUIRED E2E PASS, SINGLE-PASS REVIEW PASS (exception-path EMPIRICALLY proven via shape-replica script), PUSH APPROVED by Adviser.** Adviser independently verified: scope = login.dart ONLY; exactly 2 hunks — both `needsUpgrade` upgrade calls wrapped in-place in try/catch (Shape B, smallest diff), catch = `if (kDebugMode) debugPrint('[Login] upgrade skipped: $e')` per docs/error-hygiene.md, the `hashPassword` argument inside the try scope, verify/saveSession byte-identical, creation sites untouched; gates re-run — analyze exit 0, format 0 changed, 222/222. Reviewer: site-diff exact; **exception-path trace EMPIRICALLY proven** (shape-replica Dart script: synchronous argument-eval throw caught → skip-upgrade → login proceeds); creation-site audit holds; STOP-echo minimal-diff discipline honored; "no web searches needed" stance confirmed (pure repo-internal control flow; the sole language premise verified empirically). **THE LAST NON-GATED FINDING IS CLOSED — post-cycle-20 posture: the non-gated queue is EMPTY; cycle 21 opens with the re-stated user-decision escalation + verification/watch framing.** Commits: `fix(security): exception-proof the verify-then-upgrade call sites (F6-residue)` / `docs(plans): close cycle 19 and open cycle 20 plan`. Version bump: none; next tag carries 1.2.4 and unlocks the ^11 fss follow-up. |
| pending | agent-push: push main (2 commits), watch BOTH workflows → **Build APK green — identical profile** (failure class if red = Dart compile errors at login.dart or auth-suite test failures → fix phase = scoped 1-file revert); **F18 runner watch (still 24.04 — observe only)**; Promote to Landing green as usual. On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-21 audit — **the re-stated user-decision escalation as first agenda item** (v1.2.4 tag / Supabase access / desktop direction) + verification/watch framing (post-Oct-19 runner, first post-tag ^11 readiness). On red: capture `gh run view --log-failed`, plan stays `active`, fix phase planned. |

- Cycle-21 pre-ranked: **verification/watch posture** — the user-decision escalation re-stated, the post-Oct-19 runner observation, ^11 readiness check (if the tag was cut), and any newly surfaced findings. The F18 AGP-9 migration stays deferred-with-trigger.
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing user escalation (20 cycles). The ^11 fss follow-up remains gated on the user's next release tag. B2 remains parked.
- This plan is `done` only when P1 PASSes the single review (after the e2e run), the push is Adviser-approved and executed, and BOTH workflows are green.
