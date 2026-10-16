# Cycle 27 — Update-dialog DEFECT: diagnosis + fix (re-scoped from "audit")

**status:** active — cycle-26 closed 2026-10-16; P1 (the read-only middle-end diagnosis) delegated
**created:** 2026-10-16 by Adviser; **re-scoped:** 2026-10-16 (user defect report invalidates the audit premise)
**repo:** C:\projects\aiproject (AgentA) — the feature ships under `lib/services/update/`, `lib/cubit/update/`, `lib/presentation/shared/update_*`
**task level:** **Level 2 — Standard** (behavioral fixes in one repo; e2e ONCE + Reviewer ONCE at plan end because P2/P3 touch behavior). Contract gate: conditional — if the fix introduces a shared engine↔UI outcome type, run `contract-first` (read by path) before the consumer.
**environment note:** skills are NOT in the loadable registry — read BY PATH: `C:\projects\aiproject\.opencode\skills\<name>\SKILL.md`.

## Why re-scoped (the invalidated premise)

The Adviser's original premise — "the feature exists and is correctly wired; it never appeared because pubspec `1.2.5+1` vs release `v1.2.5` are equal → correctly silent" — is **invalidated by a real defect report**: the dialog does not appear on an installed **CI-signed `com.agenta.AgentA` 1.2.4** build **even though a newer release exists**. This is a live failure mode, not a no-op.

