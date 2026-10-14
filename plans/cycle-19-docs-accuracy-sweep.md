# Cycle 19 — Docs-Accuracy Sweep (README nits + bounded docs truth pass) — the frontier cycle

**status:** active
**created:** 2026-10-14
**created by:** Adviser (self-improvement cycle 19 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ c707dc2
**predecessors:** plans/done/cycle-1..18 (all closed, CI green; latest runs 38539290547 / 38540829369)

## Cycle 19 ground truth (fresh evidence, 2026-10-14)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 19th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| `flutter pub outdated` | **ONLY the gated ^11 fss 11.2.0** — the voluntary dependency queue is EMPTY |
| **Docs sweep probes** | docs/*.md essentially truthful (backend-rls.md carries the corrected post-cycle-15 text; versioning.md's `1.1.0+2` mentions are illustrative examples; google-signin-setup.md `.env` row fixed in cycle 16). **README.md:44 `flutter_launcher_icons: ^0.13.1` (stale example version) + :62 `flutter pub run flutter_launcher_icons:main` (legacy invocation — current is `dart run flutter_launcher_icons`)** — the confirmed remaining docs debt. |
| Runner watch (F18) | Cycle 18's run executed on **Ubuntu 24.04** — Ubuntu 26 migration (~Oct 19, 5 days out) NOTICE-ONLY; first post-date run is the watch point. |
| CI | runs 38539290547 / 38540829369 green; zero deprecations |

## Findings backlog (re-ranked, uncapped) — THE FRONTIER STATEMENT

**THE FRONTIER (per the cycle-18 flag):** with the small-majors queue empty and F13 closed, the remaining backlog is:

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F24** *(new)* | **README launcher-icons how-to stale (2 lines)**: :44 `^0.13.1` example + :62 legacy `flutter pub run flutter_launcher_icons:main` invocation (current: `dart run flutter_launcher_icons`). **SELECTED as the cycle-19 task**, extended into a bounded docs-accuracy sweep (README + docs/*.md claims vs repo reality). | docs | grep evidence above | middle-end | CHEAP |
| **F18** | **AGP-9 + Built-in-Kotlin toolchain migration — DEFERRED WITH A DEFINED TRIGGER** (Adviser ruling below): execute when (a) a future Flutter release turns the checker warns (Gradle < 9.1.0 / AGP < 9.0.1) into errors, (b) the user requests it, or (c) the non-gated queue is otherwise empty AND the runner-migration picture is stable. Until then the warn is non-blocking and the migration is the loop's single largest risk item — not the best use of a cycle without a forcing function. Also tracks the Ubuntu 26 runner migration (notice-only Oct 14; due ~Oct 19; first post-date run = watch point). | CI / toolchain | DependencyVersionChecker.kt warn values; runner observation | backend | EXPENSIVE |
| **F6-residue** | `hashPassword` outside `tryUpgrade`'s try — theoretical only (disproven by golden vector + 222 tests); auth-path change → EXPENSIVE ceremony. **Fold into the next auth-path touch** (ruling reaffirmed; not a standalone cycle). | security (nit) | cycle-10 review | middle-end | EXPENSIVE (as standalone) |
| **F11 part 4** | ^11 fss `checkUpgradeStatus()` follow-up — **GATED on the user cutting the next release tag**. | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **B2** | Desktop-identity — **PARKED pending user direction** (inert until desktop builds ship). | branding | cycle-17 ruling | — | CHEAP (when triggered) |
| **F15 residue / F16 / F19** | Guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (19 cycles). The single biggest blocker to remaining value.** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

## THE FRONTIER RULING (proceed/pause — binding, stated as the audit outcome)

**RULING: THE CODEBASE HAS REACHED THE CLEAN STATE THE DIRECTIVE TARGETS; THE LOOP CONTINUES ON LEGITIMATE WORK, AND THE USER DECISIONS ARE ESCALATED AS THE PRIMARY PATH TO FURTHER VALUE.**

- The evidence: 19 consecutive clean cycles; analyzer clean under the strictest lint set; 222/222; zero dead dependencies; docs truthful (post this cycle's sweep); CI green on every push; the entire voluntary dependency queue empty.
- **F18 is DEFERRED, not abandoned** — with the defined trigger above. Executing the AGP-9/Built-in-Kotlin migration now would spend the loop's largest risk budget on a non-urgent modernization while the genuinely valuable items sit behind user decisions. That is not the best use of continuing cycles.
- **The user decisions are the critical path** — escalated here THROUGH the Orchestrator for user action: (1) **cut the next release tag** (v1.2.4) — this ships 12 cycles of improvements AND unlocks the ^11 fss follow-up; (2) **grant live Supabase access** — unblocks F4/F5/F12 (19 cycles blocked); (3) **rule on desktop identity** (B2) — park permanently or schedule.
- **The loop continues productively** (per the standing directive): this cycle executes the docs-accuracy sweep; subsequent cycles become verification/watch cycles (post-Oct-19 runner, first post-tag ^11 readiness) and execute any newly surfaced findings — the standing directive stands; only the user stops the loop.

---

## Selected task (single): F24 — README launcher-icons fix + bounded docs-accuracy sweep

**Objective:** the README how-to matches the repo's actual toolchain (0.14.4 + `dart run`); every factual claim in README.md + docs/*.md verified against repo reality (or explicitly illustrative); zero docs debt remaining.

**Version bump decision: none** — docs-only changes are not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — since the phase below is **CHEAP-class, no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch.

**SWEEP SCOPE GUARD (binding):** the sweep covers README.md + docs/*.md (6 files) and verifies FACTUAL claims (versions, paths, commands, counts, file references) against repo reality. Illustrative examples (e.g., versioning.md's `1.1.0+2` scheme examples) are LEFT ALONE unless actively misleading. Anything requiring CODE changes to make true → record as a backlog finding, do NOT change code. Historical archives (docs/superpowers/) are out of scope.

---

## Phase 1 — README fix + bounded docs-accuracy sweep

- **Phase id:** P1 (single phase)
- **Objective:** README how-to current; all factual docs claims verified or fixed.
- **Responsible subagent:** middle-end
- **Files to change:** `README.md` (:44 → `flutter_launcher_icons: ^0.14.4`; :62 → `dart run flutter_launcher_icons`), plus any docs/*.md line where the sweep finds factual drift (findings-driven — expected small)
- **Implementation steps:**
  1. README:44 — update the example version to `^0.14.4` (matching pubspec).
  2. README:62 — `flutter pub run flutter_launcher_icons:main` → `dart run flutter_launcher_icons` (the current invocation; cite the package README).
  3. Bounded sweep: for each of README.md + docs/backend-rls.md, error-hygiene.md, google-signin-setup.md, sync.md, versioning.md — verify factual claims (file paths exist, command examples current, counts/versions match reality, no references to removed things: dotenv/.env-fallback, cupertino, AI Skill Coach, kaggle). Fix factual drift; leave illustrative examples; record any code-required truths as backlog findings instead of changing code.
  4. Local validation: `flutter analyze` exit 0, `flutter test` → 222/222 (docs changes cannot affect them — run as hygiene), format gate irrelevant to .md but run anyway for uniformity.
  5. Repo-wide grep proof: zero stale-pattern matches in the swept files (patterns per the verification commands below).
- **Acceptance criteria:** README lines current; sweep findings either fixed (docs-only) or recorded as backlog (code-required); gates green.
- **Verification:** **CHEAP** — docs copy; no behavior surface.
- **Dependencies / sequencing:** single phase.
- **Expected result:** zero docs debt; the documentation states the truth about the toolchain, config model, and brand.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `docs: refresh launcher-icons how-to and sweep docs accuracy (F24)` — README.md + any docs/*.md drift fixes.
- Commit 2: `docs(plans): close cycle 18 and open cycle 19 plan` — stage `plans/` explicitly (deletion of old cycle-18 path, `plans/done/cycle-18-...md`, new cycle-19 file). Never root-wide `git add -A`/`git add .`
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); historical archives (docs/superpowers/) untouched; internal identifiers untouched.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — identical profile (docs-only; the run also serves as the **F18 Ubuntu 26 watch point** if it lands post-Oct 19: record any runner-image/toolchain deltas, observe only).
- **Promote to Landing** green as usual.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-20 audit — which should open with **the user-decision escalation as its first agenda item** (release tag / Supabase access / desktop direction), because the non-gated queue will then contain only F18 (deferred-with-trigger) and F6-residue (fold-into-auth-touch).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `flutter_launcher_icons dart run invocation current` (pub.dev README — verify `dart run flutter_launcher_icons` is the current invocation form for 0.14.x; load-bearing for README:62).

## Reviewer verification commands (single pass, after P1)

1. README audit: `git diff README.md` → the 2 designed lines (plus sweep fixes if any, each citeable).
2. Sweep audit: the swept-files list + per-file findings table (fixed vs illustrative-left vs backlog-recorded); zero unexplained diffs.
3. Stale-pattern greps: `AI Skill Coach|dotenv|cupertino_icons|1\.1\.0\+2` in swept files → only legitimate/illustrative/contextual mentions (each accounted for).
4. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` 222/222, `dart format --output=none --set-exit-if-changed lib test` exit 0.
5. Scope: docs + README only; analysis_options.yaml absent; .opencode/ absent; historical archives untouched.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-14 | Cycle-19 audit recorded; plan created `active` (task F24 — README fix + bounded docs sweep). **THE FRONTIER RULING stated: codebase at the clean state; F18 deferred-with-trigger; user decisions escalated as the critical path (release tag → ships 12 cycles of work + unlocks ^11; Supabase access → unblocks F4/F5/F12; desktop direction → B2).** The loop continues on legitimate work. |
| 2026-10-14 | **P1 IMPLEMENTED (docs sweep), SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser independently verified: scope = exactly 4 docs files + plans artifacts (**zero code/config/workflow changes**); README = the 2 designed lines (:44 `^0.14.4`, :62 `dart run flutter_launcher_icons`) + the §5 sweep fix (the `.env`-fallback claim replaced with the dart-define truth, `.env.example` repositioned as the key reference — a legitimate in-scope sweep finding); docs = backend-rls 3/2 (exact CI step name vs build-apk.yml:45), error-hygiene 1/1 (actual `_initializeApp` row vs main.dart:143-155), versioning 4/3 (tag wording softened — ACCEPT: reverting would restore a false statement; the load-bearing invariant is unchanged and `git tag -a` convention preserved); gates re-run — analyze exit 0, format 0 changed, 222/222. Sweep-clean files verified (google-signin-setup + sync: 6+8 claims checked). **Backlog rulings at closure:** (1) the 8 display-only ".env" UI strings → **PARKED display-only-accepted**, fold into the next UI-copy touch if one occurs (no standalone cycle — display copy referencing the key-reference file remains user-helpful); (2) the mixed tag-annotation observation (3 annotated / 3 lightweight) → **convention note only, no action** — the load-bearing invariants (tag == pubspec version; no duplicate-semver) are CI-enforced regardless of annotation type. Commits: `docs: refresh launcher-icons how-to and sweep docs accuracy (F24)` / `docs(plans): close cycle 18 and open cycle 19 plan`. Version bump: none; next tag carries 1.2.4 and unlocks the ^11 fss follow-up. |
| pending | agent-push: push main (2 commits), watch BOTH workflows → **Build APK green — identical profile expected (docs-only)**; the run doubles as the **F18 Ubuntu-26 watch** (still 24.04 as of cycle 18 — observe and record only); Promote to Landing green as usual. On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-20 audit — **first agenda item: the user-decision escalation** (release tag → ships the backlog + unlocks ^11; Supabase access → unblocks F4/F5/F12; desktop direction → B2), then verification/watch items (post-Oct-19 runner, first post-tag ^11 readiness) and any newly surfaced findings. On red: capture `gh run view --log-failed`, plan stays `active`, fix phase planned. |

- Cycle-20 pre-ranked: **the user-decision escalation as first agenda item**, then verification/watch items (post-Oct-19 runner, first post-tag ^11 readiness) and any newly surfaced findings.
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing user escalation (19 cycles). The ^11 fss follow-up remains gated on the user's next release tag. B2 remains parked.
- This plan is `done` only when P1 PASSes the single review, the push is Adviser-approved and executed, and BOTH workflows are green.
