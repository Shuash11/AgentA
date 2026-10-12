# Cycle 6 — In-Range Dependency Refresh (F11 part 1)

**status:** active
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 6 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 999ecc7
**predecessors:** plans/done/cycle-1..5 (all closed, CI green; latest runs 38305550630 / 38307098329)

## Cycle 6 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` (strict lints) | **"No issues found!" exit 0** — 6th consecutive clean cycle |
| `flutter test` | **208/208 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| `flutter pub outdated` | **4 discontinued packages**: direct `flutter_gemma` 1.8.4 (pub.dev: *"replaced by flutter_edge_ai"*) + `flutter_gemma_mediapipe` 1.0.6 (no named successor); transitive `flutter_secure_storage_macos` (resolvable "-") + `js` (resolvable "-"). **80 in-range upgradables locked**; 18 constrained-blocked (majors). |
| Pin lattice (pubspec:27-30) | CONFIRMED still binding: win32 5.15.0 (6.4.0 blocked), flutter_secure_storage 9.2.4 (11.2.0 blocked), package_info_plus 9.0.1 (10.2.2 blocked), flutter_secure_storage_windows 3.1.2 — the documented comment remains factually accurate |
| CI | runs 38305550630 / 38307098329 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F11** | **Dependency drift.** Part 1 SELECTED this cycle: **in-range lockfile refresh** (`flutter pub upgrade`, zero pubspec constraint edits) — clears the 80 locked upgradables within existing constraints. Parts 2-3 deferred: **F20** (flutter_gemma → flutter_edge_ai replacement migration — app-critical offline-AI engine, dedicated cycle) and the **blocked-major set** (win32 6 / flutter_secure_storage 11 / package_info_plus 10 lattice; flutter_bloc 9; connectivity_plus 7; flutter_dotenv 6; flutter_lints 6 — each needs its own constraint-edit cycle with the pin lattice respected). | maintainability | pub outdated output (above) | middle-end | **EXPENSIVE** |
| **F20** *(new)* | **flutter_gemma is discontinued — replaced by flutter_edge_ai** (per its pub.dev discontinue notice). The offline AI engine (GemmaService, ModelDownloadService, the forced OfflineModelGate) runs on dead code. Migration is a dedicated, carefully-validated cycle: API mapping, engine registration, model-download path, plus flutter_gemma_mediapipe's fate (no named successor). | maintainability / forward-risk | pub outdated discontinue notice; lib/services/ai/* | middle-end | EXPENSIVE |
| **F21** *(new)* | **Transitive discontinued packages ride the blocked lattice**: flutter_secure_storage_macos (no resolvable upgrade within flutter_secure_storage 9.x) and js (no resolvable upgrade) both resolve when the win32→flutter_secure_storage 11.x lattice is broken in a future constraint-edit cycle. No standalone action. | maintainability | pub outdated resolvable "-" | backend | EXPENSIVE (with F11 part 3) |
| **F15** | **Tag-guard cannot catch duplicate-semver re-tagging** (documented process rule). Optional CI history check. | CI / logic | docs/versioning.md §6 | backend | CHEAP |
| **F16** | **promote-landing main-branch fallback can promote an older commit's APK** — accepted-risk, warned in logs. | CI | promote-landing.yml:123-145 | backend | CHEAP |
| **F19** | **Zombie queued run 34749579707** — accepted cosmetic noise (cycle-5 ruling); run-deletion API only if noise ever matters. | CI hygiene | cycle-5 plan closure | — | accepted |
| **F17** | **Kotlin serialization pin** — background_downloader shows **9.6.4 resolvable** in this cycle's pub outdated (precondition now reachable!) but only via the in-range upgrade. **P1's refresh may satisfy F17's precondition** — re-check after P1; if bgdl lands 9.6.x, the settings.gradle pin evaluation becomes unblocked (separate cheap follow-up, NOT this cycle). | maintainability | pub outdated: bgdl 9.5.9 → 9.6.4 upgradable-in-range | backend | CHEAP (after P1) |
| **F6** | **Local passwords = salted SHA-256** (no work factor); argon2/SQLCipher hardening path. | security | lib/services/auth/password_hasher.dart | security | EXPENSIVE |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — deliberate deferral; AGP 9 migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing escalation to the user.** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: analyzer/tests/format clean for 6 straight cycles; the genuine forward risks are dependency rot (2 discontinued DIRECT dependencies — one being the app's core offline-AI engine) and the blocked-major lattice. This cycle takes the safest meaningful slice: the in-range refresh, zero constraint edits, with the migration work (F20) and lattice-breaking (F11 parts 2-3) queued as their own validated cycles.

---

## Selected task (single): F11 part 1 — in-range lockfile refresh

**Objective:** every dependency that the EXISTING constraints already permit moves to its newest resolvable version (`flutter pub upgrade`); `pubspec.yaml` is untouched (the documented pin lattice stays byte-identical); all gates and CI stay green.

**Scope guard (binding):** NO `--major-versions`, NO pubspec.yaml constraint edits, NO new packages, NO removals. If any single bumped dependency breaks validation, revert pubspec.lock and re-apply selectively (`flutter pub upgrade <pkg>` per package), recording each reverted dependency as deferred — same discipline as cycle 4's lint deferrals.

**Version bump decision: none** — dependency maintenance is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **P1 is EXPENSIVE (runtime dependency behavior), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch.

---

## Phase 1 — In-range refresh + full validation (F11 part 1)

- **Phase id:** P1 (single phase)
- **Objective:** pubspec.lock refreshed to the newest constraint-resolvable set; pubspec.yaml untouched; all local gates green.
- **Responsible subagent:** middle-end
- **Files to change:** `pubspec.lock` (regenerated); `pubspec.yaml` **must show zero diff**; possibly `.dart_tool/` local state (untracked).
- **Implementation steps:**
  1. Record pre-state: `flutter pub outdated` (saved), `git stash list` empty, working tree clean.
  2. Run `flutter pub upgrade` (in-range only). Inspect `git diff pubspec.yaml` → MUST be empty; `git diff --stat pubspec.lock` → broad lockfile churn is expected and acceptable.
  3. **Spot-verify the pin lattice held** (grep pubspec.lock): win32 == 5.x, flutter_secure_storage == 9.x, flutter_secure_storage_windows == 3.1.x, package_info_plus == 9.x, flutter_secure_storage_macos/js state recorded. Any lattice violation → STOP, revert, report (that would mean a constraint edit happened — out of scope).
  4. Note whether background_downloader landed **9.6.x** (F17 precondition check — report it; do NOT touch the settings.gradle pin this cycle).
  5. Full local validation: `flutter analyze` exit 0 (strict lints), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` → 208/208.
  6. **Deferral rule:** if validation fails, bisect via selective re-upgrade (`flutter pub upgrade` per package on the direct-dep list: flutter_gemma, flutter_gemma_mediapipe, flutter_markdown_plus, flutter_svg, json_annotation, path_provider, shared_preferences, sqflite, supabase_flutter, url_launcher, uuid, build_runner, json_serializable, sqflite_common_ffi); each failing package reverted to its locked prior version and recorded as deferred with the failure evidence.
  7. If pub output shows any NEW discontinuation or constraint conflict introduced by the refresh → record in the phase report (feeds the backlog).
- **Acceptance criteria:** pubspec.yaml byte-identical to HEAD; lattice spot-check passes; all three gates green; any deferrals recorded with evidence; F17 precondition status reported.
- **Verification:** **EXPENSIVE** — honest classification: the lockfile changes the runtime code that executes (supabase/gotrue/realtime_client/storage_client, sqflite, crypto paths, flutter_gemma internals). The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: execute `flutter analyze` (exit 0) and `flutter test` (208/208) on the refreshed tree, plus re-run the pin-lattice spot-check greps.
- **Dependencies / sequencing:** single phase; nothing follows this cycle on this task.
- **Expected result:** 80 in-range upgradables cleared; discontinued direct deps at their final in-range versions pending the F20 migration; lattice intact.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `chore(deps): refresh in-range dependencies via pub upgrade (no constraint edits)` — pubspec.lock only.
- Commit 2: `docs(plans): close cycle 5 and open cycle 6 plan` — stage `plans/` explicitly (deletion of old cycle-5 path, `plans/done/cycle-5-...md`, new cycle-6 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); `pubspec.yaml` MUST NOT appear in any commit (zero-diff guard).
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — this is the real-world proof the refreshed dependency set builds and passes all guards + format gate + strict-lint analyze + 208/208 tests + APK build on the runner. Watch to conclusion.
- **Promote to Landing** green as usual.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase (likely selective revert per the deferral rule). Do not retry or fix autonomously.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-7 audit.

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `flutter_gemma discontinued replaced flutter_edge_ai` (pub.dev/packages/flutter_gemma — verify the discontinue notice + replacement claim; informs F20 scoping).
2. `flutter pub upgrade vs pub get lockfile semantics` (dart.dev/tools/pub/cmd — confirm upgrade touches only constraint-permitted versions, i.e., pubspec.yaml constraints are never edited).
3. `win32 package 6.0.0 breaking changes pub.dev` (pub.dev/packages/win32/changelog — validates the documented pin rationale for the F11 part 3 / F21 cycles).
4. `flutter_secure_storage 11.0.0 changelog breaking` (pub.dev — what the blocked 9→11 jump entails; informs the future lattice-breaking cycle).

## Reviewer verification commands (single pass, after P1)

1. `git diff pubspec.yaml` → **empty** (binding zero-diff guard).
2. Lattice spot-check greps on pubspec.lock: win32 5.x / flutter_secure_storage 9.x / flutter_secure_storage_windows 3.1.x / package_info_plus 9.x → all hold.
3. Baseline gates on the refreshed tree: `flutter analyze` exit 0, `flutter test` 208/208, `dart format --output=none --set-exit-if-changed lib test` exit 0.
4. `flutter pub outdated` post-state → "80 upgradable locked" count should collapse to near-zero; discontinued direct deps remain (expected, F20) — record the new numbers.
5. F17 precondition status: background_downloader version in pubspec.lock (9.6.x = precondition met, unblocks the settings.gradle pin evaluation for a future cheap cycle).
6. Diff audit: C1 = pubspec.lock only; C2 = plans artifacts only; no pubspec.yaml anywhere.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-6 audit recorded; plan created `active` (task F11 part 1). F20 (flutter_gemma → flutter_edge_ai migration) and F21 (transitive discontinued ride-alongs) added. F17 precondition discovered REACHABLE via this cycle's refresh (bgdl 9.6.4 in-range) — re-check post-P1. |
| 2026-10-13 | **P1 IMPLEMENTED + REQUIRED E2E PASS + SINGLE-PASS REVIEW PASS + PUSH APPROVED by Adviser.** Adviser independently verified: pubspec.yaml byte-identical (binding guard held); lockfile = the only code artifact (170/170 lines); lattice spot-check with exact versions — **win32 5.15.0, flutter_secure_storage 9.2.4, flutter_secure_storage_windows 3.1.2, package_info_plus 9.0.1** (pin lattice intact, pubspec:27-30 comment stays factually accurate), **background_downloader 9.6.4 (F17 precondition MET)**, flutter_gemma 1.11.4 / mediapipe 1.0.9 (discontinued in-range finals → F20 scope); gates re-run — analyze exit 0, format 0 changed, 208/208. **Registrant adjudication CORRECTED by tree evidence:** the 3 platform registrants (linux .cc/.cmake, macos .swift) are tracked but show **ZERO diffs vs HEAD** — the reported regeneration left no working-tree change (transient state normalized or report error). Ruling: **2-commit sequence** — commit 2 (registrant chore) EXISTS ONLY IF those files show diffs at push time; if unchanged (current state), agent-push SKIPS it (never an empty commit) and proceeds C1 → docs. The Reviewer's substantive findings (sdks floor dart≥3.13/flutter≥3.47 compatible with CI pin 3.47.6; flutter_edge_ai migration guide "installed models carry over"; win32 6.0 redesign + fss 9→11 data-loss risk validating the lattice deferral) stand and are recorded for F20/F21 scoping. Commits: `chore(deps): refresh in-range dependencies via pub upgrade (no constraint edits)` (pubspec.lock ONLY) → [conditional registrant chore] → `docs(plans): close cycle 5 and open cycle 6 plan`. Version bump: none; next tag carries 1.2.4. |
| pending | agent-push: push main (conditional registrant commit per ruling above), watch BOTH workflows → **Build APK green on the refreshed lock** (the definitive real-world proof the dependency set builds and passes guards + format gate + strict-lint analyze + 208/208 + APK build on the runner), Promote to Landing green. Watch for NEW dependency-related failures distinctly from infra failures. On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-7 audit (pre-ranked: F20 migration, then cheap F15/F16/F17 cluster — F17 now unblocked). On red: capture `gh run view --log-failed`, plan stays `active`, fix phase likely selective lockfile revert per the deferral discipline. |

- Cycle-7 pre-ranked: F20 (flutter_gemma → flutter_edge_ai migration — dedicated, carefully-validated cycle), then F15/F16 (cheap CI notes) + F17 (if P1 met its precondition) as a cheap cluster.
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing escalation to the user before scheduling.
- This plan is `done` only when P1 PASSes review (after the e2e run), the push is Adviser-approved and executed, and BOTH workflows are green.
