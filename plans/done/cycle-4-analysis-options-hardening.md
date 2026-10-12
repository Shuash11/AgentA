# Cycle 4 — Analyzer Config Adoption + Async-Discipline Lints

**status:** done (closed 2026-10-13 — P1+P2 PASS, push executed, CI green with strict lints active)
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 4 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 3e7cb17
**predecessors:** plans/done/cycle-1..3 (all closed, CI green; latest runs 38292663386 / 38294145342)

## Cycle 4 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` | **"No issues found!" exit 0** — held for the 4th consecutive cycle |
| `flutter test` | **208/208 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** — cycle-2 gate still holding |
| `git status` (app scope) | clean — only `analysis_options.yaml` (the F14 +9 stanza, unchanged) + plan artifacts |
| CI | runs 38292663386 / 38294145342 green; F3 deprecation annotations GONE; remaining annotations info-only and pre-existing (V2 signer digests, ubuntu-latest→Ubuntu 26 note) |
| New transparency note | STALE queued workflow run **34749579707** (created 2026-09-13, SHA 7343c13) — unrelated to any push, can never complete against current main → recorded as F19 |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F14** | **analysis_options.yaml: bare-default lints + uncommitted analyzer-exclude stanza.** The +9-line `analyzer.exclude` (build/android/ios/web/windows/macos/linux — verified masks 0 Dart files) sits local-only and re-appears after every revert because newer SDKs auto-upgrade the file on every analyze run. Adopting it ends the churn; adding `unawaited_futures`/`discarded_futures` hardens against the cycle-1 F1 bug class (un-awaited futures in try blocks) at zero runtime cost. **SELECTED as the cycle-4 task.** | maintainability | working-tree diff (unchanged since cycle 1); analysis_options.yaml | backend / middle-end | CHEAP |
| **F9** | **docs/versioning.md drift**: "Existing tags: v1.0.0, v1.1.0. Current version: 1.1.0+2" vs pubspec 1.2.3+6 and released tags since. | maintainability | docs/versioning.md:74 | middle-end | CHEAP |
| **F8** | **Dead Python test**: `tests/test_agenta_traceability_matrix_revision.py` tracked, never run by CI; companion `tools/revise_agenta_traceability_matrix.py`; `tests/__pycache__/` stray. Wire into CI or remove/relocate. | maintainability / tests | git ls-files; no Python step in workflows | backend | CHEAP |
| **F17** | **Kotlin serialization pin precondition unmet** — background_downloader still 9.5.9 transitive (needs 9.6.x per the settings.gradle removal comment). | maintainability | pubspec.lock (9.5.9); settings.gradle:20-29 | backend | CHEAP |
| **F11** | **Dependency drift**: 2 discontinued packages, 100 constraint-blocked updates (mind the documented win32/flutter_secure_storage pin, pubspec:27-30). | maintainability | pub resolution output (cycle 1) | middle-end | CHEAP |
| **F19** *(new)* | **Stale queued workflow run 34749579707** (created 2026-09-13, SHA 7343c13) — can never complete against current main; CI noise only. Cancel via `gh run cancel 34749579707` (or ignore; it ages out). | CI hygiene | agent-push report, cycle 3 | backend | CHEAP |
| **F6** | **Local passwords = salted SHA-256** (no work factor); documented "minimum bar"; argon2/SQLCipher hardening path. | security | lib/services/auth/password_hasher.dart | security | EXPENSIVE |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — non-blocking warnings; upgrade = AGP 9 + Built-in-Kotlin migration. Deliberate deferral; needs a dedicated phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15** | **Tag-guard cannot catch duplicate-semver re-tagging** (documented process rule). Optional CI history check. | CI / logic | docs/versioning.md §6 | backend | CHEAP |
| **F16** | **promote-landing main-branch fallback can promote an older commit's APK** — accepted-risk, warned in logs. | CI | promote-landing.yml:123-145 | backend | CHEAP |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing escalation to the user.** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: analyzer/test ground truth has been clean for 4 cycles; F14 converts a recurring local annoyance (auto-upgrade churn) into a committed, durable config AND installs the lints that guard the exact bug class cycle 1 fixed — all cheap, all mechanical.

---

## Selected task (single): F14 — analyzer config adoption + async-discipline lints

**Objective:** `analysis_options.yaml` is committed with the exclude stanza (churn ends) and the async-discipline lints (`unawaited_futures`, `discarded_futures`) are live in CI, with every surfaced finding resolved mechanically or explicitly deferred — no gate weakened, no behavior changed.

