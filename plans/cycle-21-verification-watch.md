# Cycle 21 — Verification & Watch Cycle (the clean-state posture)

**status:** active
**created:** 2026-10-14
**created by:** Adviser (self-improvement cycle 21 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ fde57a1
**predecessors:** plans/done/cycle-1..20 (all closed, CI green; latest runs 38573099266 / 38574801994)

## Cycle 21 ground truth (fresh evidence, 2026-10-14)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 20th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| `flutter pub outdated` | **ONLY the gated ^11 fss 11.2.0** — the voluntary dependency queue remains empty |
| CI | runs 38573099266 / 38574801994 green; annotations 3 informational (baseline — no drift); runner still ubuntu-24.04 (pre-Oct-19) |

## THE POSTURE (stated plainly)

**The codebase has reached the clean state the directive targets: 20 consecutive green cycles, the analyzer clean under the strictest lint set, 222/222 tests, zero dead dependencies, hardened credentials (Argon2id/PHC), the storage lattice on maintained majors, pure-AgentA branding, truthful docs, and a CI pipeline with dependency guards, semver guards, and lint/format gates. The non-gated queue is EMPTY — F6-residue (the last finding) closed in cycle 20.**

**THE RE-STATED USER-DECISION ESCALATION (for relay — the critical path to further value):**
1. **CUT THE NEXT RELEASE TAG (v1.2.4)** — ships 20 cycles of improvements (pure-AgentA rebrand, Argon2id credentials, the fss 10.3.4 lattice, connectivity_plus 7, flutter_bloc 9, probe hardening, docs truth) and **unlocks the ^11 fss `checkUpgradeStatus()` follow-up** (gated since cycle 9).
2. **GRANT LIVE SUPABASE ACCESS** (project `pmeygoyubqiaqvsuyjzm`) — unblocks F4 (schema versioning), F5 (the H8 recovery-code RPC), F12 (the offline-signup Edge Function).
3. **RULE ON DESKTOP IDENTITY (B2)** — rebrand the desktop runners (CHEAP when triggered) or formally accept them as inert.

**The loop continues per the standing directive** — this cycle is the verification/watch posture: concrete executable checks that the clean state HOLDS, with any drift becoming a fix phase.

## Findings backlog (re-ranked, uncapped) — the watch-era state

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F18** | Gradle/AGP below Flutter warn thresholds (deferred-with-trigger: a Flutter release turning warns into errors / user request / stable runner) + **the Ubuntu 26 runner migration watch (due ~Oct 19 — 5 days out; the first post-date run is the observation point)**. | CI / toolchain | DependencyVersionChecker.kt warn values; runner observation (ubuntu-24.04 as of Oct 14) | backend | EXPENSIVE |
| **F11 part 4** | ^11 fss `checkUpgradeStatus()` follow-up — **GATED on decision 1** (the release tag). | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **B2** | Desktop-identity — **PARKED pending decision 3**. | branding | cycle-17 ruling | — | CHEAP (when triggered) |
| **F4 / F5 / F12** | Schema versioning / H8 recovery RPC / offline-signup Edge Function — **GATED on decision 2** (Supabase access). **20 cycles blocked — the single biggest blocker to remaining value.** | contract / security / logic | cycle-1 plan | backend / security | EXPENSIVE |
| **F15 residue / F16 / F19** | Duplicate-semver guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |
| *(closed)* | F1-F6, F7-F17, F20-F24 + B1/B3: all resolved across cycles 1-20 (see plans/done/). The only carry-forwards are the gated/blocked/parked items above. | — | plans/done/ | — | — |

**Fresh-findings sweep result (this audit): NO new non-gated findings.** The analyzer is clean under flutter_lints 6, the suite is 222/222, the dependency queue holds only the gated ^11, and the working tree is clean. The verification cycle below makes that state *checked* rather than *asserted*.

---

## Selected task (single): the verification/watch battery — prove the clean state holds

**Objective:** execute the concrete check battery; the outcome is either **"all clean, nothing to fix; escalation pending"** (cycle closes without a code push) or **a drift finding becomes a fix phase**.

**Version bump decision: none** — a verification cycle changes no version; if drift forces a fix phase, that fix's own bump decision is made then (expected: none). Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — every phase below is **CHEAP-class, no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch (the bookkeeping push; see the close rule).

**CLOSE RULE (binding — how a verification cycle closes):**
- **If ALL checks pass and nothing changed:** the cycle closes **WITHOUT a code push**. The only commit is the plans bookkeeping (`docs(plans): close cycle 20 and open cycle 21 plan` — the cycle-20 closure move + this plan file). CI still runs on that push (docs-only) and must be green.
- **If ANY check finds drift** (analyzer findings, test failures, annotation drift beyond baseline, docs-claim drift): the drift becomes a **fix phase** with its own code commit; the plan stays `active` until the fix lands and CI is green.

---

## Phase 1 — The verification battery

- **Phase id:** P1 (single phase)
- **Objective:** the clean state proven by executable checks, not assertion.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only battery; the plans bookkeeping is the only artifact)
- **Implementation steps (the concrete checks):**
  1. **Ground-truth battery:** `flutter analyze` → exit 0; `flutter test` → 222/222; `dart format --output=none --set-exit-if-changed lib test` → exit 0; `git status` → only plan artifacts; `flutter pub outdated` → only the gated ^11.
  2. **Docs-consistency spot-check:** the cycle-19 sweep fixes still hold — README:44 shows `^0.14.4`, README:62 shows `dart run flutter_launcher_icons`, README §5 states dart-define-only, backend-rls.md §C1 states no-fallback, app_config.dart:168 comment states logout-only, google-signin-setup.md troubleshooting row cites dart-define, zero "AI Skill Coach"/"coach"/wrong-case "Agenta" in lib+test (case-sensitive greps).
  3. **CI-annotation review:** compare the latest Build APK run's annotations against the baseline (3 informational: V2 signer digests ×2, Ubuntu 26 notice) — **any new or changed annotation is a finding** (record under F18/new ID; observe and record only).
  4. **State-unchanged confirmation:** `flutter pub deps` spot-check (no unexpected dependency drift since cycle 16's removal); the plans/done/ archive count matches the closed-cycle count (20).
  5. Record the battery results in the phase report (the Reviewer re-runs them).
- **Acceptance criteria:** every check passes OR every failure is a recorded drift finding.
- **Verification:** **CHEAP** — read-only battery.
- **Dependencies / sequencing:** single phase.
- **Expected result:** "all clean, nothing to fix; escalation pending" — or a drift finding that becomes the next fix phase.

## Push guidance (after Adviser confirmation — do not push before it) — AMENDED FOR THE RELEASE CUT

- Commit 1: `chore(release): bump version to 1.2.4+1` — pubspec.yaml (the version line) + docs/versioning.md (tags/current-version line).
- Commit 2 (bookkeeping): `docs(plans): close cycle 20 and open cycle 21 plan` — stage `plans/` explicitly (deletion of old cycle-20 path, `plans/done/cycle-20-...md`, new cycle-21 file). Never root-wide `git add -A`/`git add .`
- THEN the tag: `git tag -a v1.2.4 -m "Release 1.2.4"` → `git push origin v1.2.4` (per docs/versioning.md §2 — commit first, then tag, then tag-push).
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); nothing else rides.
- Version bump: **1.2.3+6 → 1.2.4+1** (this is the release exception to the per-push "none" convention — the tag carries the bump, per docs/versioning.md §2).

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — identical profile (docs-only bookkeeping). This run also serves the **F18 Ubuntu 26 watch** if it lands post-Oct 19: record deltas, observe only.
- **Promote to Landing** green as usual.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-22 audit — **same posture**: re-state the escalation, run the battery, check the runner watch (post-Oct-19 by then), surface any new findings. The loop continues per the standing directive.

