# Cycle 17 — flutter_launcher_icons 0.14.4 (F11 part 3c-4) — Dev-Tool Bump, Map-First

**status:** active
**created:** 2026-10-14
**created by:** Adviser (self-improvement cycle 17 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 3d41302
**predecessors:** plans/done/cycle-1..16 (all closed, CI green; latest runs 38510803047 / 38511755124)

## Cycle 17 ground truth (fresh evidence, 2026-10-14)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 16th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| `pub outdated` queue | flutter_launcher_icons 0.14.4 (+ gated ^11 fss 11.2.0); cupertino_icons + dotenv RESOLVED in cycles 15-16 |
| **flutter_launcher_icons evidence** | dev-dependency `^0.13.1` (pubspec:63) + config block (pubspec:72-76: `android: "launcher_icon"`, `ios: true`, `image_path: assets/images/logo.png`, `min_sdk_android: 21`). **CI uses it 0 times** (no workflow step) — it is a developer-invoked one-shot generator. **31 icon assets pre-generated and committed** (android mipmaps + iOS AppIconSet). Active dev utility, NOT dead weight → **map-first bump, not removal**. |
| B2 | Desktop-identity — **PARKED pending user direction** (ruling below; stop re-surfacing as an open decision each cycle). |
| F18 | Ubuntu 26 runner migration due ~Oct 19 (5 days out) — today's runs show the notice only; watch the first post-Oct-19 run for runner-side behavior change. |
| CI | runs 38510803047 / 38511755124 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F11 part 3c-4** | **flutter_launcher_icons 0.13.1 → 0.14.4.** Dev-invoked one-shot generator (CI: 0 uses; 31 committed icon assets). Dev-tool bump: runtime/CI behavior cannot change; the only surface is config compatibility with 0.14 (`min_sdk_android` / `android:` output-name semantics — verify with citations). **SELECTED as the cycle-17 task.** | maintainability | pubspec:63,72-76; CI grep 0; 31 committed assets | middle-end | CHEAP |
| **B2** | Desktop template branding — **PARKED pending user direction** (this ruling): actionable only if/when the user ships desktop builds; until then the template strings are inert. Trigger recorded; stop re-surfacing as an open decision. | branding | cycle-14 review; linux/windows/macos sweep | — | CHEAP (when triggered) |
| **F11 part 4** | ^11 fss `checkUpgradeStatus()` follow-up — **GATED on the user cutting the next release tag**. | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **F18** | Gradle/AGP below Flutter warn thresholds + **Ubuntu 26 runner migration ~Oct 19** — after that date, check the first Build APK run for runner-side changes (toolchain preinstalls, notice changes). Still a deliberate deferral for the AGP 9 migration itself. | CI / toolchain | CI annotations; DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F6-residue** | `hashPassword` outside `tryUpgrade`'s try (login.dart:365,459) — theoretical only. | security (nit) | cycle-10 review | middle-end | CHEAP |
| **F13** | Connectivity probe fresh HttpClient per call — LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15 residue / F16 / F19** | Guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (17 cycles).** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

**Strategic note (honest):** launcher_icons is the LAST small major. After this cycle the actionable queue is EXPENSIVE-only (F18 AGP-9 toolchain migration, F13) plus user-gated items (^11 fss) and cloud-blocked items (F4/F5/F12). The loop continues per the standing directive, but the next audits should surface the user-gated/blockied frontier prominently — the user's decisions (release tag, Supabase access, desktop identity) now gate most remaining value.

---

## Selected task (single): F11 part 3c-4 — flutter_launcher_icons 0.14.4

**Objective:** the dev dependency at ^0.14.4 with the pubspec config block valid per 0.14's documented options (adapted mechanically if needed); zero runtime/CI surface change; gates + CI green.

**Version bump decision: none** — dev-tool maintenance is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — since every phase below is **CHEAP-class, no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch.

**STOP RULE (binding, cycles 7/9/10/12/13/15/16 precedent):** P1 extracts 0.14's breaking changes from the official changelog and maps the config block. **If any config option is removed/renamed without a documented equivalent, or the 0.14 semantics break the committed-icons workflow (e.g., output paths change such that a future regeneration would clobber different files) → STOP** and record; the Adviser re-scopes (deferral is acceptable — the tool is one-shot and currently working).

---

## Phase 1 — Config-compatibility map (read-only evidence pass)

- **Phase id:** P1
- **Objective:** the 4 config options mapped against 0.14's documented schema with citations — or an honest STOP.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only)
- **Implementation steps:**
  1. Extract the official 0.13→0.14 breaking-change list with verbatim changelog citations (pub.dev/packages/flutter_launcher_icons CHANGELOG; candidate areas per the pre-cycle brief: `min_sdk_android` option fate, `android:` output-name semantics, iOS handling, any renamed keys — HYPOTHESES to verify).
  2. Map the 4 config options (android/ios/image_path/min_sdk_android) against 0.14's schema: unchanged / mechanically-updated / removed-without-equivalent.
  3. Confirm the one-shot invocation contract: the committed 31 assets were generated by 0.13; a future regeneration under 0.14 must write the SAME paths (or the map must document the delta) — this is the only real-world risk.
  4. Confirm dev-only blast radius: no CI step, no runtime import (grep — expected 0), no test references.
  5. **STOP decision:** any removed-without-equivalent option or regeneration-path delta → STOP; record everything (deferral is a sound outcome for a working one-shot tool).
- **Acceptance criteria:** all 4 options mapped with citations; the regeneration-path delta stated; or STOP with the specific gap.
- **Verification:** **CHEAP** — read-only; no e2e impact.
- **Dependencies / sequencing:** first; P2 executes only a clean map.
- **Expected result:** P2 fully determined, or an honest deferral of the bump.

## Phase 2 — Apply the bump

- **Phase id:** P2
- **Objective:** flutter_launcher_icons ^0.14.4 live; config block valid per the map; nothing else changes.
- **Responsible subagent:** middle-end
- **Files to change:** `pubspec.yaml` (dev-dep line; config block only if the map requires mechanical adaptation), `pubspec.lock`
- **Implementation steps:**
  1. Apply the map mechanically: constraint bump; config-block updates strictly per the map (each authorized by a cited changelog line).
  2. Do NOT regenerate icons in this cycle (the committed assets are current; regeneration is the developer's one-shot action when the logo changes — the map documents that 0.14 writes the same paths).
  3. Local validation: `flutter analyze` exit 0 (flutter_lints 6), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` → 222/222.
  4. **STOP-and-revert on any non-mechanical gap** (fallback rule).
- **Acceptance criteria:** dev-dep = the designed line only; config diffs = the map site-by-site (or zero); gates green; committed icon assets byte-identical.
- **Verification:** **CHEAP** — dev-tool constraint; zero runtime/CI surface. The definitive acceptance is the post-push CI watch.
- **Dependencies / sequencing:** after P1's clean map (STOP forbids P2). P2 is the only application phase.
- **Expected result:** the last small major cleared; the small-majors queue is EMPTY (remaining: launcher regeneration is a developer action; the gated/blocked/EXPENSIVE items are the whole rest of the backlog).

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `build(deps): adopt flutter_launcher_icons 0.14.4 (map-driven dev-tool bump)` — pubspec.yaml, pubspec.lock. Atomic.
- Commit 2: `docs(plans): close cycle 16 and open cycle 17 plan` — stage `plans/` explicitly (deletion of old cycle-16 path, `plans/done/cycle-16-...md`, new cycle-17 file). Never root-wide `git add -A`/`git add .`
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); committed icon assets byte-identical (this cycle does NOT regenerate); no other pubspec constraints.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — identical profile to run 38510803047 (the tool is not in the CI path; the run proves nothing else broke). Watch for the **Ubuntu 26 runner migration (~Oct 19)**: if the runner migrated, compare the run's toolchain notices — record any behavioral delta under F18 (do not fix; observe and record).
- **Promote to Landing** green as usual.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase (scoped revert to ^0.13.1 — trivially safe, dev-tool only).
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-18 audit (pre-ranked: F18 AGP-9 toolchain migration or F13 — the EXPENSIVE-only frontier; surface the user-gated/blockied items prominently).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `flutter_launcher_icons 0.14.0 changelog breaking changes` (pub.dev — the official 0.13→0.14 delta, verbatim).
2. `flutter_launcher_icons min_sdk_android android output name 0.14` (pub.dev README/schema — the two config options whose fate matters).
3. `flutter_launcher_icons 0.14 dart sdk minimum` (pub.dev — compatibility with Dart 3.13.5 / Flutter 3.47.6).

## Reviewer verification commands (single pass, after P1+P2)

1. `git diff pubspec.yaml` → the dev-dep line (+ config lines only per the map); `pubspec.lock` → flutter_launcher_icons 0.14.x.
2. Regeneration-path audit: the committed icon assets byte-identical (`git diff android/app/src/main/res ios/Runner/Assets.xcassets` → empty); the map documents 0.14's output paths vs the committed tree.
3. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` 222/222, `dart format --output=none --set-exit-if-changed lib test` exit 0; `flutter pub get --enforce-lockfile` idempotent.
4. Scope: no other constraints; analysis_options.yaml absent; .opencode/ absent; no CI workflow changes.
5. STOP-echo audit: the bump cites the P1 map's citations; any deferral is recorded with the evidence.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-14 | Cycle-17 audit recorded; plan created `active` (task F11 part 3c-4 — the LAST small major). **B2 PARKED** pending user direction (trigger: desktop builds). F18 extended (Ubuntu 26 runner migration ~Oct 19 — watch item). Strategic note recorded: post-cycle-17 the actionable queue is EXPENSIVE-only + user-gated/blockied. |
| 2026-10-14 | **P1 MAP COMPLETE (no STOP; one nuance adjudicated) + ADVISER RULING: LAUNCHER_ICONS = PROCEED.** P1's map: **zero breaking changes 0.13.1→0.14.4** (no "breaking" entry anywhere; no option removed/renamed); all 4 config options UNCHANGED (`android: "launcher_icon"` same custom-file branch + mipmap paths; `ios: true` same 21 AppIcon PNGs + pbxproj; `image_path` same fallback; `min_sdk_android: 21` parsed-but-inert in BOTH versions — zero call sites); blast radius confirmed zero (no CI usage, no lib/test refs, transitives in range). **THE ADJUDICATED NUANCE — regeneration-path delta:** 0.14.4's regeneration would rewrite `AppIcon.appiconset/Contents.json` (SAME path) to the 25-entry manifest — all 19 committed mappings preserved + 6 ADDITIVE entries (50/57/72 @1x/@2x) referencing already-committed PNGs; non-breaking, valid Xcode manifest, surfaces ONLY on voluntary regeneration (this cycle does NOT regenerate). **RULING: PROCEED** — the STOP rule's intent ("regeneration would clobber different files") targets destructive-or-surprising paths; this delta is same-path/additive/preserving, documented here so any future regeneration is informed not surprised, and deferral would leave the last small major dangling over a benign-by-inspection delta. **P2 SCOPE CONFIRMED:** pubspec dev-dep line + lock ONLY (2-file diff); config block byte-identical; NO regeneration; committed icon assets byte-identical; gates green. **Reviewer armed:** verify committed icon dirs byte-identical (git diff android res + iOS Assets.xcassets → empty); verify the Contents.json delta is recorded in this row + the P1 report; verify zero config changes; confirm the bump cites P1's citations. |
| 2026-10-14 | **P2 IMPLEMENTED (exactly per the confirmed scope), SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser independently verified: diff scope = exactly pubspec.yaml (single dev-dep hunk `^0.13.1`→`^0.14.4`, config block zero-diff) + pubspec.lock (flutter_launcher_icons 0.14.4); **committed icon assets byte-identical** (android res + iOS Assets.xcassets diffs empty — no regeneration); gates re-run — analyze exit 0 (flutter_lints 6), format 0 changed, 222/222. Reviewer arming notes all held (icon dirs empty-diff; Contents.json delta documented in the governance row — 19+6=25 corroborated against the tree; zero config changes; citations cited). **README nit ruling:** backlog for a future docs-sweep commit — the README how-to carries **2 stale lines**, not 1: :44 (`flutter_launcher_icons: ^0.13.1` example) and :62 (legacy `flutter pub run flutter_launcher_icons:main` invocation). Out-of-phase scope here; pre-ranked into the next docs-touching cycle. Commits: `build(deps): adopt flutter_launcher_icons 0.14.4 (map-driven dev-tool bump)` / `docs(plans): close cycle 16 and open cycle 17 plan`. Version bump: none; next tag carries 1.2.4 and unlocks the ^11 fss follow-up. |
| pending | agent-push: push main (2 commits), watch BOTH workflows → **Build APK green — identical profile expected** (the tool is not in the CI path); **watch for the Ubuntu 26 runner migration (~Oct 19)**: if the runner migrated, record any toolchain-notice/behavior delta under F18 (observe and record only — no fixes), Promote to Landing green as usual. On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-18 audit — **the EXPENSIVE-only frontier** (F18 AGP-9 toolchain migration or F13; surface the user-gated/blocked items prominently: F4/F5/F12 cloud-blocked 18 cycles, ^11 fss gated on the release tag, B2 parked). On red: capture `gh run view --log-failed`, plan stays `active`, fix phase = scoped revert to ^0.13.1 (trivially safe, dev-tool only). |

- Cycle-18 pre-ranked: **F18 AGP-9 toolchain migration** or **F13** — the EXPENSIVE-only frontier; **surface the user-gated/blockied frontier prominently** (^11 fss needs a release tag; F4/F5/F12 need Supabase access; B2 parked). The user's decisions now gate most remaining value.
- This plan is `done` only when P1+P2 PASS the single review, the push is Adviser-approved and executed, and BOTH workflows are green.
