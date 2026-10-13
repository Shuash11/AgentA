# Cycle 13 — connectivity_plus 7 Migration (F11 part 3c-1) — Map-First

**status:** active
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 13 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 310a8fa
**predecessors:** plans/done/cycle-1..12 (all closed, CI green; latest runs 38416344603 / 38418409454)

## Cycle 13 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 12th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| **Connectivity surface (corrected)** | 56 matches / 22 files — but MOST are the app's own abstractions (`ConnectivityService`/`ConnectivityCubit`/`InternetStatus`, version-independent). The **version-dependent package API** (`connectivity_plus` import, `Connectivity()`, `onConnectivityChanged`, `ConnectivityResult`) lives in **`lib\core\utils\connectivity_service.dart` only** (the single direct package consumer; the cubit consumes the app's own `statusStream`). P1 confirms the exact direct-consumer list. |
| Current usage (from cycle-1 read) | `Connectivity()` + `_connectivity.onConnectivityChanged.listen(...)` in `ConnectivityService.init()` — the app never exposes raw `ConnectivityResult` beyond its own `InternetStatus` enum |
| Known app debt in the same file | F13 (fresh `HttpClient` per probe; `_lastStatus` defaults offline) — deliberately NOT bundled (one risk surface per cycle) |
| CI | runs 38416344603 / 38418409454 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F11 part 3c-1** | **connectivity_plus 6.1.5 → 7.3.2.** The smallest lattice yet: a single direct package consumer behind the app's own `InternetStatus` abstraction. Breaking changes (candidate areas: `onConnectivityChanged` result-shape evolution, platform/web support changes) must be extracted from the official changelog with citations (P1). **SELECTED as the cycle-13 task.** | maintainability | pub outdated; single-consumer surface | middle-end | **EXPENSIVE** |
| **F11 part 3c-2..4** | **Remaining small majors** (flutter_dotenv 6.0.1, cupertino_icons 2.0.0, flutter_launcher_icons 0.14.4) — each its own cycle after 3c-1. | maintainability | pub outdated | middle-end | EXPENSIVE |
| **F11 part 4** | **^11 fss `checkUpgradeStatus()` follow-up** — design recorded (cycle 9 P1); **GATED on the user cutting the next release tag**. | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe — IN THE SAME FILE as this cycle's map. Deliberately NOT bundled (one risk surface per cycle); candidate to pair with the NEXT connectivity-adjacent touch if ever convenient. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F6-residue** | `hashPassword` outside `tryUpgrade`'s try (login.dart:365,459) — theoretical only; move inside if ever touched. | security (nit) | cycle-10 review | middle-end | CHEAP |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — deliberate deferral; AGP 9 migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F15 residue / F16 / F19** | Duplicate-semver guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (13 cycles).** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: the majors queue proceeds smallest-risk-first; connectivity_plus 7 has the smallest blast radius of the remaining majors (one direct consumer behind the app's own abstraction) and its failure mode (offline detection) is heavily test-covered (dashboard/sync suites) + device-smokeable.

---

## Selected task (single): F11 part 3c-1 — connectivity_plus 7, map-first

**Objective:** connectivity_plus ^7.3.2 live with every package-API adaptation mechanical per the migration map; the app's `InternetStatus` abstraction (and everything built on it — SyncService, AppShell offline mode, connectivity cubit) unchanged; all gates + e2e + CI green.

**Version bump decision: none** — dependency migration is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **P2 is EXPENSIVE (runtime connectivity behavior drives SyncService + offline mode), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch.

**STOP RULE (binding, cycles 7/9/10/12 precedent):** if P1 cannot map the migration mechanically from the official changelog ALONE — a breaking change without a documented equivalent, or an ambiguous usage — P1 ends in STOP: no constraint edit in P2, evidence and gaps recorded, the Adviser re-scopes. A migration resting on guesswork NEVER ships.

**RISK ACKNOWLEDGMENT (honest, plan-level):** connectivity drives the app's offline mode and sync triggers; the suites cover dashboard/sync reactions at unit level, but **real radio-state transitions (wifi↔mobile↔none) are not gate-coverable** — non-gating advisory: after green, the user toggles airplane-mode/wifi on a device with the promoted APK and confirms the offline banner + sync-flush react as before.

---

## Phase 1 — Migration map (read-only evidence pass)

- **Phase id:** P1
- **Objective:** a complete old→new map for the direct package consumer(s), driven by the official changelog — or an honest STOP.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only)
- **Implementation steps:**
  1. Extract the official 6→7 breaking-change list with verbatim changelog/migration-guide citations (pub.dev/packages/connectivity_plus CHANGELOG; candidate areas — result-shape changes to `onConnectivityChanged`, platform support changes, deprecations — are HYPOTHESES to verify, not facts).
  2. Confirm the exact direct-consumer list: grep for the package API (`connectivity_plus` import, `Connectivity(`, `onConnectivityChanged`, `ConnectivityResult`) — expected: `connectivity_service.dart` only; verify the cubit/repositories/screens consume only the app's own `InternetStatus`/`statusStream` (version-independent).
  3. Map every direct-API site: unchanged / mechanically-updated / non-mechanical, each authorized by a cited changelog line.
  4. Confirm version pin: `connectivity_plus: ^7.3.2` resolves with the current lock (no lattice entanglement — connectivity_plus is independent of the fss/win32 lattice; verify).
  5. **STOP decision:** any breaking change without a documented equivalent → STOP; record everything.
