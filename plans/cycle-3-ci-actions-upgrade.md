# Cycle 3 — GitHub Actions Deprecation Upgrade

**status:** active
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 3 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 59d060f
**predecessors:** plans/done/cycle-1-async-bug-fixes-analyzer-green.md, plans/done/cycle-2-dart-format-gate.md (both closed, CI green)

## Cycle 3 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` | **"No issues found!" exit 0** — held across cycles |
| `flutter test` | **208/208 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** — cycle-2 gate HELD (no drift since the gate went live) |
| `git status` (app scope) | clean — only `analysis_options.yaml` (F14 local-only) + plan artifacts |
| F10 stray artifacts | **RESOLVED** — `watch_out.txt`/`watch_done.txt` deleted locally (were gitignored; nothing to commit) |
| background_downloader | still **9.5.9** transitive — F17 precondition ("9.6.x taken") unmet; serialization pin stays |
| CI | runs 38287161921 / 38288748232 both green; annotations = **only the F3 items** (setup-java v4 deprecation, Node 20→24 for checkout@v4/setup-java@v4/upload-artifact@v4) — now the sole remaining CI debt |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F3** | **Deprecated GitHub Actions across BOTH workflows.** build-apk.yml: `actions/checkout@v4` (:23), `actions/setup-java@v4` (:25 — explicitly deprecated, "migrate to v5+"), `actions/upload-artifact@v4` (:371) — all on deprecated Node 20 runtime (forced Node 24). promote-landing.yml: `actions/checkout@v4` (:259) — same Node 20 debt. Last remaining CI-debt finding; every run logs the warnings. **SELECTED as the cycle-3 task.** | CI | run 38287161921 annotations; both workflow files | backend | CHEAP |
| **F14** | **Lint config bare-default + local-only analyzer-exclude stanza** (+9 lines, verified masks 0 Dart files; keeps re-appearing because newer SDKs auto-upgrade the file on every analyze run). Adopt include-first + add `unawaited_futures`/`discarded_futures`/`prefer_single_quotes`. | maintainability | working-tree diff; analysis_options.yaml | middle-end | CHEAP |
| **F9** | **docs/versioning.md drift**: "Existing tags: v1.0.0, v1.1.0. Current version: 1.1.0+2" vs pubspec 1.2.3+6 (and released tags since). | maintainability | docs/versioning.md:74 | middle-end | CHEAP |
| **F8** | **Dead Python test**: `tests/test_agenta_traceability_matrix_revision.py` tracked, never run by CI; companion `tools/revise_agenta_traceability_matrix.py`; `tests/__pycache__/` stray. Wire into CI or remove/relocate. | maintainability / tests | git ls-files; no Python step in workflows | backend | CHEAP |
| **F17** | **Kotlin serialization pin precondition unmet** — background_downloader still 9.5.9 transitive (needs 9.6.x per the settings.gradle removal comment). | maintainability | pubspec.lock (9.5.9); settings.gradle:20-29 | backend | CHEAP |
| **F11** | **Dependency drift**: 2 discontinued packages, 100 constraint-blocked updates (mind the documented win32/flutter_secure_storage pin, pubspec:27-30). | maintainability | pub resolution output (cycle 1) | middle-end | CHEAP |
| **F6** | **Local passwords = salted SHA-256** (no work factor); documented "minimum bar"; argon2/SQLCipher hardening path. | security | lib/services/auth/password_hasher.dart | security | EXPENSIVE |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — non-blocking CI deprecation warnings; upgrade = AGP 9 + Built-in-Kotlin migration. Deliberate deferral; needs a dedicated migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15** | **Tag-guard cannot catch duplicate-semver re-tagging** (documented process rule). Optional CI history check. | CI / logic | docs/versioning.md §6 | backend | CHEAP |
| **F16** | **promote-landing main-branch fallback can promote an older commit's APK** — accepted-risk, warned in logs. | CI | promote-landing.yml:123-145 | backend | CHEAP |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing escalation to the user.** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |
| ~~F10~~ | ~~Stray artifacts~~ **RESOLVED** (deleted locally in cycle 2; were untracked). | — | — | — | — |

