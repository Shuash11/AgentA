# Cycle 2 — Dart Format Compliance + CI Format Gate

**status:** active
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 2 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ dd65308
**predecessor:** plans/done/cycle-1-async-bug-fixes-analyzer-green.md (closed 2026-10-13, CI green)

## Cycle 2 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` | **"No issues found!" exit 0** — cycle-1 P1 fix held; zero bug-class findings in analyzer ground truth |
| `flutter test` | **208/208 "All tests passed!" exit 0** |
| `dart format --set-exit-if-changed --output=none lib test` | **FAIL — 80/89 files unformatted** (F7 stands) |
| `git status` (app scope) | clean — only `analysis_options.yaml` (local-only per F14 ruling) + plan artifacts |
| background_downloader (F17 precondition) | still **9.5.9 transitive** (pubspec.lock:83) — "9.6.x taken" precondition NOT met; serialization pin in `settings.gradle` stays |
| `watch_out.txt` / `watch_done.txt` | still present at root (F10) |
| `docs/versioning.md` | still says "Current version: 1.1.0+2" vs pubspec 1.2.3+6 (F9) |
| CI (runs 38276659204 / 38278175241) | both green on Flutter 3.47.6 — baseline for this cycle's gate |
| New note | Gradle 8.14 / AGP 8.11.1 now sit **below Flutter's warn thresholds** (9.1.0 / 9.0.1) — CI logs non-blocking deprecation warnings; upgrade path is the AGP 9 + Built-in-Kotlin migration (deliberate deferral, see backlog F18) |

## Findings backlog (re-ranked, uncapped; carry-over + new)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F7** | **dart format violations 80/89 lib+test files; no CI format gate.** Format-only reformat + one CI step. Selected as the cycle-2 task (see phases below). | maintainability | `dart format` FAIL above | middle-end / backend | CHEAP |
| **F3** | **Deprecated GitHub Actions** in build-apk.yml: `actions/setup-java@v4` → v5; `checkout@v4`/`upload-artifact@v4` target Node 20 (forced Node 24). Will hard-fail when Node 20 support drops. Next cycle's cheap win. | CI | run 38276659204 annotations | backend | CHEAP |
| **F8** | **Dead Python test**: `tests/test_agenta_traceability_matrix_revision.py` tracked, never run by CI; `tools/revise_agenta_traceability_matrix.py`; `tests/__pycache__/` stray. Wire into CI or remove/relocate. | maintainability / tests | git ls-files; no Python step in workflows | backend | CHEAP |
| **F9** | **docs/versioning.md drift**: "Existing tags: v1.0.0, v1.1.0. Current version: 1.1.0+2" vs pubspec 1.2.3+6. | maintainability | docs/versioning.md:74 | middle-end | CHEAP |
| **F10** | **Stray local artifacts** `watch_out.txt` / `watch_done.txt` (untracked, gitignored). Local delete; no commit. | maintainability | root listing | backend | CHEAP |
| **F14** | **Lint config bare-default + uncommitted analyzer-exclude stanza.** Adopt the +9-line `analyzer.exclude` (include-first ordering) and consider `unawaited_futures`/`discarded_futures`/`prefer_single_quotes`. | maintainability | working-tree diff; analysis_options.yaml | middle-end | CHEAP |
| **F17** | **Kotlin serialization pin precondition unmet.** background_downloader still 9.5.9 (needs 9.6.x for the pin's removal comment to apply). Transitive-dependency bump first. | maintainability | pubspec.lock:83 = 9.5.9; settings.gradle comment | backend | CHEAP |
| **F11** | **Dependency drift**: 2 discontinued packages, 100 constraint-blocked updates (mind the documented win32/flutter_secure_storage pin, pubspec:27-30). | maintainability | pub resolution output (cycle 1) | middle-end | CHEAP |
| **F6** | **Local passwords = salted SHA-256** (no work factor). Documented "minimum bar"; hardening backlog (argon2/SQLCipher path). | security | lib/services/auth/password_hasher.dart | security | EXPENSIVE |
| **F4** | **Supabase schema not version-controlled** (only RLS migration; tables live in cloud). **CLOUD-BLOCKED — escalate to user.** | contract | supabase/migrations/ | backend | EXPENSIVE |
| **F5** | **H8 recovery-code RPC not deployed** (client-side hash compare). **CLOUD-BLOCKED — escalate to user.** | security | user_repository.dart:72-80 | security | EXPENSIVE |
| **F12** | **Offline signups never sync** (Edge Function stub). **CLOUD-BLOCKED — escalate to user.** | logic | sync_service.dart:293-306 | backend | EXPENSIVE |
| **F18** *(new)* | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — CI logs non-blocking deprecation warnings. Upgrade path = AGP 9 + Built-in-Kotlin migration (repo carries `android.builtInKotlin=false`/`newDsl=false` migrator flags). Deliberate deferral from cycle 1; schedule only with a dedicated migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values; android/gradle.properties | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW perf/robustness. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15** | **Tag-guard cannot catch duplicate-semver re-tagging** (documented process rule). Optional CI history check. | CI / logic | docs/versioning.md §6 | backend | CHEAP |
| **F16** | **promote-landing main-branch fallback can promote an older commit's APK** — accepted-risk note, warned in logs. | CI | promote-landing.yml:123-145 | backend | CHEAP |

Ranking rationale: user directive is bug-first — the fresh diagnostics show **no bug-class findings remaining** in analyzer/test ground truth, so the highest-impact items are the durability plays that keep it that way. F7 tops the list: it fixes 80 files of drift AND installs the gate that prevents recurrence, at zero behavior risk.

---

## Selected task (single): F7 — dart format compliance + CI format gate

**Objective:** every lib/ and test/ file is `dart format`-clean and CI enforces it, so formatting drift can never re-accumulate and review diffs stay semantic.

**Version bump decision: none** — formatting + CI config only, no release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding for this cycle, per user directive):** ALL phases below are implemented first, completely, by their owners. Per-phase gates are NOT run mid-plan. Afterwards, e2e-tester and Reviewer are triggered **ONCE each over the whole plan** — and since **every phase is CHEAP-class, no e2e run occurs**; the Reviewer executes the verification commands itself. The definitive acceptance is the post-push CI watch (Build APK green with the new format step), performed by agent-push after the Adviser's push confirmation.

