# Cycle 18 — Connectivity Probe Hardening (F13) — the last self-contained non-gated item

**status:** active
**created:** 2026-10-14
**created by:** Adviser (self-improvement cycle 18 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ b356acf
**predecessors:** plans/done/cycle-1..17 (all closed, CI green; latest runs 38521746312 / 38523136270)

## Cycle 18 ground truth (fresh evidence, 2026-10-14)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 18th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| `flutter pub outdated` | **ONLY the gated ^11 fss 11.2.0** — the voluntary dependency queue is EMPTY (dotenv, cupertino_icons, launcher_icons cleared in cycles 15-17; launcher regeneration = developer one-shot action) |
| **F13 surface** | Fix contained in **1 file** (`lib\core\utils\connectivity_service.dart`, 7 self-matches): fresh `HttpClient` per probe (:44 area) + `_lastStatus` offline-until-first-probe boot window. Consumers (15 files: repositories isOnline(), version_check, sync, screens, cubit) depend ONLY on the `InternetStatus`/`statusStream`/`isOnline()`/`lastStatus` contract — **the contract stays unchanged; the fix is internal**. Tests mock the service abstraction (sync_service_test, version_check_service_test, dashboard tests) — probe changes are internal. |
| Runner watch (F18) | Cycle 17's run executed on **Ubuntu 24.04** (ubuntu24/20261004.327) — Ubuntu 26 migration (~Oct 19, 5 days out) is NOTICE-ONLY so far; no delta. |
| CI | runs 38521746312 / 38523136270 green; zero deprecations |

## Findings backlog (re-ranked, uncapped) — with the frontier analysis

**THE FRONTIER:** after cycle 17 cleared the small-majors queue, the remaining backlog is: 1 self-contained improvement (F13, this cycle), 1 large toolchain migration (F18 AGP-9), 1 theoretical nit (F6-residue), and items that are **user-gated or cloud-blocked** (F11-part-4, F4/F5/F12, B2). The user's decisions (release tag, Supabase access, desktop direction) now gate most remaining value.

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F13** | **Connectivity probe hardening** — fresh `HttpClient` per probe (allocation churn; probes fire on every connectivity_plus event) + the boot false-offline window (`_lastStatus` defaults offline until the first ~5s-timeout probe completes). **SELECTED as the cycle-18 task** — the last self-contained non-gated improvement; fix internal to 1 file; consumers untouched. | performance / robustness | connectivity_service.dart:44 + the boot window; 15-consumer contract map | middle-end | **EXPENSIVE** |
| **F18** | **AGP-9 + Built-in-Kotlin toolchain migration** (Gradle 8.14/AGP 8.11.1 below Flutter warn thresholds 9.1.0/9.0.1; repo carries `android.builtInKotlin=false`/`newDsl=false` migrator flags) — the largest remaining real debt, substantial risk, no visible deadline (checker warns only). **DEFERRED to its own future cycle with a dedicated map-first**; also tracks the Ubuntu 26 runner migration (notice-only as of Oct 14; due ~Oct 19 — watch the first post-date run). | CI / toolchain | DependencyVersionChecker.kt warn values; runner observation | backend | EXPENSIVE |
| **F6-residue** | `hashPassword` outside `tryUpgrade`'s try (login.dart:365,459) — theoretical only (disproven by golden vector + 222 tests). Cheap fix but sits in the auth path → EXPENSIVE ceremony for a theoretical nit; poor ROI as a standalone cycle — fold into the next auth-path touch. | security (nit) | cycle-10 review | middle-end | EXPENSIVE (as standalone) |
| **F11 part 4** | ^11 fss `checkUpgradeStatus()` follow-up — **GATED on the user cutting the next release tag** (staged-rollout safety). | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **B2** | Desktop-identity — **PARKED pending user direction** (inert until desktop builds ship; trigger recorded). | branding | cycle-17 ruling | — | CHEAP (when triggered) |
| **F15 residue / F16 / F19** | Duplicate-semver guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (18 cycles). The single biggest blocker to remaining value.** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: with the voluntary dependency queue empty, F13 is the only self-contained non-gated improvement left. Honest assessment: LOW severity, but real (probe churn on every radio event + a boot false-offline window), contained to 1 file behind an unchanged contract, and completing it leaves only F18 (big/risky/undated), F6-residue (nit), and user-gated/blocked items — after this cycle the loop's remaining value is largely behind user decisions.

---

## Selected task (single): F13 — connectivity probe hardening

**Objective:** one reusable probe client instead of a fresh `HttpClient` per probe; the boot status window handled without a false-offline contract change; the `InternetStatus`/`statusStream`/`isOnline()`/`lastStatus` contract byte-preserved; all gates + e2e + CI green.

**Version bump decision: none** — behavior polish is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **P2 is EXPENSIVE (connectivity behavior drives SyncService + offline mode), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch.

**STOP RULE (binding, cycles 7/9/10/12/13/15/16 precedent):** P1 designs the fix shape. **If either fix requires changing the consumer-facing contract** (`InternetStatus` enum shape, `statusStream` element type, `isOnline()`/`lastStatus` semantics) **or cannot be contained in connectivity_service.dart → STOP**, record, and the Adviser re-scopes (deferral is acceptable — LOW severity; the current behavior is correct, just suboptimal).

---

## Phase 1 — Probe-lifecycle design (read-only evidence pass)

- **Phase id:** P1
- **Objective:** the exact fix shape for both issues, contract-preservation proven — or an honest STOP.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only)
- **Implementation steps:**
  1. Inventory: every `checkInternetStatus()`/`isOnline()`/`lastStatus` call site (the 15-file map above, filtered to real calls) and their frequency (per-event vs one-shot) — establishes what the fix must preserve.
  2. Fix shape for the client churn: a single lazily-created `HttpClient` (static/instance field, `connectionTimeout` kept, no per-probe construction/teardown) — cite dart:io HttpClient reuse semantics; confirm no state leakage between probes (headers/timeouts reset per request).
  3. Fix shape for the boot window: analyze the actual window (construction → `init()` → first probe completes, up to ~5s×3 URLs worst case) and choose WITHOUT contract change: e.g., ensure the first probe starts synchronously in `init()` (already does — verify), consider whether `_lastStatus` initialization can await the first probe before any consumer can observe it (trace the main.dart :216 fire-and-forget ordering vs the cubit's subscription timing — the cubit subscribes AFTER AppProviders mounts, so the window may already be narrower than the finding implies; measure, don't assume).
  4. If the window fix requires `InternetStatus.unknown` or contract changes → STOP (that's a different, larger task).
  5. Test plan: existing tests mock the abstraction (sync/version_check/dashboard) — probe changes are internal; add/adjust only if the design alters testable seams.
  6. **STOP decision:** contract change needed, or the client-reuse fix has unsafe HttpClient semantics (per dart:io docs) → STOP; record everything (deferral sound: LOW severity, current behavior correct).
- **Acceptance criteria:** fix shapes stated for both issues with the contract-preservation argument; call-site frequency measured; test plan recorded; or STOP with the specific gap.
- **Verification:** **CHEAP** — read-only; no e2e impact.
- **Dependencies / sequencing:** first; P2 executes only a clean design.
- **Expected result:** P2 fully determined, or an honest deferral.

## Phase 2 — Implement the probe hardening

- **Phase id:** P2
- **Objective:** the probe reuses one client; the boot window handled per design; consumers byte-untouched.
- **Responsible subagent:** middle-end
- **Files to change:** `lib/core/utils/connectivity_service.dart` (the fix), possibly `test/` seam adjustments (only if P1's design says so)
- **Implementation steps:**
  1. Implement per the P1 design (client reuse + window handling); keep `connectionTimeout`, the 3-URL fallback order, and the swallow-and-continue error semantics byte-equivalent in intent.
  2. Consumers untouched: `InternetStatus`, `statusStream`, `isOnline()`, `lastStatus` signatures and semantics identical.
  3. Local validation: `flutter analyze` exit 0 (flutter_lints 6), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` → 222/222.
  4. **STOP-and-revert on any non-mechanical gap** (fallback rule).
- **Acceptance criteria:** single client reuse proven (code inspection: no per-probe construction); window handling per design; consumers byte-untouched; gates green.
- **Verification:** **EXPENSIVE** — connectivity behavior drives SyncService + offline mode. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: analyze ×2 exit 0, 222/222, format 0, contract-grep audit (consumer files zero-diff).
- **Dependencies / sequencing:** after P1's clean design (STOP forbids P2). P2 is the only application phase.
- **Expected result:** F13 closed; the last self-contained non-gated improvement done.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `perf(connectivity): reuse probe client and handle boot status window (F13)` — connectivity_service.dart (+ test seams per design). Atomic.
- Commit 2: `docs(plans): close cycle 17 and open cycle 18 plan` — stage `plans/` explicitly (deletion of old cycle-17 path, `plans/done/cycle-17-...md`, new cycle-18 file). Never root-wide `git add -A`/`git add .`
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); consumer files (repositories/cubit/screens/services) byte-identical.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — identical profile to run 38521746363-class runs (guards + format gate + strict-lint analyze + 222/222 + APK build). **Failure class to name if red:** Dart compile errors at connectivity_service or test failures in the connectivity-dependent suites — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase = scoped revert (the fix is 1-file).
- **Watch F18:** if this run is the first post-Oct-19 run, record the runner-image/toolchain deltas under F18 (observe and record only).
- **Promote to Landing** green as usual.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-19 audit. **Honest frontier statement for that audit:** after F13, the non-gated actionable queue is F18 (big/risky/undated) + F6-residue (nit, poor standalone ROI) — the user's decisions (release tag, Supabase access, desktop direction) gate the rest; the Adviser will surface whether a pause-for-user-input is the honest recommendation.

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `dart io HttpClient reuse multiple requests best practice` (api.flutter.dev / dart.dev — reuse semantics, per-request state isolation).
2. `HttpClient connectionTimeout per request dart` (api.flutter.dev — confirm the timeout behavior survives reuse).
3. `flutter connectivity check boot initial state pattern` (established patterns for the boot-window handling — supporting citation, not load-bearing).

## Reviewer verification commands (single pass, after P1+P2)

1. Contract audit: `git diff` → lib/core/utils/connectivity_service.dart only (+ test seams per design); **consumer files (repositories/cubit/screens/services/main) zero-diff**; `InternetStatus`/`statusStream`/`isOnline()`/`lastStatus` signatures identical.
2. Fix audit: no per-probe `HttpClient()` construction remains (grep `HttpClient(` in connectivity_service — one site); `connectionTimeout` + 3-URL fallback + swallow-and-continue semantics preserved.
3. Window audit: the P1 design's window handling implemented (quote the diff lines against the design).
4. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` 222/222, `dart format --output=none --set-exit-if-changed lib test` exit 0; `flutter pub get --enforce-lockfile` idempotent.
5. Scope: no other files; analysis_options.yaml absent; .opencode/ absent.
6. If P1 STOPped: verify clean revert (empty git diff) + recorded gaps.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-14 | Cycle-18 audit recorded; plan created `active` (task F13). Frontier analysis recorded: post-F13 the non-gated queue is F18 + F6-residue only; user decisions gate the rest. F18 updated (Ubuntu 26 watch: first run post-Oct 19). |
| 2026-10-14 | **P1 DESIGN + P2 IMPLEMENTED, REQUIRED E2E PASS, SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser independently verified: scope = connectivity_service.dart ONLY (22/14 — consumers byte-identical, contract audit clean); fix shape = hoisted `_connectionTimeout`/`_probeUrls` consts + lazy app-lifetime `HttpClient? _probeClient` (timeout set once at creation, per dart:io semantics) + dispose force-close + null; **exactly 1 `HttpClient(` site**; the boot-window issue (b) dispositioned as a verified NO-OP (ordering already maximal — hard elimination would require a contract change, STOP-gated out); drain awaited inside try (correct shape — generate_204 empty bodies; fire-and-forget would leak). Gates re-run — analyze exit 0, format 0 changed, 222/222. Reviewer: 4 searches cited (reuse semantics, connectionTimeout creation-time, drain/leak chain, broadcast-no-replay); drain-risk assessed acceptable; window no-op disposition confirmed sound. **Commit message AMENDED**: the planned "handle boot status window" clause dropped — the window disposition was a verified no-op, not a handled change; ratified message: `perf(connectivity): reuse probe client (F13)`. Commits: that / `docs(plans): close cycle 17 and open cycle 18 plan`. Version bump: none; next tag carries 1.2.4 and unlocks the ^11 fss follow-up. Drain-body-timeout note (probe URLs configurable) recorded as LOW/theoretical backlog. |
| pending | agent-push: push main (2 commits), watch BOTH workflows → **Build APK green — identical profile expected** (failure class if red = Dart compile errors at connectivity_service or connectivity-suite test failures → fix phase = scoped 1-file revert); **watch F18: if this is the first post-Oct-19 run, record runner-image/toolchain deltas (observe and record only — no fixes)**; Promote to Landing green as usual. On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-19 audit — **the honest frontier: the non-gated queue is F18 (big/risky/undated) + F6-residue (nit) only; user decisions (release tag, Supabase access, desktop direction) gate the rest — the audit will surface whether pausing for user input is the honest recommendation.** On red: capture `gh run view --log-failed`, plan stays `active`, fix phase planned. |

- Cycle-19 pre-ranked: **F18 AGP-9 toolchain migration** (map-first, its own careful cycle) or a user-input consolidation — the Adviser will surface the honest recommendation either way. The ^11 fss follow-up remains gated on the user's next release tag; **F4/F5/F12 remain CLOUD-BLOCKED** (18 cycles) — standing user escalation.
- This plan is `done` only when P1+P2 PASS review (after the e2e run; or the STOP-deferral is recorded and the plan closes via Adviser re-scope), the push is Adviser-approved and executed, and BOTH workflows are green.
