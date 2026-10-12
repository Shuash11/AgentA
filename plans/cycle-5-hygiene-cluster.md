# Cycle 5 — Repo Hygiene Cluster (versioning doc, dead Python tooling, stale run)

**status:** active
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 5 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ a56d320
**predecessors:** plans/done/cycle-1..4 (all closed, CI green; latest runs 38299699189 / 38301174361)

## Cycle 5 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` (strict lints active) | **"No issues found!" exit 0** — 5th consecutive clean cycle |
| `flutter test` | **208/208 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** — gate holding since cycle 2 |
| `git status` (app scope) | clean — only plan artifacts (analysis_options.yaml churn ENDED since F14) |
| Tags (ground truth for F9) | `git tag -l` → **v1.0.0, v1.1.0, v1.2.0, v1.2.1, v1.2.2, v1.2.3**; pubspec `1.2.3+6` |
| F8 evidence | `tests/test_agenta_traceability_matrix_revision.py` hardcodes `C:\Users\joashua\Downloads\…docx` absolute paths + third-party `docx` dependency; tests a Word-file revision tool (`tools/revise_agenta_traceability_matrix.py`), not the app — **never runnable in CI**, unrunnable on any other machine. Dead weight, delete-not-wire. |
| F19 | stale queued run **34749579707** (created 2026-09-13, SHA 7343c13) still queued |
| background_downloader | still 9.5.9 transitive — F17 precondition unmet, stays deferred |
| CI | runs 38299699189 / 38301174361 green; zero deprecation annotations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F9** | **docs/versioning.md stale release facts**: claims "Existing tags: v1.0.0, v1.1.0. Current version: 1.1.0+2" (:74) — reality: 6 tags (v1.0.0–v1.2.3) and version 1.2.3+6. The doc is the release checklist's reference. **SELECTED (cluster P1).** | maintainability | `git tag -l`, pubspec.yaml:4 vs docs/versioning.md:74 | middle-end | CHEAP |
| **F8** | **Dead Python tooling**: `tests/test_agenta_traceability_matrix_revision.py` + `tools/revise_agenta_traceability_matrix.py` — hardcoded developer-machine Downloads paths, `docx` dependency, tests a Word artifact, never in CI, unrunnable elsewhere. **SELECTED (cluster P2) — DELETE.** | maintainability / tests | file read (paths at :14-19); `git ls-files`; no Python step in workflows | backend | CHEAP |
| **F19** | **Stale queued workflow run 34749579707** (2026-09-13, SHA 7343c13) — can never complete against current main; CI noise. **SELECTED (cluster P3) — cancel.** | CI hygiene | agent-push reports, cycles 3-4 | backend | CHEAP |
| **F11** | **Dependency drift**: 2 discontinued packages, 100 constraint-blocked updates. **Deliberately EXCLUDED from this cluster** — dependency bumps interact with the documented win32/flutter_secure_storage pin (pubspec:27-30) and can change runtime behavior; belongs in its own carefully-validated cycle (pub upgrade + full suite + CI watch), not a hygiene batch. | maintainability | pub resolution output | middle-end | EXPENSIVE |
| **F17** | **Kotlin serialization pin** — precondition still unmet (background_downloader 9.5.9; needs 9.6.x). Stays deferred until the dependency bump happens. | maintainability | pubspec.lock; settings.gradle:20-29 | backend | CHEAP (after F11) |
| **F6** | **Local passwords = salted SHA-256** (no work factor); argon2/SQLCipher hardening path. | security | lib/services/auth/password_hasher.dart | security | EXPENSIVE |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — non-blocking; AGP 9 migration is a dedicated phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15** | **Tag-guard cannot catch duplicate-semver re-tagging** (documented process rule). Optional CI history check. | CI / logic | docs/versioning.md §6 | backend | CHEAP |
| **F16** | **promote-landing main-branch fallback can promote an older commit's APK** — accepted-risk, warned in logs. | CI | promote-landing.yml:123-145 | backend | CHEAP |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing escalation to the user.** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: analyzer/test ground truth clean for 5 consecutive cycles; the highest-impact remaining work is eliminating dead weight and stale facts that mislead future agents and release operators. The cluster is three small, zero-risk items bundled as ONE task (multi-phase precedent: cycle 1's F1+F2 pairing). F11 is explicitly deferred to its own cycle.

---

