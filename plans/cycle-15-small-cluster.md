# Cycle 15 — Small Cluster: flutter_dotenv 6 + B3 + B1 (F11 part 3c-2 + rebrand residue)

**status:** active
**created:** 2026-10-14
**created by:** Adviser (self-improvement cycle 15 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 3d6b55e
**predecessors:** plans/done/cycle-1..14 (all closed, CI green; latest runs 38448764269 / 38450890988)

## Cycle 15 ground truth (fresh evidence, 2026-10-14)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 14th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| `pub outdated` queue | cupertino_icons 2.0.0, flutter_dotenv 6.0.1, flutter_launcher_icons 0.14.4 (+ gated ^11 fss 11.2.0) |
| **dotenv surface** | **exactly 1 file**: `lib\core\config\app_config.dart` — import :2, `dotenv.env[key] ?? ''` :11, `await dotenv.load(fileName: '.env')` :31 (wrapped in try/catch — missing .env is expected in release; dart-define is the source of truth). Test surface: none (no test references dotenv). |
| **B1 (cycle-14 ruling)** | `chat_error_classifier.dart:5-6` — "Brand copy is frozen — do not reword." now **false** post-F23 (the brand copy WAS normalized). Comment-only fix. |
| **B3 (cycle-14 ruling)** | `web/manifest.json:7` — `"description": "A new Flutter project."` placeholder → the AgentA copy (matching cycle 14's index.html meta description). One-liner. |
| CI | runs 38448764269 / 38450890988 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F11 part 3c-2** | **flutter_dotenv 5.2.1 → 6.0.1.** Single-consumer surface (AppConfig: load + env access). Boot-time config-loading behavior → map-first with citations. **SELECTED (cluster P1+P2).** | maintainability | 1-file surface above | middle-end | **EXPENSIVE** (boot behavior) |
| **F23-residue B3** | **web/manifest.json description placeholder** — one-liner to the AgentA copy. **SELECTED (cluster P3).** | branding | manifest.json:7 | middle-end | CHEAP |
| **F23-residue B1** | **Stale "Brand copy is frozen" comment** (classifier :5-6) — false post-F23; fix the comment (and only the comment). **SELECTED (cluster P3).** | branding / docs | classifier :5-6 | middle-end | CHEAP |
| **F11 part 3c-3** | cupertino_icons 2.0.0 — icon-font major; separate cycle. | maintainability | pub outdated | middle-end | EXPENSIVE |
| **F11 part 3c-4** | flutter_launcher_icons 0.14.4 — build tool; separate cycle. | maintainability | pub outdated | middle-end | EXPENSIVE |
| **F11 part 4** | ^11 fss `checkUpgradeStatus()` follow-up — **GATED on the user cutting the next release tag**. | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **B2** | Desktop template branding ("aiproject" strings in linux/windows/macos runners) — separate desktop-identity decision (user input advisable). | branding | cycle-14 review | — | CHEAP (when decided) |
| **F6-residue** | `hashPassword` outside `tryUpgrade`'s try (login.dart:365,459) — theoretical only. | security (nit) | cycle-10 review | middle-end | CHEAP |
| **F18** | Gradle/AGP below Flutter warn thresholds; **the ubuntu-latest→Ubuntu 26 migration notice now appears in CI runs** (informational, runner-side — track in the same future toolchain cycle). | CI / toolchain | CI annotations | backend | EXPENSIVE |
| **F13** | Connectivity probe fresh HttpClient per call — LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15 residue / F16 / F19** | Guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (15 cycles).** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: the majors queue proceeds; dotenv 6 has the smallest surface of the remaining majors (1 consumer, 3 call sites) and pairs naturally with the two one-liner rebrand residues as a small cluster (cluster precedent: cycles 5/8). Honest classification: dotenv touches boot-time config loading → EXPENSIVE → e2e required; the one-liners are CHEAP.

---

## Selected task (single): F11 part 3c-2 + B3 + B1 — small cluster

**Objective:** flutter_dotenv ^6.0.1 live with the AppConfig consumer adapted mechanically per the map (or constraint-only if the map says zero changes); the web manifest description and the classifier comment state true facts; all gates + e2e + CI green.

**Version bump decision: none** — dependency migration + copy/comment fixes are not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **P2 is EXPENSIVE (boot-time config-loading behavior), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch.

**STOP RULE (binding, cycles 7/9/10/12/13 precedent):** if P1 cannot map the dotenv 5→6 migration mechanically from the official changelog ALONE — a breaking change without a documented equivalent for AppConfig's 3 call sites — P1 ends in STOP: no constraint edit in P2, evidence recorded, the Adviser re-scopes (deferral with evidence; P3's one-liners can still proceed independently). **[STATUS: TRIGGERED 2026-10-14 — C1 conditional TRUE (asset-bundle-only load), AND the deeper finding: 5.2.1 has the byte-identical asset-only implementation, so the .env fallback was always inert. RESOLVED by re-scope: DOTENV = OPTION B (removal) — see P2 below.]**

---

## Phase 1 — dotenv 6 migration map (read-only evidence pass)

- **Phase id:** P1
- **Objective:** a complete old→new map for the 3 AppConfig call sites — or an honest STOP.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only)
- **Implementation steps:**
  1. Extract the official 5→6 breaking-change list with verbatim changelog citations (pub.dev/packages/flutter_dotenv CHANGELOG; candidate areas: `load()` semantics/signature, `env[]` access behavior, null-handling, asset declaration requirements — HYPOTHESES to verify).
  2. Map the 3 call sites: import (:2), `dotenv.env[key] ?? ''` (:11), `dotenv.load(fileName: '.env')` (:31) — unchanged / mechanically-updated / non-mechanical, each authorized by a cited changelog line.
  3. Confirm asset declaration status: pubspec has NO `.env` asset (C1 — CI asserts it); dotenv 6 must not require asset bundling for the local-dev fallback to work (if it does → conflict with C1 → STOP).
  4. **STOP decision:** any undocumented/unmappable break → STOP; record everything.
