# Cycle 7 — Offline-AI Engine Migration (F20: flutter_gemma → flutter_edge_ai)

**status:** active
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 7 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 45fb75e
**predecessors:** plans/done/cycle-1..6 (all closed, CI green; latest runs 38316319241 / 38317351979)

## Cycle 7 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` (strict lints) | **"No issues found!" exit 0** — 7th consecutive clean cycle |
| `flutter test` | **208/208 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| `flutter pub outdated` | 0 upgradables (cycle-6 refresh held); discontinued: flutter_gemma **1.11.4** + flutter_gemma_mediapipe **1.0.9** at in-range finals (direct — **F20 scope**); flutter_secure_storage_macos + js at blocked finals (transitive — F21, lattice-coupled) |
| Gemma surface in lib/ | **6 reference sites** (contained): main.dart imports (:6-7) + `FlutterGemma.initialize(inferenceEngines: const [MediaPipeEngine()])` (:182-183, failure caught and ignored — non-fatal boot) + service-layer wrappers (gemma_service / model_download / offline_ai) |
| background_downloader | **9.6.4** shipped — F17 precondition MET (stale-pin evaluation unblocked, cheap follow-up) |
| CI | runs 38316319241 / 38317351979 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F20** | **Offline-AI engine runs on discontinued code.** flutter_gemma (discontinued; pub.dev: replaced by flutter_edge_ai) + flutter_gemma_mediapipe (discontinued, NO named successor) power the app's core differentiator. Cycle-6 Reviewer validated the official migration guide is light: replace dep, change imports, `dart fix --apply`, "installed models and app data carry over". Open question: the MediaPipeEngine registration story in flutter_edge_ai (main.dart:183). **SELECTED as the cycle-7 task.** | maintainability / forward-risk | pub outdated; lib surface count (6 sites) | middle-end | **EXPENSIVE** |
| **F17** | **Stale serialization pin — precondition NOW MET** (toolchain on 3.47+ since cycle 1; background_downloader 9.6.4 shipped in cycle 6). The settings.gradle pin (`kotlin.plugin.serialization` → 2.3.20) and its comment are provably stale; removing it lets plugin resolution run unforced (verify no other dep reintroduces a conflicting serialization pin — pub get resolution is the test). Cheap follow-up cluster with F15. | maintainability | settings.gradle:20-29; pubspec.lock bgdl 9.6.4 | backend | CHEAP |
| **F15** | **Tag-guard cannot catch duplicate-semver re-tagging** (documented process rule). Optional CI history check: a pre-build step grepping existing tags for the version when on a v* ref. | CI / logic | docs/versioning.md §6 | backend | CHEAP |
| **F16** | **promote-landing main-branch fallback can promote an older commit's APK** — accepted-risk, warned in logs, staleness visible. No action; recorded. | CI | promote-landing.yml:123-145 | — | accepted |
| **F21** | **Transitive discontinued (flutter_secure_storage_macos, js)** — ride the blocked win32→fss-11 lattice; resolve in a future constraint-edit cycle (data-loss risk on the 9→11 jump per cycle-6 research — must be its own validated cycle). | maintainability | pub outdated resolvable "-" | backend | EXPENSIVE |
| **F11** | **Blocked-major dependency set** (win32 6.4.0, flutter_bloc 9.1.1, connectivity_plus 7.3.2, flutter_dotenv 6.0.1, cupertino_icons 2.0.0, flutter_lints 6.0.0, flutter_launcher_icons 0.14.4, package_info_plus 10.2.2) — each needs its own constraint-edit cycle with the pin lattice respected. | maintainability | pub outdated resolvable column | middle-end | EXPENSIVE |
| **F6** | **Local passwords = salted SHA-256** (no work factor); argon2/SQLCipher hardening path. | security | lib/services/auth/password_hasher.dart | security | EXPENSIVE |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — deliberate deferral; AGP 9 + Built-in-Kotlin migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F19** | **Zombie queued run 34749579707** — accepted cosmetic noise (cycle-5 ruling). | CI hygiene | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing escalation to the user.** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: 7 clean cycles; the last forward-risk that touches runtime engine code is F20. The cycle-6 research de-risked it (official guide, models carry over). The cheap F17/F15 cluster is next cycle. Honesty note: **device-level inference is NOT covered by any gate** — acknowledged below with a non-gating advisory.

