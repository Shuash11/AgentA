# Cycle 1 — Async Bug Fixes + Analyzer/CI Alignment

**status:** active
**created:** 2026-10-12
**created by:** Adviser (self-improvement cycle 1 audit)
**repo:** C:\projects\aiproject (AgentA — Flutter app, Supabase backend)
**branch:** main @ 08dfe59

## Audit ground truth (evidence base)

| Check | Result |
|---|---|
| `flutter analyze` (local, Flutter 3.47.6 / Dart 3.13.5) | **FAIL (exit 1)** — 3 warnings, all `unawaited_return_in_try_block` |
| `flutter test` | **PASS** — 208/208 tests, "All tests passed!" (~40s) |
| `dart format --set-exit-if-changed --output=none lib test` | **FAIL** — 80 of 89 files not dart-formatted |
| `git ls-files .env` | empty — **.env is NOT committed** (gitignored; C1 dart-define model intact) |
| `git status` (app code) | clean — only `.opencode/` workflow-config churn (out of scope) |
| CI (last run 34762499526, commit predating F1) | **green** — but see F2/F3 |
| CI pinned Flutter | 3.44.1 (`build-apk.yml:39`) vs local stable 3.47.6 → **analyzer drift** |
| Supabase migrations | only `0001_rls.sql` (policies only; **no versioned table schema**) |
| RLS policies | present for profiles/chats/messages, `auth.uid()`-bound — good |
| Empty catches / raw `print()` in lib/ | none found |
| Audit side effects | reverted (`analysis_options.yaml`, `pubspec.lock` restored to HEAD; temp output file deleted) — tree left as found |

---

## Findings backlog (ranked, uncapped)