- **Acceptance criteria:** all 3 sites mapped with citations; or STOP with the specific gap.
- **Verification:** **CHEAP** — read-only; no e2e impact.
- **Dependencies / sequencing:** first; P2 executes only a clean map. P3 is independent.
- **Expected result:** P2 fully determined, or an honest deferral of dotenv alone.

## Phase 2 — Remove flutter_dotenv + the inert .env fallback (re-scoped per Adviser ruling)

- **Phase id:** P2 (re-scoped from "apply dotenv 6" — the STOP finding made the dependency dead weight under C1)
- **Objective:** zero dotenv references repo-wide; the boot path reflects the actual config source (dart-define only); docs state the truth.
- **Responsible subagent:** middle-end
- **Files to change:** `pubspec.yaml` (remove the flutter_dotenv line), `pubspec.lock` (regenerated), `lib/core/config/app_config.dart` (remove import :2, the dotenv branch in `_withFallback` :8-15 — keeping only the dart-define value with its existing trim, remove `init()` :28-34 entirely, refresh the C1 comments), `lib/main.dart` (:95-111 — remove the `await AppConfig.init()` call **and its try/catch wrapper**, which only guarded dotenv.load; `AuthService.resetGoogleInit()` at :89 stays; boot proceeds directly to the Supabase block), `docs/backend-rls.md` (§C1: the ".env as a local-dev fallback" claim is false — dart-define-only truth), `.env.example` (header comment: the copy-to-.env instruction no longer applies — keep the file as the dart-define key reference with corrected comments)
- **Implementation steps:**
  1. Verify zero callers at edit time: grep `AppConfig.init|dotenv` — expected: main.dart:96 (the sole init caller) + the app_config.dart sites; if any other caller or test reference exists → STOP-and-report.
  2. Remove per the file list above. `_withFallback(defined, key)` collapses to returning the trimmed dart-define value (keep the `.trim()` semantics byte-identical). The getters' public contract is unchanged.
  3. Preserve boot semantics: `AuthService.resetGoogleInit()` ordering stays; the Supabase init block follows immediately (the removed try/catch only ever guarded a throw that was swallowed anyway — the error-UI branch was unreachable and its removal is behavior-preserving by the P1 evidence).
  4. Docs: backend-rls.md §C1 and .env.example comments state the dart-define-only truth (C1 posture UNCHANGED — no `.env` asset, CI guard still passes).
  5. Local validation: `flutter analyze` exit 0 (flutter_lints 6), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` → 222/222.
  6. Repo-wide grep proof: `dotenv|flutter_dotenv` → zero in lib/ + pubspec.yaml + lock (the `.env.example` FILE remains as the key-reference doc; `.gitignore`'s .env entries stay — harmless and correct).
  7. **STOP-and-report on any unexpected caller or reference** (fallback rule).
- **Acceptance criteria:** zero dotenv references in lib/ + pubspec.yaml + lock; boot path = dart-define-only with the documented unreachable-branch removal; docs truthful; gates green; internal identifiers untouched.
- **Verification:** **EXPENSIVE** — boot-path change. Covered by the once-per-plan **e2e-tester run**: analyze ×2 exit 0, 222/222, format 0, `pub get --enforce-lockfile` idempotent, zero-dotenv greps, boot-path diff audit (main.dart/AppConfig) against this phase's map.
- **Dependencies / sequencing:** resolves the P1 STOP (this re-scope is its outcome). Independent of P3.
- **Expected result:** a dependency that provided zero function is gone; the config story is one honest sentence: dart-define is the only source.
- **Recorded idea (NOT asserted, NOT scheduled):** a future local-dev mechanism could use `--dart-define-from-file` (version support unverified) — backlog idea only.

## Phase 3 — Rebrand residue one-liners (B3 + B1)

- **Phase id:** P3
- **Objective:** the web manifest and the classifier comment state true facts.
- **Responsible subagent:** middle-end
- **Files to change:** `web/manifest.json` (:7), `lib/core/utils/chat_error_classifier.dart` (:5-6 comment only)
- **Implementation steps:**
  1. B3: `"description": "A new Flutter project."` → `"description": "AgentA — your offline-first AI assistant."` (matching cycle 14's index.html meta description).
  2. B1: replace the stale comment with the true statement, e.g. `/// Brand copy normalized to "AgentA" in F23 — display-only strings; update test/chat_error_classifier_test.dart assertions whenever rewording.` (Comment-only; the class and all strings byte-identical.)
  3. Local validation: `flutter analyze` exit 0; `flutter test` → 222/222 (the classifier tests must be untouched by a comment edit).