**Version bump decision: none** — config + mechanical lint compliance, no release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — since every phase below is **CHEAP-class, no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch (Build APK green with the new lints active in its analyze step).

---

## Phase 1 — Adopt the analyzer-exclude stanza (F14 part 1)

- **Phase id:** P1
- **Objective:** the working-tree stanza is committed; SDK auto-upgrades converge (no more recurring local diff).
- **Responsible subagent:** backend
- **Files to change:** `analysis_options.yaml` — **IN-SCOPE for this phase** (ends its local-only status from earlier cycles)
- **Implementation steps:**
  1. Adopt the existing working-tree +9-line stanza, reordered to conventional key order: `include: package:flutter_lints/flutter.yaml` FIRST, then the `analyzer: exclude:` block (build/android/ios/web/windows/macos/linux). Content identical to the verified stanza (masks 0 Dart files).
  2. Run `flutter analyze` → expect "No issues found!" exit 0, and confirm `git status` afterwards shows NO new diff in analysis_options.yaml beyond the committed state (auto-upgrade convergence proof).
  3. Nothing else changes — no lint rules in this phase (P2 owns those), no other files.
- **Acceptance criteria:** stanza committed include-first; analyze exit 0; churn-convergence demonstrated (analyze → no new local diff).
- **Verification:** **CHEAP** — config adoption of an already-verified stanza; zero behavior surface.
- **Dependencies / sequencing:** first; P2 builds on the same file.
- **Expected result:** the file that has mutated locally since cycle 1 finally matches HEAD.

## Phase 2 — Async-discipline lints + mechanical compliance (F14 part 2)

- **Phase id:** P2
- **Objective:** `unawaited_futures` and `discarded_futures` are live; every new finding resolved WITHOUT behavior change or gate weakening.
- **Responsible subagent:** middle-end
- **Files to change:** `analysis_options.yaml` (2-3 lint lines) + only the lib/test files that surface findings
- **Implementation steps:**
  1. Enable `unawaited_futures` first. Run `flutter analyze`; record findings count.
  2. Enable `discarded_futures`. Run `flutter analyze`; record findings count.
  3. **Mechanical resolution rules (Adviser-authorized, mirroring the cycle-2 brace ruling):**
     - `dart fix --apply --code=<code>` where the fix exists.
     - Otherwise wrap fire-and-forget calls in `unawaited(...)` (dart:collection import: `dart:async`) — **explicitly non-behavioral** (documents intent, changes no execution).
     - **FORBIDDEN in this phase:** adding `await` to call sites (behavioral — error propagation changes), disabling rules, `// ignore:` comments, or touching analysis_options beyond adding the lint lines.
  4. **Deferral rule (keeps the phase bounded and CHEAP):** any finding that cannot be resolved by the mechanical rules above (i.e., it would need an `await` or semantic judgment) is NOT fixed — record it in the plan's backlog as a deferred lint finding and, if it blocks analyze exit 0, defer that whole lint: comment out its line with a `# deferred — see plan F14 backlog` note. Lint-by-lint adoption, not all-or-nothing.
  5. Also assess `prefer_single_quotes` (one analyze run); expected ~0 findings (codebase already single-quoted); include ONLY if zero findings — otherwise skip (pure style, not durability).
  6. Re-run: `flutter analyze` exit 0, `dart format --output=none --set-exit-if-changed lib test` exit 0 (format must not fight the lint fixes), `flutter test` 208/208.
- **Acceptance criteria:** lints live in committed analysis_options.yaml (or explicitly deferred with reasons); analyze exit 0 with the lints active; format idempotent; 208/208; every applied fix is mechanical per the rules above; deferred findings recorded.
- **Verification:** **CHEAP** — lint config + mechanical, non-behavioral compliance (unawaited() wrapping changes no execution). If the implementer is ever tempted beyond the mechanical rules, STOP and report — that would reclassify the phase EXPENSIVE.
- **Dependencies / sequencing:** after P1 (same file).
- **Expected result:** the F1 bug class is structurally guarded from now on, in local dev and CI alike.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `chore: adopt analyzer exclude stanza in analysis_options (SDK auto-upgrade convergence)` — P1 file.
- Commit 2: `refactor: enforce async-discipline lints with mechanical unawaited() wrapping (no behavior change)` — P2 files (analysis_options + the lib/test files with mechanical fixes).
- Commit 3: `docs(plans): close cycle 3 and open cycle 4 plan` — stage `plans/` explicitly (deletion of old cycle-3 path, `plans/done/cycle-3-...md`, new cycle-4 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); any stray untracked files. NOTE: `analysis_options.yaml` is **IN-SCOPE** for commits 1-2 — no longer excluded.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** with the new lints active in its `flutter analyze` step — proving the lints pass on a clean checkout (CRLF-independence) and that the analyze gate now runs STRICTER than before with zero failures. All existing guards + format gate unchanged.
- **Promote to Landing** green as usual (unchanged by this task).
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-5 audit.

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `unawaited_futures lint dart.dev` (semantics: futures silently ignored in async contexts; confirm `unawaited()` wrapping is the sanctioned suppression).
2. `discarded_futures lint dart.dev` (semantics: non-awaited futures in non-async contexts; difference from unawaited_futures).
3. `dart fix apply lint code mechanical fixes availability` (dart.dev — which of these lints have automated fixes).
4. `analyzer exclude analysis_options dart.dev` (exclude stanza semantics + that SDK auto-upgrade writes exactly this stanza).