---

## Selected task (single): F20 — offline-AI engine migration to flutter_edge_ai

**Objective:** zero imports of discontinued packages (`flutter_gemma`, `flutter_gemma_mediapipe`) in lib/ and pubspec.yaml; the offline-AI path compiles, passes the full suite, and boots with the engine registered per flutter_edge_ai's documented setup; installed-model carry-over preserved (no forced re-download).

**Version bump decision: none** — engine migration is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **P2 is EXPENSIVE (runtime engine behavior), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch (Build APK compiles the migrated engine on the runner).

**RISK ACKNOWLEDGMENT (honest, plan-level):** unit tests mock the inference engine; gates prove compile + unit integrity, and CI proves the APK builds — but **real on-device inference is not gate-covered**. Advisory (non-gating): after the push goes green, the user should smoke-test offline chat on a device using the promoted `AgentA-45fb75e`-or-newer APK from the landing release. The migration must preserve graceful degradation: `FlutterGemma.initialize` failure remains non-fatal (main.dart catch-and-ignore) and all error paths stay friendly per docs/error-hygiene.md.

**FALLBACK RULE (binding):** if P1's map or P2's application hits any non-mechanical gap — an API without a flutter_edge_ai equivalent, an unclear engine-registration story, or a behavioral change beyond import/dep/API-swap — **STOP, revert all migration changes (`git checkout -- pubspec.yaml pubspec.lock lib/`), record the gap with evidence, and report.** A partial migration is NEVER committed; the plan stays `active` and the Adviser re-scopes (possibly deferring F20 and substituting the cheap F17/F15 cluster for this cycle).

---

## Phase 1 — Migration map (F20 evidence pass)

- **Phase id:** P1
- **Objective:** a complete old→new API map for all 6 lib/ reference sites + the engine-registration disposition + the mediapipe sub-package disposition — enough for a purely mechanical P2 or a clean STOP.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only evidence pass)
- **Implementation steps:**
  1. Inventory: grep lib/ + test/ for `flutter_gemma|FlutterGemma|MediaPipeEngine|flutter_gemma_mediapipe|InferenceModel|ModelType|Chat` — list every file:line with its call and its role (import / init / model-create / chat / download).
  2. Extract the official migration guidance: pub.dev/packages/flutter_edge_ai README + migration guide (cycle-6 Reviewer cited it — "replace dep, change imports, dart fix --apply, installed models and app data carry over") — capture the exact documented steps and any engine-setup section.
  3. **Engine disposition (the critical unknown):** does flutter_edge_ai bundle the MediaPipe (.task) engine that flutter_gemma_mediapipe provided, register engines by default, or require an explicit engine argument? Determine from the package docs; if undocumented → candidate STOP per the fallback rule.
  4. **Mediapipe sub-package disposition:** what replaces `flutter_gemma_mediapipe` (bundled? renamed? dropped because flutter_edge_ai registers its own engine?).
  5. Map every call site old→new API; classify each as mechanical (import/renamed-class) or non-mechanical (signature change, async shape change, model-type semantics change).
  6. Check the model-download path: gemma-offline.task filename, ModelDownloadService's install flow, and whether flutter_edge_ai expects the same on-device layout ("models carry over" claim).
  7. Produce the map in the phase report. If ANY item in 3-6 is unresolved → invoke the STOP-and-revert path (nothing to revert in P1 — just report STOP and the gap).
- **Acceptance criteria:** the map covers 100% of the reference surface; engine + mediapipe dispositions stated with doc citations; mechanical/non-mechanical classification per site.
- **Verification:** **CHEAP** — read-only evidence; no e2e impact.
- **Dependencies / sequencing:** first; P2 executes only a clean map.
- **Expected result:** P2 is fully determined, or the cycle STOPs honestly.