**Verified evidence (read-only, Orchestrator + Adviser):**
- GitHub releases healthy: `gh release list` → `v1.2.5 (Latest)`, v1.2.4, v1.2.3, v1.2.2, v1.2.1 — none draft/prerelease; `GET /releases/latest` returns v1.2.5 **with the APK asset** (`AgentA-v1.2.5.apk`). The "no release object" theory is ruled out; unauthenticated access works.
- The feature **is in the v1.2.4 tag**: `git ls-tree v1.2.4` shows all five files (`version_check_service`, `github_releases_source`, `version_source`, `update_cubit`, `update_dialog_host`); `git show v1.2.4:pubspec.yaml` → `version: 1.2.4+1`. Introduced in `a371ccd`.
- Wiring present: the check inits post-first-frame inside `_startMainApp` (fire-and-forget, plus_plugins #309 guard), and `UpdateDialogHost` mounts via the main `MaterialApp.builder`.
- Dismissal semantics: `update_dismissed_version` (SharedPreferencesAsync) is written **only** by the dialog host's post-close handler — a dismissal requires a previously SHOWN dialog; a newer release auto-re-triggers; pre-load results are buffered.

**Reproduction:** installed CI-signed 1.2.4 + published v1.2.5 (latest, APK asset) → dialog expected on/after launch → **absent**.

## Investigation list (P1 — each suspect gets a CONFIRMED / RULED-OUT verdict with evidence)

1. **Silent network failure (prime suspect).** The engine is offline-silent BY DESIGN (8s timeout, 403/429 rate-limit backoff, silent catch). **Release builds strip every `kDebugMode` log** — in the field the engine is completely unobservable. A device/network where `api.github.com` is blocked, DNS-failed, or times out produces exactly this symptom with zero feedback.
2. **Release-build gate.** The service skips checks unless `kReleaseMode` (`enabled: kReleaseMode`). Confirm the CI-signed APK is a `--release` build (check the CI workflow's build command); a debug/profile distribution would disable checks by design.
3. **Boot-path reachability.** Enumerate EVERY path from `main()` to the check's `init()` (it runs only in `_startMainApp`'s post-frame callback, reached via `AppInitStatus.databaseReady` — including the `_continueOffline` path, which DOES reach it). Identify every early-return that would skip it (e.g. a database-init failure returns before `_startMainApp`) and rate each for plausibility on the user's device.
4. **Persisted dismissal.** Confirm no writer other than the host's post-close handler exists; treat as a lesser suspect (it requires a prior shown dialog).
5. **Version source + semver.** Prove by trace (and optional scratch executable in the temp dir, never committed) that `decide()` returns `available` for current `1.2.4` (PackageInfo `versionName` on Android) vs the REAL v1.2.5 payload (`tag_name: v1.2.5`, `draft: false`, `prerelease: false`, APK asset). Check the `v`-prefix strip, `+1` build-number exclusion, and the strict-`^\d+\.\d+\.\d+$` parser.
6. **Timing/readiness.** Verify the host/cubit mount timing vs the init post-frame callback and the buffered-result path (a result emitted before the dismissal loads must still surface once loaded).

**Deliverable:** a diagnosis report naming the root cause(s) RANKED, each suspect's verdict with evidence, and the fix design for P2/P3 (including whether more than the affordance is needed).

## Adviser rulings (binding)

- **User-visible failure feedback: YES — this is part of the fix.** A silent update checker is itself the defect the user is complaining about ("a proper practice is a must"). Add a manual **"Check for updates"** row in the Profile screen (P3): runs `checkNow()` (the engine's user-initiated path — bypasses the 5-min throttle, respects the backoff gate) and surfaces the OUTCOME inline: checking → spinner; up-to-date → "You're on the latest version (vX)"; available → opens the existing dialog; **failed → "Couldn't check for updates" + the reason class (offline / timed out / rate-limited until HH:MM)** with a retry affordance. NO automatic failure toasts on background checks (that would nag); the manual row is the diagnostic surface.
- **Verification strategy:** hermetic tests are the PRIMARY acceptance (fake `VersionSource`: newer → dialog shows; equal/older → silent; forced → non-dismissible; 404/403/429 → silent + backoff honored; offline → background-silent AND surfaced by the manual row). The user's device is the LIVE DIAGNOSTIC, not the fix's acceptance: once the fixed build is installed there, the manual row will NAME the real failure on that network (confirming the diagnosis in the wild). The organic dialog demonstration happens at the next natural release (a build at vX cannot self-demonstrate until vX+1 is published — acknowledged, no test-release churn unless the user asks).
- **Version bump:** patch (`1.3.1+1`) if fixes land — preliminary; decided finally at push confirmation.

## Phases

### P1 — Diagnosis (CHEAP — read-only + report; no code changes)
- **Responsible:** middle-end (owns the engine). **Mandate:** zero repo mutations, zero device actions; the CI-signed device stays with the user. Work the six suspects above; each gets a verdict with evidence. Optional scratch executable proof lives in the temp dir and is never committed.
- **Deliverable:** the diagnosis report + the fix design + the web-research declarations.

### P2 — Engine/prefs fix (EXPENSIVE — behavior)
- **Responsible:** middle-end. Implement the P1 fix design: whatever the diagnosis names (e.g. boot-path reachability, backoff correctness, observability hooks the UI can read — a check-outcome surface the manual row consumes). Unit tests for every fixed path + the hermetic matrix above. If a shared outcome type crosses engine↔UI, read `contract-first` by path first and record the contract.
- Gates: analyze 0; suite green (record count).

### P3 — Manual check affordance + host/wiring (EXPENSIVE — new UI state + behavior)
- **Responsible:** frontend. The Profile "Check for updates" row per the ruling (all four outcomes), wired to the engine's outcome surface; any host/wiring fixes P1 named. Follows the ratified white-theme spec (§5 components, §7 a11y — the row is a labeled control; outcomes are text + icon, never color-only).
- Gates: analyze 0; suite green (record count).

## ORCHESTRATION RULE (binding)
ALL phases first, completely; NO mid-plan gates; then **e2e ONCE** (the hermetic matrix + the affordance's four outcomes + the standing flows) → **Reviewer ONCE** → Adviser push confirmation → bookkeeping push + CI watch. STOP rule: any diagnosis that requires a live mutation (device actions, release changes) → STOP, report, Adviser re-scopes.

## Push guidance
- Version bump: patch `1.3.1+1` (preliminary — final at push confirmation). Commits: engine fix / affordance+host / docs+plans — atomic, explicit staging, never root-wide `git add`, `.opencode/` excluded.

## Reviewer web searches (per the web-research skill, read from `.opencode/skills/web-research/SKILL.md`)
1. GitHub REST unauthenticated rate limits (60 req/h/IP) + documented reachability/throttling behavior of `api.github.com` (regional/network blockers).
2. Android in-app update best practice for NON-Play (sideloaded) distribution — why the Play In-App Updates API does not apply here and what the proper pattern is (periodic silent check + manual affordance + link-out).
3. Semantic-version comparison practice (strict core; build metadata excluded) — verify `semver.dart` against it.

## Governance
| Date | Event |
|---|---|
| 2026-10-16 | Plan created `queued` (premise: the feature exists and is correctly wired → audit-only). |
| 2026-10-16 | **RE-SCOPED to diagnosis + fix** (user defect: no dialog on CI-signed 1.2.4 despite v1.2.5 latest; premise invalidated). Reproduction + 6-suspect investigation list + affordance ruling + hermetic-primary/live-diagnostic verification recorded. P1 (diagnosis, CHEAP, middle-end) is the first delegation. |
