# Cycle 11 — flutter_lints 6 Adoption (F11 part 3a)

**status:** done (closed 2026-10-13 — P1 PASS, push executed, both workflows green; flutter_lints 6 live with zero findings)
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 11 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 232cabb
**predecessors:** plans/done/cycle-1..10 (all closed, CI green; latest runs 38388465650 / 38389882933)

## Cycle 11 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` (strict lints) | **"No issues found!" exit 0** — 10th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** (208 baseline + 14 F6 tests) |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| flutter_lints | **^4.0.0 (dev dep) → 6.0.0 available** — a dev-only dependency; the lint set raise is the task |
| bloc surface | **99 matches** across lib/ + test/ — bloc 9's breaking changes touch every state-management file; deliberately NOT paired with this cycle (one risk surface at a time; dedicated cycle 12) |
| CI | runs 38388465650 / 38389882933 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F11 part 3a** | **flutter_lints 4 → 6.0.0.** Dev-only constraint bump; the new lint set may surface findings repo-wide. Cycle-4's proven playbook applies: enable → `dart fix --apply` → defer non-mechanical lint-by-lint with recorded reasons. **SELECTED as the cycle-11 task — alone, deliberately un-paired from bloc 9** (99-match surface; one risk surface per cycle). | maintainability | pub outdated; analysis_options.yaml | middle-end | CHEAP (with deferral/STOP discipline) |
| **F11 part 3b** | **flutter_bloc 8 → 9.1.1** — breaking changes (BlocBase/API updates, dart 3 alignment) across the **99-match state-management surface** (cubit/chat/connectivity/theme/update + presentation). Dedicated cycle 12 with full attention; e2e required. | maintainability | 99-match grep; pub outdated | middle-end | EXPENSIVE |
| **F11 part 3c** | **Remaining blocked majors** (connectivity_plus 7.3.2, flutter_dotenv 6.0.1, cupertino_icons 2.0.0, flutter_launcher_icons 0.14.4) — independent small constraint cycles after 3a/3b. | maintainability | pub outdated | middle-end | EXPENSIVE |
| **F11 part 4** | **^11 fss `checkUpgradeStatus()` follow-up** — design recorded (cycle 9 P1); **GATED on the user cutting the next release tag** (staged-rollout safety). | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **F6-residue** | `hashPassword(password)` evaluated outside `tryUpgrade`'s try (login.dart:365,459) — theoretical only (golden vector + 222-test run disprove argon2 throwing on valid inputs). Low-priority hardening note: move inside the try if ever touched again. | security (nit) | cycle-10 review | middle-end | CHEAP |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — deliberate deferral; AGP 9 + Built-in-Kotlin migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15 residue / F16 / F19** | Duplicate-semver guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (11 cycles).** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: 10 clean cycles; the remaining majors split cleanly. lints 6 is the smallest durable win and its playbook is proven (cycle 4); bloc 9 is the biggest and gets its own cycle. Sequencing lints first also hardens the analyzer BEFORE bloc 9's migration lands — the new lint set will then scrutinize the bloc-9 diff too.

---

## Selected task (single): F11 part 3a — flutter_lints 6 adoption

**Objective:** the dev dependency runs at 6.0.0 with every mechanically-fixable finding resolved, every non-mechanical lint explicitly deferred (lint-by-lint, reasons recorded), and the analyzer green — the repo's strict-lint floor raised without behavior change.

**Version bump decision: none** — dev-dependency maintenance is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — since the phase below is **CHEAP-class under the deferral discipline, no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch.

**DEFERRAL/STOP DISCIPLINE (binding, cycle-4 precedent):** surfaced findings are resolved ONLY mechanically — `dart fix --apply --code=<code>` where a fix exists, or equivalent non-behavioral edits (const additions, annotation moves). **Any finding whose fix would change behavior (await additions, logic changes, structural rewrites) is NOT fixed**: defer that LINT (comment out with `# deferred — <reason>` in analysis_options) and record it in the plan. If deferrals exceed 5 lints or any deferral would gut 6.0's core value, STOP and report — the Adviser re-scopes (possibly splitting the adoption).

---

## Phase 1 — Bump to flutter_lints 6 + mechanical compliance (F11 part 3a)

