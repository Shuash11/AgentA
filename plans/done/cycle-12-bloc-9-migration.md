# Cycle 12 — flutter_bloc 9 Migration (F11 part 3b) — Map-First

**status:** done (closed 2026-10-13 — P1+P2 PASS + e2e, push executed, both workflows green; bloc 9 landed as a pure constraint swap)
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 12 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 17122e4
**predecessors:** plans/done/cycle-1..11 (all closed, CI green; latest runs 38400605101 / 38402376817)

## Cycle 12 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` (strictest lints — flutter_lints 6 live) | **"No issues found!" exit 0** — 11th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| **True bloc surface (recursive, corrected)** | **193 matches across 25 files**: 4 cubit files (chat :3, connectivity :3, theme :3, update :6), `cubit\app_providers.dart` :10, `main.dart` :4, **15 presentation files** (every screen: BlocProvider/BlocBuilder/context.read), 3 test files (85 — update_feature_test :66 dominates). This IS the state-management layer. |
| Lattice queue (post-lints pub outdated) | flutter_bloc 8.1.6 → 9.1.1; bloc 8.1.4 → 9.2.1; connectivity_plus 7.3.2; flutter_dotenv 6.0.1; cupertino_icons 2.0.0; flutter_launcher_icons 0.14.4 |
| Analyzer state | flutter_lints 6 live (cycle 11) — the bloc-9 diff inherits the strictest scrutiny |
| CI | runs 38400605101 / 38402376817 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F11 part 3b** | **flutter_bloc 8 → 9.1.1 (+ bloc 9.2.1 transitive).** The entire state-management layer (193 matches / 25 files). Breaking changes must be extracted from the official changelog with citations (P1) — the pre-cycle brief listed BlocBase/API updates, dart-3 alignment, Emitter API as candidates, NOT verified facts. **SELECTED as the cycle-12 task** — map-first with a binding STOP rule. | maintainability | pub outdated; 25-file surface | middle-end | **EXPENSIVE** |
| **F11 part 3c** | **Small majors** (connectivity_plus 7, flutter_dotenv 6, cupertino_icons 2, flutter_launcher_icons 0.14) — independent constraint cycles AFTER 3b; each smaller than the fss lattice. | maintainability | pub outdated | middle-end | EXPENSIVE |
| **F11 part 4** | **^11 fss `checkUpgradeStatus()` follow-up** — design recorded (cycle 9 P1); **GATED on the user cutting the next release tag**. | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **F6-residue** | `hashPassword(password)` evaluated outside `tryUpgrade`'s try (login.dart:365,459) — theoretical only; move inside the try if ever touched again. | security (nit) | cycle-10 review | middle-end | CHEAP |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — deliberate deferral; AGP 9 migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15 residue / F16 / F19** | Duplicate-semver guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (12 cycles).** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: the analyzer is hardened (flutter_lints 6, cycle 11) specifically so this diff inherits the strictest scrutiny — the sequencing rationale from cycle 11 executes now. The 25-file surface makes this the loop's largest migration; the map-first + STOP design bounds the downside exactly as proven in cycles 7/9/10.

---

## Selected task (single): F11 part 3b — flutter_bloc 9 migration, map-first

**Objective:** flutter_bloc ^9.1.1 (+ bloc 9.2.1) live across the 25-file state-management layer with every change mechanical per the migration map, all gates + e2e + CI green, zero behavior drift (state machines, event flows, and UI reactions byte-equivalent in intent).

**Version bump decision: none** — dependency migration is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **P2 is EXPENSIVE (runtime state-management behavior), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch.

**STOP RULE (binding, cycles 7/9/10 precedent):** if P1 cannot map the migration mechanically from the official changelog/migration guide ALONE — i.e., a breaking change without a documented equivalent, or a repo usage pattern whose migration is ambiguous — P1 ends in STOP: no constraint edit in P2, evidence and gaps recorded, the Adviser re-scopes (deferral with evidence, or substitution). A migration resting on guesswork NEVER ships.

**RISK ACKNOWLEDGMENT (honest, plan-level):** 222 tests cover the update cubit machine, dashboard flows, and widget reactions — the strongest test coverage of any layer in the repo. Still, **device-level behavior across all 15 screens is not gate-coverable**; non-gating advisory: after green, the user smoke-tests the app's primary flows (login → dashboard → chat → profile) on the promoted APK.

---

## Phase 1 — Migration map (read-only evidence pass)