- **Acceptance criteria:** direct-consumer list confirmed; every site mapped with citations; or STOP with the specific gap.
- **Verification:** **CHEAP** — read-only; no e2e impact.
- **Dependencies / sequencing:** first; P2 executes only a clean map.
- **Expected result:** P2 fully determined, or an honest deferral.

## Phase 2 — Apply the migration

- **Phase id:** P2
- **Objective:** the app compiles, passes the full suite (222), and behaves identically on connectivity_plus 7.
- **Responsible subagent:** middle-end
- **Files to change:** `pubspec.yaml` (connectivity_plus ^7.3.2), `pubspec.lock`, `lib/core/utils/connectivity_service.dart` (only if the map requires adaptation)
- **Implementation steps:**
  1. Apply the map mechanically: constraint bump; package-API updates strictly per the map (each authorized by a cited changelog line).
  2. Preserve semantics: `InternetStatus` abstraction, `statusStream` contract, and every downstream consumer (SyncService, AppShell, cubit) untouched — a behavior-diffing reviewer finds only the package-API layer changed.
  3. Test updates only if the map demands (expected: none — the suites mock the app abstraction, not the package).
  4. Local validation: `flutter analyze` exit 0 (flutter_lints 6), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` all pass.
  5. **STOP-and-revert on any non-mechanical gap** (fallback rule).
- **Acceptance criteria:** constraint = the designed line only; diffs = the map site-by-site; downstream semantics preserved; gates green.
- **Verification:** **EXPENSIVE** — runtime connectivity behavior. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: analyze ×2 exit 0, 222/222, format 0, `pub get --enforce-lockfile` idempotent, direct-consumer-grep audit.
- **Dependencies / sequencing:** after P1's clean map (STOP forbids P2).
- **Expected result:** the connectivity stack on a maintained major behind the app's own abstraction.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `refactor(connectivity): migrate to connectivity_plus 7 (map-driven, behavior-preserving)` — pubspec.yaml, pubspec.lock, adapted consumer file(s) if the map requires. Atomic: constraint + required code changes never split.
- Commit 2 (conditional, cycle-6 rule): `chore: regenerate plugin registrants to match updated dependencies` — ONLY if registrant diffs exist at push time (likely for a platform plugin — check); otherwise SKIP.
- Commit 3: `docs(plans): close cycle 12 and open cycle 13 plan` — stage `plans/` explicitly (deletion of old cycle-12 path, `plans/done/cycle-12-...md`, new cycle-13 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); no other pubspec constraints (dotenv/cupertino_icons/launcher_icons stay queued).
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — the runner compiles the migrated connectivity layer (registrant/regeneration implications surface here for the Android plugin) under flutter_lints 6 with 222+ tests. **Failure class to name if red:** plugin/registrant resolution errors or Dart compile errors at the consumer site — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase = scoped revert to ^6.1.5 (the map documents every change).
- **Promote to Landing** green as usual — the promoted APK is the airplane-mode/wifi-toggle smoke-test artifact (user advisory above).
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-14 audit (pre-ranked: F11 part 3c-2 — flutter_dotenv 6 next, each remaining small major its own cycle).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `connectivity_plus 7.0.0 changelog breaking changes` (pub.dev/packages/connectivity_plus — the official 6→7 delta, verbatim).
2. `connectivity_plus onConnectivityChanged List ConnectivityResult migration` (the documented result-shape history and any 7.x change).
3. `connectivity_plus 7.3.2 platform support android ios` (pub.dev — platform/SDK floors for the resolved version).
4. `connectivity_plus 7 dart sdk minimum` (pub.dev — compatibility with Dart 3.13.5 / Flutter 3.47.6).

## Reviewer verification commands (single pass, after P1+P2)

1. `git diff pubspec.yaml` → exactly the connectivity_plus line; `pubspec.lock` → connectivity_plus 7.3.x.
2. Direct-consumer audit: grep the package API (`connectivity_plus|Connectivity\(|onConnectivityChanged|ConnectivityResult`) → all changed sites match the P1 map; the app abstraction (`InternetStatus`, `statusStream`, `ConnectivityService` public contract) unchanged.
3. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` 222/222, `dart format --output=none --set-exit-if-changed lib test` exit 0; `flutter pub get --enforce-lockfile` idempotent.
4. Scope: no other constraints touched; analysis_options.yaml absent; .opencode/ absent; registrant changes only per the conditional commit rule.
5. If P1 STOPped: verify clean revert (empty git diff) + recorded gaps.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-13 audit recorded; plan created `active` (task F11 part 3c-1). Direct-consumer surface established: 1 file behind the app's own abstraction. F13 adjacency noted and deliberately excluded. STOP rule + risk acknowledgment recorded. |
| 2026-10-13 | **P1 COMPLETE (no STOP) + ADVISER R1 RULINGS.** P1's map: zero code changes needed (sole consumer unaffected — same import, same `Connectivity()`/`onConnectivityChanged` usage; the adapter ignores the event payload and re-probes via its own HTTP check; result-shape churn predates the current lock). **R1: PROCEED-AS-IS (option a).** Ruling rationale: the in-repo empirical precedent is the strongest evidence class available — `package_info_plus 10.2.2` carries the IDENTICAL requirements line (AGP ≥8.12.1, Gradle ≥8.13, Kotlin ≥2.2.0) and its own AGP classpath, and has compiled **green in this repo's CI on this exact toolchain (AGP 8.11.1) since cycle 9** (runs 38340769615 through 38418409454) — if the floor were a hard build-failure trigger, those runs would have failed. Safety net = the loop's proven pattern (constraint+lock-only, CI gate as definitive proof, scoped revert as fallback), with the **AGP 8.11.1→8.12.1 bump recorded as the DESIGNED contingency** (P1's alternative becomes the pre-designed fix-phase option, NOT a live phase — respects the one-risk-surface rule and the cycle-1 minimal-floor principle; if CI forces it, the bump also records its F18 adjacency: 8.12.1 stays below the 9.0.1 warn boundary). **P2 SCOPE CONFIRMED:** pubspec.yaml 1 line + lock only; zero code/test changes; lib/test zero diffs enforced; expected lock movement = connectivity_plus 7.3.2, nm 0.6.x, dbus 0.8.x (platform_interface 2.1.0 unchanged) — **any movement outside that named set = stop-and-report**. **REVIEWER ARMED:** evaluate R1 as a *documented deviation with in-repo precedent* (not a mismatch), citing the package_info_plus 10.2.2 CI-green runs; the Reviewer verifies the precedence claim (runs green + requirements-line parity) and confirms the CI-gate-as-proof + designed-contingency design is armed. |
| 2026-10-13 | **P1+P2 IMPLEMENTED (zero code changes, per map), REQUIRED E2E PASS, SINGLE-PASS REVIEW PASS (R1 documented deviation CONFIRMED), PUSH APPROVED by Adviser.** Adviser independently verified: pubspec.yaml = exactly the 1 constraint line (^6.0.3→^7.3.2); named lock set EXACT — connectivity_plus 7.3.2, platform_interface 2.1.0 (unchanged, as P1 predicted), nm 0.6.0, dbus 0.8.0; **contingency file untouched** (settings.gradle + lib/test clean — the AGP contingency correctly not live); no registrant diffs (skip correct); gates re-run — analyze exit 0, format 0 changed, 222/222. Reviewer's R1 confirmation from primary sources: requirements-line parity (identical AGP ≥8.12.1/Gradle ≥8.13/Kotlin 2.2.0 trio) AND package_info_plus 10.2.2's green APK-build CI history on this exact toolchain (locked at cc88764, verified ancestor of run 38340769615's head; 38388465650/38416344603/38418409454 all green); contingency + scoped revert armed. Non-blocking notes: plan-header phrasing nit (6.1.5 vs ^6.0.3 — both accurate in their domains); radio-state device smoke test remains user-side. Commits: `refactor(connectivity): migrate to connectivity_plus 7 (map-driven, behavior-preserving)` (pubspec.yaml + lock, atomic) → registrant chore SKIPS → `docs(plans): close cycle 12 and open cycle 13 plan`. Version bump: none; next tag carries 1.2.4. |
| pending | agent-push: push main (2 commits — registrant chore skips), watch BOTH workflows → **Build APK green = the definitive R1 proof** (Gradle resolving connectivity_plus 7 with its own AGP 8.12.1 classpath under the repo's AGP 8.11.1 — the precedent says it passes; failure class if red: Gradle/AGP version-check or plugin-compile errors at the APK build step → fix phase chooses between the designed AGP 8.12.1 contingency and the scoped revert to ^6.1.5), Promote to Landing green — **the promoted APK is the airplane-mode/wifi-toggle smoke-test artifact** (non-gating advisory: offline banner + sync-flush react as before). On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-14 audit (pre-ranked: F11 part 3c-2 — flutter_dotenv 6, AppConfig-only surface). On red: capture `gh run view --log-failed`, plan stays `active`, fix phase planned. |

- Cycle-14 pre-ranked: **F11 part 3c-2** (flutter_dotenv 6 — small surface: AppConfig only). The ^11 fss follow-up remains gated on the user's next release tag; **F4/F5/F12 remain CLOUD-BLOCKED** (13 cycles) — standing user escalation.
- This plan is `done` only when P1+P2 PASS review (after the e2e run; or the STOP-deferral is recorded and the plan closes via Adviser re-scope), the push is Adviser-approved and executed, and BOTH workflows are green.