Ranking rationale: no bug-class findings exist in analyzer/test ground truth; F3 is the last standing CI-debt item, appears in every run's annotations, and is a cheap, high-durability fix. F14 next (the local-only stanza is a recurring artifact source), then the cheap hygiene cluster (F9, F8, F17, F11).

---

## Selected task (single): F3 — migrate deprecated GitHub Actions

**Objective:** every `uses:` in both workflows runs on a current, non-deprecated runtime — zero Node-20/setup-java-v4 annotations in the next runs, no future hard break when Node 20 support is dropped.

**Targets (Adviser ruling, research-backed 2026-10-13):** current stable majors — `actions/checkout@v7` (latest v7.0.1), `actions/setup-java@v6` (latest v6.0.1; release explicitly fixes temurin 17 jobs), `actions/upload-artifact@v7` (latest v7.0.2). Rationale: landing on the deprecation-floor versions (v5) would leave a second upgrade cycle to do later; the inputs this repo uses are long-stable across these majors (checkout: none / repository+token+path+ref; setup-java: distribution+java-version; upload-artifact: name+path+retention-days + step-level `continue-on-error`). **Fallback clause:** if the Reviewer cannot verify input compatibility for a target major from release notes, that action drops to the highest version with verified compatibility (minimum: v5 — the deprecation-satisfying floor). Untouched by design: `softprops/action-gh-release@v2` and `subosito/flutter-action@v2` (no deprecation evidence).

**Version bump decision: none** — CI config only, no release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases are implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — since every phase below is **CHEAP-class, no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch (BOTH workflows green, annotations clean).

---

## Phase 1 — Action version bumps (F3)

- **Phase id:** P1 (single phase)
- **Objective:** zero deprecated `uses:` refs; both workflows parse; behavior unchanged for this repo's inputs.
- **Responsible subagent:** backend
- **Files to change:**
  - `.github/workflows/build-apk.yml` — 3 lines: `actions/checkout@v4` → `@v7`, `actions/setup-java@v4` → `@v6`, `actions/upload-artifact@v4` → `@v7`
  - `.github/workflows/promote-landing.yml` — 1 line: `actions/checkout@v4` → `@v7`
- **Implementation steps:**
  1. Apply the four version-ref bumps. Nothing else — no input changes, no step reordering, no comments needed beyond the existing ones.
  2. Sanity: `git diff` = exactly 4 version strings; no other `uses:` touched (`softprops/action-gh-release@v2`, `subosito/flutter-action@v2` remain).
  3. Validate YAML parses both files (PyYAML load or `gh workflow list` after push; local parse preferred).
  4. Grep `.github/` for remaining `@v4` action refs → must return none (for the three migrated actions).