- **Phase id:** P1
- **Objective:** a complete site-by-site old→new map for all 25 files, driven by the official changelog/migration guide — or an honest STOP.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only)
- **Implementation steps:**
  1. Extract the official 8→9 breaking-change list with verbatim changelog/migration-guide citations (pub.dev/packages/flutter_bloc CHANGELOG + the bloc migration notes; the bloc 9.2.1 delta too). Candidate areas from the pre-cycle brief (BlocBase/API updates, dart-3 alignment, Emitter API) are HYPOTHESES to verify, not facts.
  2. Enumerate the surface precisely (the 25-file table above): for each file, list the flutter_bloc APIs used (extends Cubit/Bloc, emit, add, BlocProvider create/lazy, BlocBuilder buildWhen, BlocConsumer/listener, context.read/watch, BlocObserver if any).
  3. Map every site: unchanged / mechanically-updated (renamed API, moved import) / non-mechanical (behavioral). Cite the changelog line authorizing each mechanical change.
  4. Test-surface note: update_feature_test.dart (:66) and the dashboard tests — mock/fake updates per the same map; report any expected test-count change.
  5. Version pin decision: `flutter_bloc: ^9.1.1` (and confirm the transitive bloc lands 9.2.x).
  6. **STOP decision:** any breaking change without a documented equivalent, or any ambiguous repo pattern → STOP; record everything.
- **Acceptance criteria:** 100% of the 25 files mapped with citations; mechanical/non-mechanical classification per site; or STOP with the specific gap.
- **Verification:** **CHEAP** — read-only; no e2e impact.
- **Dependencies / sequencing:** first; P2 executes only a clean map.
- **Expected result:** P2 fully determined, or an honest deferral.

## Phase 2 — Apply the migration