## Phase 2 — Apply the migration (F20)

- **Phase id:** P2
- **Objective:** the app compiles and passes the full suite on flutter_edge_ai with zero discontinued imports.
- **Responsible subagent:** middle-end
- **Files to change:** `pubspec.yaml` (dep swap — IN SCOPE this cycle), `pubspec.lock` (regenerated), `lib/main.dart` (+ the service-layer files in the inventory), possibly `test/` mocks; possibly generated plugin registrants (same conditional-commit treatment as cycle 6: separate chore commit ONLY if diffs exist at push time)
- **Implementation steps:**
  1. Apply the map mechanically: swap deps (`flutter_gemma` → `flutter_edge_ai` at the guide's version; drop/replace `flutter_gemma_mediapipe` per disposition), update imports, run `dart fix --apply` (import directives), adjust call sites strictly per the map.
  2. main.dart engine registration per flutter_edge_ai's documented setup (P1 step 3); preserve the non-fatal catch-and-ignore and retry budget semantics (maxDownloadRetries: 3 comment block stays accurate — update the comment text if the engine names change).
  3. Preserve model carry-over: do NOT change the model filename/layout (`gemma-offline.task`, `aaptOptions.noCompress = ['task']`) unless the guide mandates it; if it mandates, record in the phase report as a user-facing note (re-download required?) — carry-over claim says not required.
  4. Update test mocks to the new API strictly per the map (no behavior reinterpretation); test COUNT may change only if a test becomes obsolete — report any such change explicitly.
  5. Local validation: `flutter analyze` exit 0 (strict lints), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` all pass.
  6. **STOP-and-revert on any non-mechanical gap** (fallback rule above).
- **Acceptance criteria:** zero `flutter_gemma`/`flutter_gemma_mediapipe` references in lib/ + pubspec.yaml; gates green; diffs = the map's mechanical scope only; graceful-degradation semantics preserved; model carry-over preserved.
- **Verification:** **EXPENSIVE** — runtime engine behavior changes. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: `flutter analyze` exit 0 ×2 (lint-activity awareness), `flutter test` all-pass, `flutter pub get --enforce-lockfile` idempotent, zero-discontinued-imports grep.
- **Dependencies / sequencing:** after P1's clean map.
- **Expected result:** the app's offline-AI engine runs on maintained code; the last discontinued direct dependency pair is gone.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `refactor(ai): migrate offline engine to flutter_edge_ai (flutter_gemma discontinued)` — pubspec.yaml, pubspec.lock, lib/ + test/ migration changes.
- Commit 2 (conditional, same rule as cycle 6): `chore: regenerate plugin registrants to match new dependency set` — ONLY if registrant diffs exist at push time; otherwise SKIP.
- Commit 3 (final): `docs(plans): close cycle 6 and open cycle 7 plan` — stage `plans/` explicitly (deletion of old cycle-6 path, `plans/done/cycle-6-...md`, new cycle-7 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); no secrets (pubspec dep lines + code only).
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — the runner compiles the migrated engine, runs the format gate, strict-lint analyze, 208+ tests, and builds the APK. This is compile-level proof of the migration; device-level inference remains the user's advisory smoke test (above).
- **Promote to Landing** green as usual — the promoted APK is the smoke-test artifact.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase (likely scoped revert to flutter_gemma finals + recorded gaps). Do not retry or fix autonomously.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-8 audit (pre-ranked: cheap F17+F15 cluster).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `flutter_edge_ai pub.dev migration guide from flutter_gemma` (pub.dev/packages/flutter_edge_ai — README/migration: dep swap, imports, dart fix, model carry-over claims).
2. `flutter_gemma discontinued notice replacement` (pub.dev/packages/flutter_gemma — the official discontinue record and its pointer).
3. `flutter_edge_ai MediaPipe engine registration inferenceEngines` (does flutter_edge_ai bundle/require an engine argument replacing MediaPipeEngine? — resolves P1's critical unknown).
4. `dart fix import directives flutter migration apply` (dart.dev — the mechanical import-fix availability used in P2).

## Reviewer verification commands (single pass, after P1+P2)

1. Grep `lib/ test/ pubspec.yaml` for `flutter_gemma|flutter_gemma_mediapipe|MediaPipeEngine` → zero matches in pubspec.yaml + lib/ (test mocks only if a legacy name survives per the map — else zero); `pubspec.lock` contains `flutter_edge_ai` and NOT `flutter_gemma`.
2. Baseline gates on the migrated tree: `flutter analyze` exit 0 (strict lints), `flutter test` all-pass (quote the count and any count change vs 208), `dart format --output=none --set-exit-if-changed lib test` exit 0.
3. `flutter pub get --enforce-lockfile` idempotent; `flutter pub outdated` → flutter_gemma/mediapipe GONE from the direct list.
4. Diff audit: pubspec.yaml = the dep swap lines only; lib/ diffs match the P1 map site-by-site; main.dart's non-fatal catch + retry-budget semantics preserved; model filename/layout untouched (or guide-mandated change recorded).
5. Fallback audit: any STOP during P1/P2 → verify clean revert (`git diff` empty) and the recorded gaps.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-7 audit recorded; plan created `active` (task F20). F17 precondition confirmed MET (cheap cluster pre-ranked for cycle 8). Risk acknowledgment recorded (device inference not gate-covered; advisory smoke test). |
| 2026-10-13 | **P1+P2 IMPLEMENTED, REQUIRED E2E PASS, SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser verified the tree: exactly 12 files (pubspec.yaml 2-line dep swap → flutter_edge_ai ^1.11.4 / flutter_edge_ai_mediapipe ^1.0.8; pubspec.lock; 3 lib + 2 test files; **5 registrants with real diffs** — linux .cc 4/4, linux cmake 1/1, macos .swift 2/2, windows .cc 3/3, windows cmake 1/1 — so the conditional registrant chore commit is REQUIRED per the cycle-6 rule); zero discontinued refs in pubspec.yaml + lib/; engine registration preserved verbatim (`FlutterEdgeAi.initialize(inferenceEngines: const [MediaPipeEngine()], maxDownloadRetries: 3)`, non-fatal catch at :186-188, comment updated); gates re-run — analyze exit 0, format 0 changed, 208/208. Fallback rule unused; 8/8 preservation items hold; mediapipe 1.0.8 is the correct 1.x engine (1.2.2 needs core ^2.3.0 — Reviewer-verified from pub cache). Non-blocking carry-forward recorded: stale cosmetic "flutter_gemma" comments at android/app/proguard-rules.pro:9 + ios/Podfile:10-20 (functional rules/floors valid — future cheap cycle). Device-inference advisory stands (non-gating): user smoke-tests offline chat with the promoted APK post-green. Commits: `refactor(ai): migrate offline engine to flutter_edge_ai (flutter_gemma discontinued)` → `chore: regenerate plugin registrants for flutter_edge_ai` (REQUIRED — diffs exist) → `docs(plans): close cycle 6 and open cycle 7 plan`. Version bump: none; next tag carries 1.2.4. |
| pending | agent-push: push main (3 commits — registrant chore is required this cycle), watch BOTH workflows → **Build APK green COMPILING THE MIGRATED ENGINE** (definitive acceptance; failure class to name if red: native/Gradle/plugin resolution errors), Promote to Landing green (the promoted APK is the user's smoke-test artifact for the device-inference advisory). On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-8 audit (pre-ranked: cheap F17+F15 cluster). On red: capture `gh run view --log-failed`, plan stays `active`, fix phase possibly invokes the migration's revert discipline (back to flutter_gemma finals). |

- Cycle-8 pre-ranked: cheap F17 (pin removal — precondition met) + F15 (optional tag-guard history check) cluster.
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing escalation to the user before scheduling.
- This plan is `done` only when P1+P2 PASS review (after the e2e run), the push is Adviser-approved and executed, and BOTH workflows are green.