---

## Phase 1 — Repo-wide dart format (F7 part 1)

- **Phase id:** P1
- **Objective:** `dart format --output=none --set-exit-if-changed lib test` exits 0 AND `flutter analyze` exits 0 on the completed tree; diff is format-only **plus** the mechanical lint compliance the formatting itself necessitates.
- **Responsible subagent:** middle-end
- **Files to change:** ~80 files under `lib/` and `test/` (formatter output) **+ 12 lib files receiving 30 canonical brace wraps** (see step 2) — no other edits, no semantic changes
- **Implementation steps:**
  1. Run `dart format lib test` (one shot; expect ~80 files changed).
  2. **AUTHORIZED ADDENDUM (Adviser ruling 2026-10-13):** run `dart fix --apply --code=curly_braces_in_flow_control_structures lib` — exactly **30 mechanical brace wraps across 12 lib files** (0 test files). Rationale: the formatter splits over-80-char one-liners like `if (kDebugMode) debugPrint('…');`, which forfeits `curly_braces_in_flow_control_structures`' same-line-body exemption → 30 info-level lints, analyze exit 1 (Adviser-verified on the live tree: "30 issues found", all this one code). Plain CI `flutter analyze` treats infos as fatal, so the addendum is required to keep this cycle's definitive acceptance (green Build APK) reachable. `dart fix --code=` is deterministic, canonical `if (x) { stmt; }` wrapping, semantics-neutral. Rejected alternatives (unsound): disabling the lint or `--no-fatal-infos` (weakens gates / touches analysis_options.yaml, local-only per F14); reverting format (the infos come FROM format).
  3. Sanity-check the diff is mechanical-only: `git diff --stat` touches only `.dart` files under lib/ and test/; spot-check diffs for format/brace-wrap-only changes.
  4. Run `flutter analyze` (expect exit 0) and `flutter test` (expect 208/208) as local sanity — informational, not a per-phase gate (single-pass rule).
  5. Re-run `dart format --output=none --set-exit-if-changed lib test` → must be idempotent (exit 0, "0 changed"); re-run `flutter analyze` → still 0 issues (format-after-fix must not resurrect one-liners).
- **Acceptance criteria:** format idempotent; **`flutter analyze` exit 0 on the completed P1 tree** (the 30 format-introduced infos resolved by the authorized addendum); 208/208 tests; diff contains no manual/semantic edits beyond formatter output + the 30 canonical brace wraps.
- **Verification:** **CHEAP** — static/cosmetic styling, explicitly non-functional per the Adviser classification rules.
- **Dependencies / sequencing:** first; P2's gate would fail CI without it.
- **Expected result:** whole repo formatter-clean.

## Phase 2 — CI format gate (F7 part 2)

- **Phase id:** P2
- **Objective:** CI fails on future formatting drift before analyze runs.
- **Responsible subagent:** backend
- **Files to change:** `.github/workflows/build-apk.yml` (one new step)
- **Implementation steps:**
  1. Insert a step named `Enforce dart format` immediately after `- run: flutter pub get` and before `- run: flutter analyze`, with `run: dart format --output=none --set-exit-if-changed lib test`.
  2. Nothing else changes — no version bumps, no other steps reordered.