## Selected task (single): F9 + F8 + F19 — repo hygiene cluster

**Objective:** the release-checklist doc states true facts, the repo carries zero never-runnable tooling, and the Actions queue holds no ghost runs.

**Version bump decision: none** — docs/deletions/CI-queue action, no release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — since every phase below is **CHEAP-class, no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch (BOTH workflows green; behavior unchanged by design).

---

## Phase 1 — Refresh versioning doc to current release facts (F9)

- **Phase id:** P1
- **Objective:** docs/versioning.md states the true tag list and current version.
- **Responsible subagent:** middle-end
- **Files to change:** `docs/versioning.md`
- **Implementation steps:**
  1. Replace line 74's stale facts: "Existing tags: v1.0.0, v1.1.0. Current version: 1.1.0+2" → "Existing tags: v1.0.0, v1.1.0, v1.2.0, v1.2.1, v1.2.2, v1.2.3. Current version: 1.2.3+6" (ground truth: `git tag -l`, pubspec.yaml:4).
  2. Scan the rest of the doc for other factually stale claims (examples in §1 are illustrative — leave; the release process itself is unchanged — verify steps still match build-apk.yml reality, e.g. workflow step names quoted in §2/§7 exist: "Assert v* tag matches pubspec version", `softprops/action-gh-release@v2`). Fix only factual drift; no restructure, no style rewrite.
  3. Cross-check (read-only): `gh release list` should show releases matching the tags — note any mismatch in the PR/report (do NOT fix release state from here; that's a separate concern).
- **Acceptance criteria:** doc facts == `git tag -l` + pubspec; no other content changed; quoted workflow step names verified to exist.
- **Verification:** **CHEAP** — factual doc correction against repo evidence.
- **Dependencies / sequencing:** first.
- **Expected result:** release operators and agents stop reading wrong version facts.

## Phase 2 — Delete dead traceability-matrix Python tooling (F8)

- **Phase id:** P2
- **Objective:** zero never-runnable test/tool files in the repo.
- **Responsible subagent:** backend
- **Files to change:** DELETE `tests/test_agenta_traceability_matrix_revision.py`, `tools/revise_agenta_traceability_matrix.py`; locally delete `tests/__pycache__/` (untracked residue). `tools/` keeps its PowerShell utilities (create_code_pdf.ps1 etc. — unrelated, untouched). If `tests/` becomes empty, remove the directory too.
- **Implementation steps:**
  1. `git rm tests/test_agenta_traceability_matrix_revision.py tools/revise_agenta_traceability_matrix.py`.
  2. Grep the repo (lib/, test/, tools/, docs/, .github/) for references to either filename or "traceability_matrix" → must return zero references after deletion (the two files referenced only each other + a Downloads docx).
  3. Confirm the Dart test suite is untouched: `flutter test` → 208/208 (Python was never part of it — M15 CI guard counts only `flutter test`).
  4. Delete local `tests/__pycache__/` (untracked; not gitignored — remove so it can't reappear as noise).
- **Acceptance criteria:** both files gone from the index; zero references repo-wide; Dart tests 208/208; tools/ PowerShell utilities intact.
- **Verification:** **CHEAP** — deletion of proven-dead files (evidence: hardcoded Downloads paths, docx dependency, no CI runner).
- **Dependencies / sequencing:** independent of P1; before P3 for tidy batching.
- **Expected result:** no false sense of coverage; no developer-machine-specific paths in the repo.

## Phase 3 — Cancel the stale queued workflow run (F19)

- **Phase id:** P3
- **Objective:** the Actions queue holds no ghost runs.
- **Responsible subagent:** backend
- **Files to change:** none — repository action via `gh` CLI.
- **Implementation steps:**
  1. `gh run cancel 34749579707 --repo Shuash11/AgentA` (created 2026-09-13, SHA 7343c13 — predates every current workflow; it can never complete against current main).
  2. Verify: `gh run view 34749579707 --repo Shuash11/AgentA --json status,conclusion` → status completed, conclusion cancelled. If the API refuses (run already expired/auto-dismissed), record the final state as the acceptance evidence.
  3. No commit, no workflow-file change.
- **Acceptance criteria:** run no longer in queued/pending state; final state recorded in the phase report.
- **Verification:** **CHEAP** — single CLI action + state read-back.
- **Dependencies / sequencing:** last (batched with the push cycle; can execute any time before plan closure).
- **Expected result:** clean Actions queue.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `docs: refresh versioning doc to current release facts (tags v1.0.0-v1.2.3, version 1.2.3+6)` — docs/versioning.md.
- Commit 2: `chore: remove dead traceability-matrix python tooling (never runnable in CI)` — the two deletions.
- Commit 3: `docs(plans): close cycle 4 and open cycle 5 plan` — stage `plans/` explicitly (deletion of old cycle-4 path, `plans/done/cycle-4-...md`, new cycle-5 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (expect NO local diff — if one appears, stop and report); any stray untracked files.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** green exactly as run 38299699189 (guards + format gate + analyze with strict lints + tests + APK build); **Promote to Landing** green as run 38301174361. Behavior is unchanged by design — this cycle is docs/deletions only.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-6 audit.

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `gh run cancel stale queued workflow run GitHub CLI` (cli.github.com manual / docs.github.com — confirm cancel semantics for a long-queued run and what conclusion it lands on). This is the only web-dependent fact in the plan; P1/P2 are repo-internal facts verified via git/pubspec/grep evidence (no web research genuinely applicable — noted per the web-research skill's scoping rule).

## Reviewer verification commands (single pass, after P1+P2+P3)

1. `git tag -l` + `Select-String pubspec.yaml '^version:'` vs docs/versioning.md:74 → facts match; `gh release list` cross-check noted.
2. `git ls-files | Select-String 'traceability|\.py$'` → zero matches; repo-wide grep for "traceability_matrix" → zero references; tools/ PowerShell files still present.
3. `gh run view 34749579707 --json status,conclusion` → completed/cancelled (or recorded expiry state).
4. Baseline gates: `flutter analyze` exit 0 (strict lints), `flutter test` 208/208, `dart format --output=none --set-exit-if-changed lib test` exit 0.
5. Diff audit: C1 = docs/versioning.md factual lines only; C2 = exactly two deletions; no other content touched.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-5 audit recorded; plan created `active` (task F9+F8+F19 cluster). F11 explicitly deferred to its own cycle (risk rationale recorded). F17 stays precondition-blocked. |
| 2026-10-13 | **P1-P3 IMPLEMENTED, SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser verified: staged deletions = exactly the 2 dead Python files; versioning.md diff = the single factual line (tags v1.0.0–v1.2.3, version 1.2.3+6 — matches `git tag -l` + pubspec ground truth from the audit); zero live references (only hits = historical `docs/superpowers/plans/2026-08-03-…` archive — correctly untouched); no tracked `.py` remains; analysis_options.yaml has NO local diff (stop-condition not triggered); gates re-run independently — analyze exit 0, format 0 changed, 208/208. **P3 executed-to-fallback (ACCEPTED):** `gh run cancel 34749579707` refused — "Cannot cancel a workflow run that is completed" (409 terminal-state path, Reviewer-validated against docs.github.com REST docs + gh CLI manual); the plan's refusal-fallback was the correct procedure. **Zombie-run ruling: ACCEPT AS COSMETIC NOISE** — the public `queued` record persists and is unremovable within authorized actions; the run-deletion API is noted as a possible future one-liner ONLY if CI noise ever matters (it rewrites Actions audit history for zero functional gain — not authorized now). P3 acceptance evidence = the refusal + Reviewer's documentation validation. Commits approved: `docs: refresh versioning doc to current release facts (tags v1.0.0-v1.2.3, version 1.2.3+6)` / `chore: remove dead traceability-matrix python tooling (never runnable in CI)` (deletions already staged) / `docs(plans): close cycle 4 and open cycle 5 plan`. Version bump: none; next tag carries 1.2.4. |
| pending | agent-push: push main (note: C2's deletions are already staged — commit directly), watch BOTH workflows → Build APK green (behavior unchanged by design: docs + dead-file deletions only), Promote to Landing green. On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-6 audit (pre-ranked: F11 own cycle, then F15/F16). On red: capture `gh run view --log-failed`, plan stays `active`, fix phase planned. |

- Cycle-6 pre-ranked: F11 (dependency drift — own cycle, careful validation), then F15/F16 (CI hardening notes) if desired; EXPENSIVE items F6/F18/F13 remain queued.
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing escalation to the user before scheduling.
- This plan is `done` only when P1-P3 PASS the single review, the push is Adviser-approved and executed, and BOTH workflows are green.