## Reviewer web searches for the whole plan (single place, per orchestration rule)

**None needed — stated honestly per the web-research skill:** the battery is repo-internal (gates, greps, annotation comparison). The only external-ish fact (Ubuntu 26 migration timing) is observed from CI runs, not researched.

## Reviewer verification commands (single pass, after P1)

1. Re-run the battery exactly as specified (all 5 checks) — quote each result.
2. Docs-consistency greps — quote the matches (the cycle-19 fixed lines present; zero stale patterns).
3. Annotation comparison — the latest run's annotations vs baseline (3 informational); any delta recorded.
4. Scope: zero code diffs outside plans/; analysis_options.yaml absent; .opencode/ absent.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-14 | Cycle-21 audit recorded; plan created `active` (verification/watch battery). **The re-stated user-decision escalation recorded as the standing first-agenda item.** Close rule defined: all-clean → bookkeeping-only commit, no code push; drift → fix phase. |
| 2026-10-14 | **THE BATTERY RAN — ALL EXECUTABLE CHECKS PASS** (analyze 0, 222/222, format 0, tree clean, lattice holds, docs-consistency holds, annotations = baseline, archive = 20). **F25 RECORD-ONLY FINDING** (queue-line precision; no repo defect): the raw outdated output also shows (a) the flutter_edge_ai 2.x line (1.11.4→2.3.3 / mediapipe 1.0.8→1.2.2 — deliberately held since cycle 7: mediapipe 1.2.2 needs core ^2.3.0) and (b) in-range accrual (13 locked; sqflite-family patch bumps). Evidence of upstream motion + queue-recording convention, NOT a regression; zero impact on gates/CI/docs/security. |
| 2026-10-14 | **THE USER DIRECTED: "tag the version if it's done and it's clean." — CONDITION RULING: RELEASE CONDITION MET.** The battery is the evidence: 20 consecutive green cycles, all executable checks pass, 222/222, analyzer clean under flutter_lints 6, zero dead dependencies, hardened credentials, truthful docs, CI green on every push. F25 does NOT block (record-only; no repo defect). **THE RELEASE CUT IS NOW THE CYCLE-21 TASK** (the user's priority supersedes the pure-verification framing; the battery becomes the release's evidence base). **F25 RULINGS:** (1) *Queue-line precision* — future records state: "the voluntary queue is empty; recorded holds: the flutter_edge_ai 2.x line (deliberately held, see F26) + in-range accrual (tracked, see F27)". (2) *edge_ai 2.x* — **ACCEPT-STAY-ON-1.X**, recorded as **F26** (the engine-major migration, map-first, deferred-with-trigger: when 1.x stops receiving fixes or a 2.x feature is needed — same discipline as F18). (3) *sqflite accrual* — recorded as **F27** (in-range refresh #2, routine, schedulable anytime after the release). (4) After the tag: the ^11 fss follow-up becomes schedulable (cycle-22 pre-rank). |
| 2026-10-14 | **RELEASE-PUSH GATE: PUSH APPROVED by Adviser.** Adviser independently verified: pubspec.yaml = the version line ONLY (`1.2.3+6` → `1.2.4+1`); docs/versioning.md = the tags/current-version line only (v1.2.4 added to the 7-tag list); **no v1.2.4 tag exists** (duplicate-semver precondition holds); plans bookkeeping rides as designed; gates re-run — analyze exit 0, format 0 changed, 222/222. Reviewer's tag-guard semantic verification accepted (semver-part-only comparison → `v1.2.4` + `1.2.4+1` passes). **FORMAL BUMP STATEMENT (the first of the loop's history — all 21 prior cycles held "none" per push): this release carries the bump 1.2.3+6 → 1.2.4+1; the tag v1.2.4 carries it to users; per docs/versioning.md §2 the build number restarts (+1) and is metadata-only.** |
| pending | agent-push RELEASE SEQUENCE (verbatim): (1) commit 1: `chore(release): bump version to 1.2.4+1` — pubspec.yaml + docs/versioning.md; (2) commit 2: `docs(plans): close cycle 20 and open cycle 21 plan` — stage `plans/` explicitly (cycle-20 deletion + done/ + cycle-21 file); (3) `git push origin main` → CI watch: Build APK on main green (identical profile); (4) `git tag -a v1.2.4 -m "Release 1.2.4"`; (5) `git push origin v1.2.4` → CI watch: **Build APK on the tag** — tag-assert ✓ (v1.2.4 == 1.2.4+1 semver-part), duplicate-semver guard ✓ (no prior release), 222/222 on the runner, APK built, **the GitHub release created**, artifact uploaded; Promote to Landing promotes the tag APK. Failure class if red: version-mismatch at the tag-assert (bump/tag disagree) or standard gates → plan stays `active`, fix before anything else. On all green: the release is SHIPPED; Adviser closes cycle 21, opens cycle 22 (**pre-rank: the ^11 fss follow-up — now schedulable — plus F26/F27**); the remaining user decisions (Supabase access, desktop direction) stay standing. |

- Cycle-22 pre-ranked: **same verification/watch posture** — by then the Oct 19 runner date will have passed: the first post-date run's observations become the F18 record. The user-decision escalation re-stated.
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing user escalation (21 cycles). The ^11 fss follow-up remains gated on the user's next release tag. B2 remains parked.
- This plan is `done` only when P1 PASSes the single review, the bookkeeping push is Adviser-approved and executed, and BOTH workflows are green.