- **Phase id:** P2
- **Objective:** the app compiles, passes the full suite (222+), and behaves identically on flutter_bloc 9.
- **Responsible subagent:** middle-end
- **Files to change:** `pubspec.yaml` (flutter_bloc ^9.1.1), `pubspec.lock`, the mapped lib/ files, mapped test/ files
- **Implementation steps:**
  1. Apply the map mechanically: constraint bump; imports/renames/API updates strictly per the map (each authorized by a cited changelog line).
  2. Preserve state-machine semantics: same states, same transitions, same buildWhen/listener logic — a reviewer diffing behavior should find only the API layer changed.
  3. Test updates strictly per the map (mocks/fakes for any renamed base classes); report any test-count change explicitly.
  4. Local validation: `flutter analyze` exit 0 (flutter_lints 6 set), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` all pass.
  5. **STOP-and-revert on any non-mechanical gap** (fallback rule).
- **Acceptance criteria:** constraint = the designed line only; lib/test diffs = the map site-by-site; state-machine semantics preserved; gates green.
- **Verification:** **EXPENSIVE** — runtime state-management behavior. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: analyze ×2 exit 0 (flutter_lints 6), 222+ tests all-pass, format 0, `pub get --enforce-lockfile` idempotent, surface-grep audit.
- **Dependencies / sequencing:** after P1's clean map (STOP forbids P2).
- **Expected result:** the state-management layer on maintained majors, scrutinized by the strictest lint set.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `refactor(state): migrate to flutter_bloc 9 (map-driven, behavior-preserving)` — pubspec.yaml, pubspec.lock, mapped lib/ + test/ files. Atomic: constraint + required code changes never split.
- Commit 2 (conditional, cycle-6 rule): `chore: regenerate plugin registrants to match updated dependencies` — ONLY if registrant diffs exist at push time; otherwise SKIP.
- Commit 3: `docs(plans): close cycle 11 and open cycle 12 plan` — stage `plans/` explicitly (deletion of old cycle-11 path, `plans/done/cycle-11-...md`, new cycle-12 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); no other pubspec constraints (connectivity_plus/dotenv/cupertino_icons/launcher_icons stay queued).
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — the runner compiles the migrated state layer under flutter_lints 6, runs 222+ tests, and builds the APK. **Failure class to name if red:** Dart compile errors at cubit/presentation sites, or test failures in the bloc-dependent suites — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase likely scoped revert to ^8.1.6 (always possible: the map documents every change).
- **Promote to Landing** green as usual — the promoted APK is the primary-flows smoke-test artifact (user advisory: login → dashboard → chat → profile).
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-13 audit (pre-ranked: F11 part 3c small majors — connectivity_plus 7 first, each its own cycle).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `flutter_bloc 9.0.0 changelog breaking changes` (pub.dev/packages/flutter_bloc — the official 8→9 delta, verbatim).
2. `bloc 9.0.0 migration guide Emitter BlocBase` (bloclibrary.dev / github.com/felangel/bloc — the official migration notes for every breaking change P1 maps).
3. `bloc 9.2.1 changelog` (post-9.0 patches relevant to the resolved version).
4. `flutter_bloc 9 dart sdk minimum requirement` (pub.dev — compatibility with Dart 3.13.5 / Flutter 3.47.6).

## Reviewer verification commands (single pass, after P1+P2)

1. `git diff pubspec.yaml` → exactly the flutter_bloc line; `pubspec.lock` → flutter_bloc 9.1.x + bloc 9.2.x.
2. Surface audit: recursive grep (`BlocBase|flutter_bloc|BlocProvider|BlocBuilder|BlocConsumer|BlocListener|Cubit|BlocObserver`) → all changed sites match the P1 map site-by-site; zero unmapped behavioral diffs.
3. Semantics audit: cubit state classes and transition logic unchanged (diff inspection: state classes/emit calls semantically identical); buildWhen/listener logic preserved.
4. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` all-pass (quote count vs 222), `dart format --output=none --set-exit-if-changed lib test` exit 0; `flutter pub get --enforce-lockfile` idempotent.
5. Scope: no other constraints touched; analysis_options.yaml absent; .opencode/ absent.
6. If P1 STOPped: verify clean revert (empty git diff) + recorded gaps.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-12 audit recorded; plan created `active` (task F11 part 3b). True surface established: 193 matches / 25 files (recursive count corrected the earlier 99/5-file undercount). STOP rule + risk acknowledgment recorded. |
| 2026-10-13 | **P1+P2 IMPLEMENTED, REQUIRED E2E PASS, SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Outcome: the "largest migration of the loop" turned out to be a **pure constraint swap with zero code changes** — Adviser independently verified: pubspec.yaml = exactly the flutter_bloc ^8.1.6→^9.1.1 line; lock = flutter_bloc 9.1.1 + bloc 9.2.1; **lib/test blob-identical**; gates re-run — analyze exit 0 (flutter_lints 6), format 0 changed, 222/222. The zero-change claim corroborated from the PRIMARY source in the Adviser's own fetch: flutter_bloc 9.0.0 has ZERO BREAKING entries (mounted-listener fix + bloc ^9.0.0 upgrade + Dart 2.14 floor + chores; 9.1.x additive); the 2 real breaking items (EmittableStateStreamableSource implements-clause, BlocOverrides removal) live in **bloc** 9.0.0 and touch zero repo usages (no BlocBase/Overrides/Emitter/blocTest/hydrated_bloc/BlocObserver anywhere — repo greps 0 hits); the widget-layer usage was untouched by 9.0.0. P1's hypothesis-driven map did its job: it proved the hypotheses false and the swap safe. Reviewer corroborated from fresh changelogs + bloclibrary migration guide (zero applicable items, walked 1:1); commit type `refactor(state):` and registrant-chore SKIP confirmed (pure Dart). Non-blocking doc-precision note recorded (plan's per-bucket match arithmetic — all definitive figures verify exactly). Commits: `refactor(state): migrate to flutter_bloc 9 (map-driven, behavior-preserving)` (pubspec.yaml + lock, atomic — no code files exist to pair) → registrant chore SKIPS → `docs(plans): close cycle 11 and open cycle 12 plan`. Version bump: none; next tag carries 1.2.4 and unlocks the ^11 fss follow-up. |
| 2026-10-13 | **Push EXECUTED** — `b516253` refactor(state) (pubspec.yaml + lock only), `310a8fa` docs(plans); remote main = `310a8fa`; no version bump; tags untouched; registrant chore skipped (pure Dart). |
| 2026-10-13 | **CI GREEN — PLAN CLOSED.** Build APK run **38416344603 SUCCESS (14m4s)**: 26/26 steps green — analyze (flutter_lints 6), format gate, 222/222 tests, APK build + all guards; **runner-side proof the state-management layer compiles on flutter_bloc 9.1.1/bloc 9.2.1**; annotations informational only. Promote to Landing run **38418409454 SUCCESS (1m54s)**: full promotion (12 steps), no skip — the promoted APK is the primary-flows smoke-test artifact (user advisory). The pre-cycle "largest migration" hypothesis was falsified by P1's map: flutter_bloc 9.0.0 shipped ZERO breaking entries and the repo uses neither of bloc 9.0.0's two breaking items — the map-first discipline turned the loop's biggest fear into its cleanest swap. Zombie run untouched (accepted). Moved to `plans/done/`. |

- Cycle-13 pre-ranked: **F11 part 3c** (connectivity_plus 7 first — each small major its own cycle). The ^11 fss follow-up remains gated on the user's next release tag; **F4/F5/F12 remain CLOUD-BLOCKED** (12 cycles) — standing user escalation.
- This plan is `done` only when P1+P2 PASS review (after the e2e run; or the STOP-deferral is recorded and the plan closes via Adviser re-scope), the push is Adviser-approved and executed, and BOTH workflows are green.