## Reviewer verification commands (single pass, after P1+P2)

1. `flutter analyze` → exit 0 **with the lints active** (the critical proof; quote the analysis_options linter section).
2. Churn-convergence proof: run `flutter analyze` again, then `git status` → analysis_options.yaml shows no new local diff.
3. `dart format --output=none --set-exit-if-changed lib test` → exit 0; `flutter test` → 208/208.
4. Diff audit: P1 = stanza include-first only; P2 = lint lines + mechanical fixes only; **zero** `await` additions, zero `// ignore:`, zero rule disablements; every deferred finding (if any) recorded in the plan with its reason.
5. Confirm commit-scope mapping: analysis_options.yaml now IN commits 1-2; `.opencode/` and strays excluded.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-4 audit recorded; plan created `active` (task F14). F19 added (stale queued run 34749579707). F10 marked resolved (cycle 2). |
| 2026-10-13 | **P1 + P2 IMPLEMENTED, SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser verified: config = include-first + stanza + `unawaited_futures`/`discarded_futures` (lines 36-37), zero `// ignore:` comments; gates re-run independently — analyze exit 0, format 0 changed, 208/208; churn convergence re-proven live (git status on analysis_options.yaml identical across an extra analyze run). P2: 36 findings (7+29) resolved via pure `unawaited(...)` wraps across 14 dart files + 7 `dart:async` imports; `prefer_single_quotes` skipped per the zero-findings gate (47 findings); zero deferred findings; the single `+await`-looking line is a pre-existing awaited statement reindented by wrapper nesting (update_dialog_host.dart:96, semantics preserved — Reviewer-verified). **Commit-split ruling:** both config changes share analysis_options.yaml — agent-push uses **deterministic content-staging, NOT interactive hunk-picking**: C1 = write intermediate file (final minus the two lint lines), stage, commit; C2 = restore final content, stage analysis_options.yaml + the 14 dart files, commit. Both commits analyze-green (no known-red intermediate, cycle-2 bisect-hygiene principle). Commits: `chore: adopt analyzer exclude stanza in analysis_options (SDK auto-upgrade convergence)` / `refactor: enforce async-discipline lints with mechanical unawaited() wrapping (no behavior change)` / `docs(plans): close cycle 3 and open cycle 4 plan`. Version bump: none; next tag carries 1.2.4. |
| 2026-10-13 | **Push EXECUTED** — `0d3f020` chore (exclude stanza, content-staged WITHOUT lint lines), `44b5a4e` refactor (lints + 36 unawaited() wraps, 14 lib files), `a56d320` docs(plans); remote main = `a56d320`; no version bump; tags untouched; both intermediate commits analyze-green (content-staging split honored). |
| 2026-10-13 | **CI GREEN — PLAN CLOSED.** Build APK run **38299699189 SUCCESS (13m27s)**: format gate ✓, **`flutter analyze` → "No issues found!" with `unawaited_futures`/`discarded_futures` active in the pushed config** (the definitive acceptance — the repo now ships a strictly stronger static gate), tests ✓, guards ✓, APK build ✓; annotations 3× info-level only (V2 signer digests, Ubuntu 26 migration), zero deprecations. Promote to Landing run **38301174361 SUCCESS (34s)**: full promotion path, Vercel deploy triggered. Transparency: stale queued run 34749579707 (F19) still queued, untouched, unrelated — carried in backlog. The F1 bug class is now structurally guarded locally and in CI. Moved to `plans/done/`. |

- Cycle-5 pre-ranked: the cheap hygiene cluster F9/F8/F17/F11 (one multi-phase task) + F19 (one-line CI cleanup).
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing escalation to the user before scheduling.
- This plan is `done` only when P1+P2 PASS the single review, the push is Adviser-approved and executed, and BOTH workflows are green.