- **Acceptance criteria:** diff scope exact (4 lines, 2 files); both workflows parse; no deprecated refs remain.
- **Verification:** **CHEAP** — CI config only, same class as cycle-1 P2 / cycle-2 P2; definitive proof is the post-push CI watch of BOTH workflows.
- **Dependencies / sequencing:** none — first and only phase.
- **Expected result:** next Build APK + Promote to Landing runs show no Node-20/setup-java-v4 annotations; both green.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `ci: upgrade GitHub Actions off deprecated Node 20 runtimes (checkout v7, setup-java v6, upload-artifact v7)` — the 2 workflow files.
- Commit 2: `docs(plans): close cycle 2 and open cycle 3 plan` — stage `plans/` explicitly (deletion of old cycle-2 path, `plans/done/cycle-2-...md`, new cycle-3 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: `analysis_options.yaml` (local-only until F14), all `.opencode/` churn (including the tracked `D .opencode/tasks.json`), any stray untracked files.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — now with **zero** Node-20/setup-java-v4 annotations; all existing guards (C1/C4/H9/H11/M15/M21), the `Enforce dart format` gate, analyze, tests, and the APK build must behave exactly as in run 38287161921.
- **Promote to Landing** must conclude green — its own checkout step (now @v7) is exercised for the first time here; expect the full promotion sequence as in run 38288748232.
- Any NEW deprecation annotations on the upgraded actions → record as a new backlog finding (do not silently accept).
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase (likely fallback per the clause above). Do not retry or fix autonomously.
- On green: Adviser marks the plan `done`, moves it to `plans/done/`, and opens the cycle-4 audit.

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `actions/checkout v5 v6 v7 release notes breaking changes` (github.com/actions/checkout/releases — verify inputs repository/token/path/ref unchanged v4→v7; note the node24 runtime move).
2. `actions/setup-java v6 release notes temurin 17` (github.com/actions/setup-java/releases — v6.0.1 explicitly fixes temurin 17 jobs; verify distribution/java-version inputs unchanged).
3. `actions/upload-artifact v5 v6 v7 release notes breaking changes` (github.com/actions/upload-artifact/releases — verify name/path/retention-days inputs and artifact behavior unchanged v4→v7).
4. `GitHub Actions Node 20 deprecation Node 24 migration` (github.blog changelog 2025-09-19 — the deprecation driving F3; confirm v5+ is the floor).

## Reviewer verification commands (single pass, after P1)

1. `git diff` inspection: exactly 4 version-ref lines across the 2 workflow files; no other changes.
2. YAML parse both workflows (PyYAML or equivalent).
3. Grep `.github/workflows/` for `checkout@v4|setup-java@v4|upload-artifact@v4` → zero matches; confirm `action-gh-release@v2` and `flutter-action@v2` untouched.
4. Baseline hygiene (tree untouched by this task, run for completeness): `flutter analyze` exit 0; `flutter test` 208/208; `dart format --output=none --set-exit-if-changed lib test` exit 0.
5. Fallback ruling if needed: for any action whose target-major input compatibility cannot be verified from release notes, direct the responsible agent to the highest verified version (floor v5).

## Cycle status

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-3 audit recorded; plan created `active` (task F3). |
| 2026-10-13 | **P1 IMPLEMENTED, SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser verified the diff: exactly 4 version-ref lines across 2 workflows (checkout@v7 ×2, setup-java@v6, upload-artifact@v7), zero remaining @v4 refs, inputs untouched, flutter-action@v2 + softprops@v2 untouched. Fallback clause NOT exercised. Reviewer primary-source verification: checkout v7 drop-in (fork-PR guard provably inapplicable here); setup-java v6.0.1 fixes temurin 17; upload-artifact v7 keeps name/path/retention-days; all three majors run node24 — and Node 20 was removed from runners 2026-09-23, so this bump clears an imminent HARD break, not just warnings (corrected citation slug: `2025-09-19-deprecation-of-node-20-on-github-actions-runners`; plan's original slug 404s). Baseline gates green (analyze, format 0 changed, 208/208). Commits approved: `ci: upgrade GitHub Actions off deprecated Node 20 runtimes (checkout v7, setup-java v6, upload-artifact v7)` then `docs(plans): close cycle 2 and open cycle 3 plan`. Version bump: none; next tag carries 1.2.4. |
| pending | agent-push: push main, watch BOTH workflows → Build APK green (all guards + format gate + analyze + tests + APK build, annotations clean of F3 items) AND Promote to Landing green (its checkout@v7 gets first real exercise: PAT guard, download, H9 guard, upload, URL verify, Vercel). On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-4 audit. On red: capture `gh run view --log-failed`, plan stays `active`, fix phase possibly invokes the fallback clause. |

## Backlog governance

- Cycle-4 pre-ranked top items: F14 (adopt the analyzer-exclude stanza + lint hardening — ends the recurring local diff), then the cheap hygiene cluster F9/F8/F17/F11 (candidates for one multi-phase hygiene task).
- **Future-workflow note (Reviewer flag, 2026-10-13):** checkout's allow-unsafe-pr-checkout fork-PR guard exists in v5.1.0+/v6.1.0+ (present in v7) — any future workflow adding `pull_request_target`/`workflow_run` fork checkouts must review that guard explicitly before landing.
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing escalation to the user before scheduling.
- This plan is `done` only when P1 PASSes the single review, the push is Adviser-approved and executed, and BOTH workflows are green with clean annotations.