- **Acceptance criteria:** 2 value/comment lines changed, nothing else; gates green.
- **Verification:** **CHEAP** — one value line + one comment block.
- **Dependencies / sequencing:** independent of P1/P2; batched.
- **Expected result:** zero rebrand residue remains (B1/B3 closed; B2 remains a separate user decision).

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `refactor(config): remove inert flutter_dotenv fallback — dart-define is the only config source` — pubspec.yaml, pubspec.lock, app_config.dart, main.dart, docs/backend-rls.md, .env.example. Atomic (removal + its boot-path consequence never split).
- Commit 2: `docs(branding): manifest description + classifier comment truth refresh (B3/B1)` — web/manifest.json + chat_error_classifier.dart.
- Commit 3: `docs(plans): close cycle 14 and open cycle 15 plan` — stage `plans/` explicitly (deletion of old cycle-14 path, `plans/done/cycle-14-...md`, new cycle-15 file). Never root-wide `git add -A`/`git add .`
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); no other pubspec constraints (cupertino_icons/launcher_icons stay queued).
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — the runner **boots dart-define-only** (dotenv gone; the C1 no-.env-bundle guard still passes) with all guards + format gate + strict-lint analyze + 222/222 + APK build. **Failure class to name if red:** Dart compile errors at the AppConfig/main.dart boot path — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase = scoped restore of the dotenv constraint + init() (P1's evidence documents the exact prior state).
- **Promote to Landing** green as usual.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-16 audit (pre-ranked: F11 part 3c-3 — cupertino_icons 2; the 2 accepted dotenv-docs nits; B2 desktop-identity decision surfaced for user input).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `flutter_dotenv 6.0.0 changelog breaking changes` (pub.dev — the official 5→6 delta, verbatim).
2. `flutter_dotenv load fileName asset declaration requirement` (pub.dev README — whether 6.x requires asset bundling; C1 conflict check).
3. `flutter_dotenv 6 dart sdk minimum` (pub.dev — compatibility with Dart 3.13.5 / Flutter 3.47.6).

## Reviewer verification commands (single pass, after P1-P3)

1. Removal audit: `git diff pubspec.yaml` → the flutter_dotenv line REMOVED (no other constraint changes); `pubspec.lock` → flutter_dotenv absent; grep `dotenv|flutter_dotenv` in lib/ + pubspec.yaml + pubspec.lock → zero matches (`.env.example` file content = updated comments only).
2. Boot-path audit: `git diff lib/core/config/app_config.dart lib/main.dart` → matches the P2 map exactly (init() + its try/catch gone; `_withFallback` collapsed to trimmed dart-define; `AuthService.resetGoogleInit()` ordering preserved; Supabase block follows); the C1 asset-declaration state unchanged (pubspec has no `.env` asset — CI guard still passes).
3. Docs audit: backend-rls.md §C1 states dart-define-only; .env.example comments corrected (key-reference role).
4. B3/B1 audit: manifest description = the new copy; classifier diff = comment lines only (class + strings byte-identical); classifier tests untouched.
5. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` 222/222, `dart format --output=none --set-exit-if-changed lib test` exit 0; `flutter pub get --enforce-lockfile` idempotent.
6. Scope: no other constraints; analysis_options.yaml absent; .opencode/ absent.
7. STOP-echo audit: the removal cites the P1 STOP finding (both-tags source verification) as its authorization — not silent scope creep.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-14 | Cycle-15 audit recorded; plan created `active` (cluster: dotenv 6 + B3 + B1). B2 desktop-identity surfaced as a user-decision item. F18 evidence extended (Ubuntu 26 runner notice). |
| 2026-10-14 | **P1 STOP INVOKED + ADVISER RE-SCOPE RULING.** P1's map was mechanically complete (zero code adaptations for 6.0.1) but the C1 conditional fired: dotenv's `load()` is asset-bundle-only — and the CRITICAL NEW FACT: **dotenv 5.2.1 has the byte-identical asset-only implementation** (source-verified at both tags). Under C1, `dotenv.load()` has ALWAYS thrown FileNotFoundError (swallowed) and `dotenv.env[key]` has ALWAYS thrown NotInitializedError (swallowed) — **the ".env local-dev fallback" has always been inert dead code; dart-define is the only functioning config source; 5.2.1 vs 6.0.1 behavior for this app is byte-for-byte identical.** **RULING: DOTENV = OPTION B, SUB-OPTION REMOVAL** — the loop's goal is a clean codebase; a dependency providing zero function is dead weight (F8 precedent); keeping 5.2.1 (C) ignores the finding; building a NEW dev-fallback mechanism (B2) is unrequested feature work. P2 is re-scoped from "apply dotenv 6" to **"remove flutter_dotenv + the inert fallback"** (boot path touched → EXPENSIVE, e2e required as already mandated). **P3 proceeds independently and now.** Sequencing: P3 → P2-removal → e2e → single review → push confirmation. Reviewer arming: evaluate the removal as a documented dead-code finding (source-verified at both tags; swallowed-error history), NOT scope creep; verify zero remaining dotenv references repo-wide; verify the boot-path change preserves actual semantics (dart-define-only config was the pre-existing reality). |
| 2026-10-14 | **P2 REMOVAL + P3 ONE-LINERS IMPLEMENTED, REQUIRED E2E PASS, SINGLE-PASS REVIEW PASS (removal re-proven from pub-cache 5.2.1 source + 6.0.1 docs), PUSH APPROVED by Adviser.** Adviser independently verified: scope = exactly the 8 files (6 P2 + 2 P3); **zero dotenv references in lib+test and pubspec.yaml+lock**; boot path exactly as mapped (`_withFallback(String defined) => defined.trim()` collapsed; `AppConfig.init` + its unreachable-branch try/catch gone; `resetGoogleInit` ordering preserved, Supabase block adjacent); docs truthful (backend-rls.md §C1, .env.example); gates re-run — analyze exit 0, format 0 changed, 222/222. Reviewer: removal re-proven from the 5.2.1 pub-cache source (rootBundle-only load; FileNotFoundError; NotInitializedError) + 6.0.1 docs (3 searches cited; load/asset semantics load-bearing); STOP-echo audit documented (not scope creep). Accepted deviations/nits: 2 stale ".env" message strings → dart-define wording (display-only, tests grep-zero, docs-truthful — Reviewer ACCEPT); residual refs google-signin-setup.md:127 + app_config.dart:168 → **RULING: pre-rank into cycle 16** (docs sweep alongside cupertino_icons 2 / B2). **Plan CI-watch wording amended per implementer note** (pre-re-scope dotenv-6 wording replaced by the dart-define-only watch). Commits: `refactor(config): remove inert flutter_dotenv fallback — dart-define is the only config source` / `docs(branding): manifest description + classifier comment truth refresh (B3/B1)` / `docs(plans): close cycle 14 and open cycle 15 plan`. Version bump: none; next tag carries 1.2.4 and unlocks the ^11 fss follow-up. |
| pending | agent-push: push main (3 commits), watch BOTH workflows → **Build APK green booting dart-define-only** (the C1 no-.env-bundle guard still passes; failure class if red = Dart compile errors at the AppConfig/main.dart boot path → fix phase = scoped restore of the dotenv constraint + init(), with P1's evidence documenting the exact prior state), Promote to Landing green as usual. On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-16 audit (pre-ranked: cupertino_icons 2 + the 2 accepted docs nits + B2 desktop-identity decision for user input). On red: capture `gh run view --log-failed`, plan stays `active`, fix phase planned. |

- Cycle-16 pre-ranked: **F11 part 3c-3** (cupertino_icons 2 — icon-font major; map-first). **B2 desktop-identity** surfaced for user input; the ^11 fss follow-up remains gated on the user's next release tag; **F4/F5/F12 remain CLOUD-BLOCKED** (15 cycles) — standing user escalation.
- This plan is `done` only when P1-P3 PASS review (after the e2e run; or the dotenv STOP-deferral is recorded and the plan closes via Adviser re-scope), the push is Adviser-approved and executed, and BOTH workflows are green.