- **Phase id:** P1 (single phase)
- **Objective:** `flutter_lints: ^6.0.0` live; analyzer exit 0; every applied fix mechanical; deferrals recorded.
- **Responsible subagent:** middle-end
- **Files to change:** `pubspec.yaml` (1 dev-dep line), `pubspec.lock`, `analysis_options.yaml` (deferral comments only, if any), lib/test files with mechanical fixes (unknown count — findings-driven)
- **Implementation steps:**
  1. Bump `flutter_lints: ^4.0.0` → `^6.0.0` in dev_dependencies; `flutter pub upgrade flutter_lints lints`; confirm the lock resolves (lints 6.x).
  2. Run `flutter analyze`; record the full findings list (code, count, file:line).
  3. Resolve mechanically: `dart fix --apply --code=<code>` per code where a fix exists; otherwise non-behavioral edits only (const, annotations, whitespace-level). NO await additions, NO logic changes, NO `// ignore:` comments.
  4. **Defer non-mechanical lints lint-by-lint** (comment out in analysis_options with `# deferred — <reason>`) rather than weaken anything else; record every deferral in the phase report.
  5. Local validation: `flutter analyze` exit 0 (with 6.0's enabled set), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` → 222/222.
  6. **STOP-and-revert on any non-mechanical gap or deferral-threshold breach** (discipline above).
- **Acceptance criteria:** pubspec dev-dep at ^6.0.0; analyzer exit 0; 222/222; format idempotent; every fix mechanical (diff audit); deferrals documented with reasons.
- **Verification:** **CHEAP** — dev-dependency + mechanical/non-behavioral compliance (the cycle-4 classification precedent; lint enablement changes no runtime behavior, and mechanical fixes are non-behavioral by the discipline above). The definitive acceptance is the post-push CI watch.
- **Dependencies / sequencing:** single phase; nothing follows in this task.
- **Expected result:** the strict-lint floor raised to 6.0's enabled set; bloc 9's future diff inherits the scrutiny.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `chore(deps): adopt flutter_lints 6 with mechanical compliance (no behavior change)` — pubspec.yaml, pubspec.lock, analysis_options.yaml (deferrals only), the mechanical-fix files.
- Commit 2: `docs(plans): close cycle 10 and open cycle 11 plan` — stage `plans/` explicitly (deletion of old cycle-10 path, `plans/done/cycle-10-...md`, new cycle-11 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is IN-SCOPE for commit 1 (deferral comments only — any non-deferral diff = stop and report); no other pubspec constraints.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — the runner's analyze step now runs 6.0's enabled lint set (CRLF-independence + findings-parity with local), then the usual guards + format gate + 222/222 + APK build.
- **Promote to Landing** green as usual.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase. Do not retry or fix autonomously.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-12 audit (pre-ranked: **bloc 9 dedicated cycle** — the 99-match surface, EXPENSIVE, e2e required).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `flutter_lints 6.0.0 changelog new lints` (pub.dev/packages/flutter_lints — the exact lint delta 4→6, so findings are attributed to the right raise).
2. `dart fix apply lint codes availability` (dart.dev — mechanical-fix availability per surfaced code).
3. `flutter_lints 6 requires dart sdk minimum` (pub.dev — constraint compatibility with Dart 3.13.5 / Flutter 3.47.6).

## Reviewer verification commands (single pass, after P1)

1. `git diff pubspec.yaml` → exactly the 1 dev-dep line; `pubspec.lock` → flutter_lints 6.x + lints 6.x.
2. Lint-set audit: `flutter analyze` exit 0; list enabled-vs-deferred rules from analysis_options.yaml — every deferral has a recorded reason and count.
3. Mechanical-fix audit: every lib/test diff hunk is non-behavioral (const/annotation/formatting-level); zero await additions; zero `// ignore:`; zero logic changes.
4. Baseline gates: `flutter analyze` exit 0, `flutter test` 222/222, `dart format --output=none --set-exit-if-changed lib test` exit 0.
5. Scope: analysis_options.yaml diff = deferral comments only; .opencode/ absent; no other constraints touched.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-11 audit recorded; plan created `active` (task F11 part 3a — lints 6 alone; bloc 9 deliberately un-paired, 99-match surface noted). F6-residue note recorded (hashPassword outside tryUpgrade — low priority). |
| 2026-10-13 | **P1 IMPLEMENTED (zero findings), SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser independently verified: scope = pubspec.yaml 1 dev-dep line + lock 4/4 (flutter_lints 6.0.0 / lints 6.1.0 resolved); **analysis_options.yaml zero diff** (no deferrals needed — zero findings is credible given cycle-4 strict adoption + 10 clean analyzer cycles); lib/test untouched; gates re-run — analyze exit 0 under 6.0's enabled set, format 0 changed, 222/222. Reviewer's probe proof closes the lint-activity question (injected file fired 4/5 new codes — the 5th needs JS interop the repo lacks — then deleted, re-verified clean). Reviewer's version-line slip noted ("stays 1.2.4" parenthetical — actual version line unchanged at 1.2.3+6, which is the fact that matters). **Commit message AMENDED**: the planned "with mechanical compliance" clause was factually odd given zero fixes — ratified message: `chore(deps): adopt flutter_lints 6 — zero findings, no code changes`. Commits: that → `docs(plans): close cycle 10 and open cycle 11 plan`. Version bump: none; next tag carries 1.2.4. |
| 2026-10-13 | **Push EXECUTED** — `1058a0d` chore(deps) (amended message, byte-exact with em-dash; pubspec.yaml + lock only), `17122e4` docs(plans); remote main = `17122e4`; no version bump; tags untouched. |
| 2026-10-13 | **CI GREEN — PLAN CLOSED.** Build APK run **38400605101 SUCCESS (13m41s)**: the runner's analyze step ran **the strictest lint set this repo has shipped (flutter_lints 6) with zero findings**; format gate + 222/222 tests + APK build green; annotations informational only. Promote to Landing run **38402376817 SUCCESS (38s)**: full promotion path, no skip. Zombie run untouched (accepted). No failures → no fix phase. The analyzer is now hardened ahead of the bloc-9 migration — its diff will inherit the strictest scrutiny. Moved to `plans/done/`. |

- Cycle-12 pre-ranked: **flutter_bloc 9 dedicated cycle** (EXPENSIVE, e2e required — the 99-match surface; research BlocBase/Emitter API changes first, migration map before code). F11 part 3c small majors queue behind it.
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing user escalation (11 cycles). The ^11 fss follow-up remains gated on the user's next release tag.
- This plan is `done` only when P1 PASSes the single review, the push is Adviser-approved and executed, and BOTH workflows are green.