Ranking: impact × (user directive: bugs/errors first). Verification class: **CHEAP** = static/compile evidence suffices, no e2e-tester run before Reviewer; **EXPENSIVE** = an executed e2e-tester run is required before the Reviewer gate.

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F1** | **3 analyzer warnings: un-awaited Futures inside try blocks — real error-swallowing bugs.** `lib\services\ai\huggingface_image_service.dart:80` and `:83` return `_saveBytes(...)` un-awaited: a temp-file write failure (disk full, IO error) escapes the `on http.ClientException` handler as an **unhandled async zone error** instead of reaching the caller's catch → user never sees the friendly failure UI. `lib\services\auth\biometric_auth_service.dart:81` returns `_storage.read(key: _uidKey)` un-awaited inside `unlock()`'s try: a secure-storage platform failure escapes **both** `on LocalAuthException` and the generic catch → unhandled async error; unlock silently breaks instead of returning `null` (graceful degrade). Also lines 78–83 are redundant duplicated branches (the second `statusCode == 200` subsumes the first). Analyzer text: *"Returning a 'Future' without 'await' inside a try block. Try adding an 'await'"* (3 issues, exit 1). | bug | `flutter analyze` output (captured); both files read in full | middle-end | **EXPENSIVE** (error-handling behavior) |
| **F2** | **CI analyzer drift: workflow pins Flutter 3.44.1; local stable is 3.47.6 (current stable line 3.47 per docs.flutter.dev).** [Post-review note 2026-10-12: 3.47.7 is now the newest 3.47 patch (stable CHANGELOG, Reviewer-verified) — P2 pins the exact dev-machine stable 3.47.6 by plan; revisit the pin against 3.47.7 at the next audit.] CI's `flutter analyze` (build-apk.yml:204) passed on code that fails analyze locally — the 3.44 analyzer does not flag `unawaited_return_in_try_block`. The analyze gate is not seeing what developers see; F1 slipped through CI green. | bug / CI | `build-apk.yml:36-40`, `flutter --version`, last green CI run in `watch_out.txt`, docs.flutter.dev/release/release-notes ("Flutter 3.47 is here!") | backend | CHEAP (config; post-push CI watch mandatory) |
| **F3** | **Deprecated GitHub Actions in build-apk.yml**: run annotations — "setup-java v4 is deprecated … migrate to actions/setup-java@v5" and Node 20 deprecation forcing Node 24 for `actions/checkout@v4`, `actions/setup-java@v4`, `actions/upload-artifact@v4`. Will hard-fail when Node 20 support is dropped. | CI | `watch_out.txt` ANNOTATIONS block (lines 703–714) | backend | CHEAP |
| **F4** | **Supabase schema is not version-controlled.** Only `0001_rls.sql` exists, all `alter table if exists` (silent no-op if a table is missing/renamed). Real tables (profiles/chats/messages + columns `recovery_code`, `last_message`, `text`, `is_user`, `timestamp`) live only in cloud project pmeygoyubqiaqvsuyjzm. Contract risk: Dart↔DB shape has no source of truth; RLS policies can silently stop protecting if schema drifts. RLS file itself says "Adjust the USING clause to the real FK if the schema differs." | contract / maintainability | `supabase\migrations\` (1 file), `docs\backend-rls.md` | backend | EXPENSIVE (needs live-DB introspection) |
| **F5** | **H8 recovery-code RPC not deployed — client-side hash comparison ships.** `user_repository.dart:72-80` fetches the stored SHA-256 hash and compares client-side; `0001_rls.sql:68-81` documents the target `verify_recovery_code` SECURITY DEFINER RPC as commented-out. Weakens recovery-code security (hash exposed to client; offline brute-force of a normalized human code). Known, documented TODO. Needs Supabase cloud deploy access. | security | `lib\repositories\user_repository.dart:72-80`, `supabase\migrations\0001_rls.sql:68-81`, `docs\backend-rls.md` §Recovery codes | security (+backend) | EXPENSIVE |
| **F6** | **Local passwords hashed with salted SHA-256 (fast hash, no work factor)** — `password_hasher.dart`; doc calls it "the minimum bar" with a SQLCipher/argon2 upgrade path (C5). Offline rows only, app-private DB — acceptable today, hardening backlog. | security | `lib\services\auth\password_hasher.dart`, `docs\backend-rls.md` §C5 | security | EXPENSIVE |
| **F7** | **dart format violations across 80/89 lib+test files; no format gate in CI.** Formatting-only one-shot `dart format` + a CI format step. Large diff but zero behavior change; erodes review signal until fixed. | maintainability | `dart format --set-exit-if-changed lib test` → "Formatted 89 files (80 changed)" | middle-end | CHEAP |
| **F8** | **Dead Python test + tooling in a Flutter repo.** `tests\test_agenta_traceability_matrix_revision.py` is git-tracked but nothing in CI runs Python (build-apk.yml has no Python step) — a false sense of coverage; `tests\__pycache__\` stray dir; companion `tools\revise_agenta_traceability_matrix.py`. Wire into CI or remove/relocate. | maintainability / tests | `git ls-files tests`, `.github\workflows\` (no Python), directory listing | backend | CHEAP |
| **F9** | **docs/versioning.md drift**: says "Existing tags: v1.0.0, v1.1.0. Current version: 1.1.0+2" while pubspec is 1.2.3+6. Doc that the release checklist relies on is stale. | maintainability | `docs\versioning.md:74` vs `pubspec.yaml:4` | middle-end | CHEAP |
| **F10** | **Stray local artifacts** `watch_out.txt` / `watch_done.txt` at repo root (untracked, gitignored CI-watch output). Local hygiene only — delete; no commit needed. | maintainability | root listing + `.gitignore:72-73` | backend | CHEAP |
| **F11** | **Dependency drift**: pub resolution reports "2 packages are discontinued", 100 packages newer but constraint-blocked (e.g. supabase_flutter 2.17.2 → 2.18.3, http/url_launcher/uuid minors). Refresh audit needed (mind the documented win32/flutter_secure_storage pin at pubspec:27-30). | maintainability | `flutter analyze` dependency-resolution output | middle-end | CHEAP |
| **F12** | **Offline signups never sync — documented functional gap.** `_queueForEdgeFunction` is a stub (sync_service.dart:293-306): "a `sync-offline-user` Supabase Edge Function is REQUIRED for offline-created accounts to ever sync … cannot be implemented client-side". Pending rows stay unsynced forever until deployed. Requires cloud deploy access. | logic / feature-gap | `lib\services\sync\sync_service.dart:282-306` | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call** (`connectivity_service.dart:44`) and runs on every connectivity_plus event — minor allocation churn; also `_lastStatus` defaults `offline` until first probe completes (brief false-offline window at boot). LOW. | performance | file read | middle-end | EXPENSIVE (behavioral tweak → e2e) |
| **F14** | **Lint config is bare-default** (`analysis_options.yaml` = stock flutter_lints). Consider adding `unawaited_futures`, `discarded_futures`, `prefer_single_quotes` once F1 lands — cheap durability for the F1 bug class. [Adviser ruling 2026-10-12: also adopt the working-tree +9-line `analyzer.exclude` stanza (build/android/ios/web/windows/macos/linux — verified masks 0 Dart files) in this phase, reordered `include:`-first for conventional key order. Root cause it exists uncommitted: newer Flutter SDKs auto-upgrade this file whenever `flutter analyze` runs.] | maintainability | `analysis_options.yaml` | middle-end | CHEAP |
| **F15** | **Tag-guard cannot catch re-tagging an already-released semver** (duplicate-version release would silently publish; installed apps never see the update). Known process rule (docs/versioning.md §6) — optional CI history check. | CI / logic | `docs\versioning.md:35-39,195` | backend | CHEAP |
| **F16** | **promote-landing main-branch fallback can promote an older commit's APK** (newest v* release when the main run has no artifact) — deliberate, warned in logs, staleness is visible; keep as accepted-risk note. | CI | `promote-landing.yml:123-145` | backend | CHEAP |

---

## Selected task (single, highest-impact): F1 + F2

**Objective:** make `flutter analyze` green (exit 0) by fixing the three flagged async error-swallowing bugs, and align CI's Flutter pin with the current stable SDK so the CI analyze gate sees what local development sees. This is the one task for cycle 1 — every other finding stays in the backlog above.

Rationale: it is the only ground-truth "bugs and errors" signal in the repo (analyze exit 1), the fixes are small and surgical, and F2 is the root cause of those bugs being invisible to CI — fixing one without the other leaves the gate broken.

**Version bump decision: none** for this task's push. Reason: no release is being cut — the changes are error-path bug fixes + CI config; per `docs/versioning.md` a patch bump (1.2.3 → 1.2.4) applies when the next user-facing tag is cut, not on every main commit. This decision is final; the push agent must not re-decide it.

---

## Phase 1 — Fix the three unawaited-return-in-try bugs (F1)

- **Phase id:** P1
- **Objective:** every returned Future inside a try block is awaited so failures reach the existing catch/caller error paths; analyzer exits 0.
- **Responsible subagent:** middle-end
- **Files to change:**
  - `lib/services/ai/huggingface_image_service.dart` (lines 78–83)
  - `lib/services/auth/biometric_auth_service.dart` (line 81)
- **Implementation steps:**
  1. In `huggingface_image_service.dart`: collapse the duplicated 200-branches (lines 78–83) into one `if (response.statusCode == 200) { return await _saveBytes(response.bodyBytes); }` — awaiting makes a `_saveBytes` failure a proper error on the returned future, which the caller's catch converts to the friendly UI error (error-hygiene contract, `docs/error-hygiene.md`), instead of an unhandled zone error.
  2. In `biometric_auth_service.dart` `unlock()`: change `return _storage.read(key: _uidKey);` to `return await _storage.read(key: _uidKey);` — a secure-storage failure then falls into the existing `catch (e, stack)` which returns `null` (graceful degrade, M17 pattern already used throughout the file) instead of escaping as an unhandled async error.
  3. Do NOT refactor anything else in these files; keep diffs minimal (no reformatting — F7 is a separate backlog item).
  4. Add/adjust unit tests only if trivially possible with existing fakes; do not expand scope.
- **Acceptance criteria:**
  - `flutter analyze` → "No issues found!" (exit 0).
  - `flutter test` → 208+ tests, "All tests passed!".
  - `git diff` touches exactly the two files above (plus possibly one test file if step 4 taken).
- **Verification:** **EXPENSIVE.** Reason: both fixes change error-handling behavior (auth unlock + image-save failure paths). e2e-tester must execute, before the Reviewer gate:
  1. `flutter analyze` — assert "No issues found!"/exit 0.
  2. `flutter test` — assert "All tests passed!"/exit 0.
- **Reviewer web searches (run these; cite sources in findings):**
  1. `Dart unawaited_return_in_try_block lint` (dart.dev — page may 404 if too new; if so mark the lint's doc-semantics unverified and rely on the analyzer diagnostic text as primary evidence).
  2. `Effective Dart error handling await futures try block` (dart.dev language/effective-dart).
  3. `Flutter unhandled async exception zone error best practice` (docs.flutter.dev/testing/errors).
- **Dependencies / sequencing:** none — first phase.
- **Expected result:** analyzer clean; failure paths in image-save and biometric unlock now surface as handled errors / graceful `null` respectively.

## Phase 2 — Align CI Flutter pin with current stable (F2)

- **Phase id:** P2
- **Objective:** CI's `flutter analyze`/`flutter test` gates run on the same stable SDK line as local development, so analyzer findings cannot slip through again.
- **Responsible subagent:** backend
- **Files to change:**
  - `.github/workflows/build-apk.yml` (line 39: `flutter-version: "3.44.1"` → `"3.47.6"`)
- **Implementation steps:**
  1. Bump the `subosito/flutter-action@v2` `flutter-version` input to `"3.47.6"` (the exact local stable; 3.47 verified as the current stable line on docs.flutter.dev).
  2. Leave every other step (guards, signing, actions versions) untouched — F3 (action deprecations) is a separate backlog item for the next cycle.
  3. Add a one-line comment above the pin noting the convention: keep the pin on the same stable line as dev machines; audit at each cycle.
- **Acceptance criteria:**
  - YAML parses (workflow shows up in `gh workflow list` / actionlint if available).
  - No other workflow step changed (`git diff` = one version line + comment).
  - Post-push CI run (Build APK on main) is green — watched by agent-push per loop rules; a red run keeps this plan active as a fix phase.
- **Verification:** **CHEAP.** Reason: config-only, no app behavior; the strongest local evidence (analyze + full test suite on 3.47.6) already exists from P1's run, and the definitive proof is the mandatory post-push CI watch. No e2e-tester run required before the Reviewer gate.
- **Reviewer web searches:**
  1. `Flutter 3.47 release notes stable` (docs.flutter.dev / blog.flutter.dev).
  2. `subosito/flutter-action flutter-version input` (github.com/subosito/flutter-action README).
- **Dependencies / sequencing:** starts only after P1 PASSes (P1 guarantees the tree is clean on 3.47.6 before CI is pointed at it).
- **Expected result:** CI analyze/test gate runs on Dart 3.13.x and would have caught F1-class warnings.

---

## Backlog governance

- Findings F3–F16 are queued for subsequent cycles; the next audit re-ranks them (cheap wins F3, F7, F8, F9, F10 are likely next).
- F4, F5, F12 carry a **cloud blocker**: they need live Supabase project access (deploy/introspect). Escalate to the user before scheduling them.
- This plan is `done` only when P1 and P2 both PASS review, the push is approved by the Adviser, executed, and the triggered Build APK + Promote to Landing workflows are green.

## Cycle status

| Date | Event |
|---|---|
| 2026-10-12 | Audit recorded; plan created `active`. |
| 2026-10-12 | **P1 PASS** — middle-end fix (+2/−6, 2 files); e2e-tester executed EXPENSIVE gate: analyze "No issues found!" exit 0, test 208/208. Reviewer PASS (3 web searches run; dart.dev lint page 404 → lint doc-semantics unverified-by-web per contingency, analyzer text is primary evidence). Adviser independently re-ran both gates: same results. |
| 2026-10-12 | **P2 PASS** — backend pin 3.44.1 → 3.47.6 + comment (1 line each); YAML parses, workflow active. Reviewer PASS (3.47 stable line + subosito exact-pin verified via web). Post-push CI watch is the definitive F2 acceptance. |
| 2026-10-12 | **Push APPROVED by Adviser.** Commit scope: 2 P1 files + `build-apk.yml` + `plans/cycle-1-async-bug-fixes-analyzer-green.md` (docs commit). Excluded: `analysis_options.yaml` (local-only until F14), all `.opencode/` churn, everything untracked outside `plans/`. Version bump: none for this push (next tag carries 1.2.4 per `docs/versioning.md`). |
| pending | agent-push: 3 commits (fix / ci / docs), push main, watch Build APK → green on 3.47.6, watch promote-landing. On green: mark plan `done`, move to `plans/done/`. On red: plan stays `active`, fix phase planned. |