- **Acceptance criteria:** `git diff` = the one step; YAML parses (workflow lists via `gh workflow list`); step placement before analyze.
- **Verification:** **CHEAP** — CI config only (same class as cycle-1 P2); definitive proof is the post-push CI watch.
- **Dependencies / sequencing:** after P1 (the gate would red CI otherwise).
- **Expected result:** format drift becomes a CI failure from now on.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1 (amended per Adviser ruling 2026-10-13): `refactor: apply dart format and brace-wrap lint compliance (no behavior change)` — P1 files. **Single commit containing BOTH the format pass and the 30 authorized `dart fix` brace wraps** — bisect hygiene: an intermediate format-only commit would fail the repo's own analyze gate (30 infos), and a known-red commit must never enter history. Body: "80 files formatted; 30 mechanical if-block wraps via dart fix --code=curly_braces_in_flow_control_structures (format side effect, Adviser-authorized); flutter analyze exit 0; 208/208 tests."
- Commit 2: `ci: enforce dart format gate in Build APK` — build-apk.yml.
- Commit 3: `docs(plans): close cycle 1 and open cycle 2 plan` — move of `plans/cycle-1-...md` → `plans/done/` + this file.
- Exclusions: `analysis_options.yaml` (local-only until F14), all `.opencode/` churn, stray artifacts (F10 — delete locally, never commit), anything else untracked.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green including the new `Enforce dart format` step** (and analyze/tests/APK steps as before). Watch to conclusion.
- **Promote to Landing** expected to run on success (pattern proven in run 38278175241); PAT-less skip-with-warning acceptable, hard failure is not.
- F3 annotations (setup-java v4, Node 20) remain non-blocking until that backlog item lands.
- On red: capture `gh run view --log-failed`, plan stays `active`, next fix phase planned by the Adviser.

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `dart format --set-exit-if-changed flag semantics` (dart.dev — confirm non-mutating check + exit code behavior).
2. `Dart official code formatting style guide dart format` (dart.dev — confirm dart format IS the official style; no alternative formatter).
3. `subosito/flutter-action dart CLI in workflow steps` (github.com/subosito/flutter-action README — confirm the Flutter-installed `dart` is on PATH for later steps without extra setup).

## Reviewer verification commands (single pass, after both phases)

1. `dart format --output=none --set-exit-if-changed lib test` → exit 0.
2. `flutter analyze` → "No issues found!" exit 0; `flutter test` → "All tests passed!".
3. `git diff` inspection: P1 diff format-only + brace wraps (spot-check); P2 diff = one step in the right position.
4. **Brace-addendum audit (Adviser ruling 2026-10-13):** verify all 30 brace wraps are the canonical `if (x) { stmt; }` pattern ONLY — determinism check: in a throwaway copy of HEAD, run `dart format lib test` then `dart fix --apply --code=curly_braces_in_flow_control_structures lib` and byte-compare against the committed result (must match; `dart fix --code=` is deterministic). Confirm: exactly 12 lib files, 0 test files touched by the brace fix; 0 `// ignore:` comments added; 0 analysis_options changes; 0 other lint codes or manual edits in the diff.
5. Confirm the plan-file move is complete (cycle-1 in `plans/done/`, this file `active`).

## Backlog governance

## Cycle status

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-2 audit recorded; plan created `active` (task F7). |
| 2026-10-13 | **P1 BLOCKER + RULING** — format pass introduced 30 `curly_braces_in_flow_control_structures` infos (12 lib files), analyze exit 1, would red CI. Adviser verified ground truth on the live tree (30 issues, one code, exit 1). **RULING: BRACE-FIX AUTHORIZED** — `dart fix --apply --code=curly_braces_in_flow_control_structures` addendum folded into P1; single `refactor:` commit (no known-red intermediate); Reviewer determinism audit specified. Alternatives (lint disable / --no-fatal-infos / revert format) rejected as gate-weakening or self-defeating. |
| 2026-10-13 | **P1 + P2 IMPLEMENTED, SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser independently re-ran all gates on the commit-bound tree: format idempotent (0 changed, exit 0), analyze "No issues found!" exit 0, 208/208 tests. Scope verified: 80 .dart files (64 lib + 16 test), P2 = +2 lines correctly placed (after `flutter pub get`, before `flutter analyze`), brace addendum = 12 lib files / 0 test files (Reviewer determinism audit: replica-of-HEAD + format + dart fix byte-identical to tree, 0 mismatches). Commits approved: `refactor: apply dart format and brace-wrap lint compliance (no behavior change)` / `ci: enforce dart format gate in Build APK` / `docs(plans): close cycle 1 and open cycle 2 plan` (stage `plans/` explicitly — deletion, `plans/done/` move, new cycle-2 file; never root-wide add). Version bump: none; next tag carries 1.2.4. |
| pending | agent-push: push main, watch Build APK → green **including the new `Enforce dart format` step** (definitive acceptance), expect Promote to Landing on success. F3 annotations non-blocking. On green: Adviser marks plan `done`, moves to `plans/done/`. On red: capture `gh run view --log-failed`, plan stays `active`, fix phase planned. |

- F3 is the pre-ranked top item for cycle 3 (cheap, quick); then F8/F9/F10/F14/F17.
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase project access (deploy/introspect) required; escalate to the user before scheduling.
- This plan is `done` only when P1+P2 both PASS the single review, the push is Adviser-approved and executed, and Build APK + Promote to Landing are green.
