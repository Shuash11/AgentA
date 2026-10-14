# Cycle 16 — Small Cluster: cupertino_icons Disposition + 2 Docs Nits (F11 part 3c-3 + F23-residue)

**status:** done (closed 2026-10-14 — P1+P2 PASS, push executed, both workflows green; second zero-use dependency removed)
**created:** 2026-10-14
**created by:** Adviser (self-improvement cycle 16 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ b919706
**predecessors:** plans/done/cycle-1..15 (all closed, CI green; latest runs 38479855236 / 38481249508)

## Cycle 16 ground truth (fresh evidence, 2026-10-14)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 15th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| `pub outdated` queue | cupertino_icons 2.0.0, flutter_launcher_icons 0.14.4 (+ gated ^11 fss 11.2.0); flutter_dotenv RESOLVED (removed, cycle 15) |
| **cupertino_icons surface** | **ZERO usage in lib/ + test/** (grep `CupertinoIcons|cupertino_icons`: 0 matches). Default-template asset-only icon-font package. Primary source (pub.dev changelog, Adviser-fetched): 2.0.0 = SDK floor Flutter 3.44/Dart 3.12 (satisfied) + `cupertino_ui` migration — an asset/font change with **no repo consumer**. Disposition candidate: REMOVE (dotenv/F8 precedent), not bump. |
| **Nit-1 (cycle-14/15 ruling)** | `docs/google-signin-setup.md` troubleshooting table (~:127): "Check CI secret and `.env`" — `.env` is no longer a config path post-cycle-15 (dart-define only). Copy-only fix. |
| **Nit-2 (cycle-14/15 ruling)** | `lib/core/config/app_config.dart:168` — "/// Called when env file changes or on logout to allow re-init." — "env file changes" is false post-cycle-15. Comment-only fix. |
| B2 | Desktop template branding — stays a USER DECISION (not scheduled; Android-first app). |
| CI | runs 38479855236 / 38481249508 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F11 part 3c-3** | **cupertino_icons — ZERO-USE dependency.** Not a 2.0.0 bump candidate: the package provides zero function (0 API/font references). Disposition = REMOVE (dotenv/F8 precedent): pubspec line + lock block; APK shrinks by the icon font. **SELECTED (cluster P1+P2).** | maintainability | 0-usage grep; pub.dev changelog (asset-only package) | middle-end | CHEAP |
| **F23-residue Nit-1** | **google-signin-setup.md troubleshooting row cites `.env`** — stale post-cycle-15. **SELECTED (cluster P2).** | docs | docs/google-signin-setup.md ~:127 | middle-end | CHEAP |
| **F23-residue Nit-2** | **app_config.dart:168 "env file changes" comment** — stale post-cycle-15. **SELECTED (cluster P2).** | docs | app_config.dart:168 | middle-end | CHEAP |
| **F11 part 3c-4** | flutter_launcher_icons 0.14.4 — build tool; separate cycle (needs its own map: icon config compatibility). | maintainability | pub outdated | middle-end | EXPENSIVE |
| **F11 part 4** | ^11 fss `checkUpgradeStatus()` follow-up — **GATED on the user cutting the next release tag**. | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **B2** | Desktop template branding ("aiproject" strings + com.example.aiproject ids in linux/windows/macos) — **USER DECISION** (surfaced cycles 14-16; Android-first app — the user should rule whether desktop identity matters at all). | branding | cycle-14 review | — | CHEAP (when decided) |
| **F6-residue** | `hashPassword` outside `tryUpgrade`'s try (login.dart:365,459) — theoretical only. | security (nit) | cycle-10 review | middle-end | CHEAP |
| **F18** | Gradle/AGP below Flutter warn thresholds; **Ubuntu 26 runner migration notice** (migration date ~Oct 19 per notices — the runner may migrate under us; informational, runner-side; re-check CI behavior after the date). | CI / toolchain | CI annotations | backend | EXPENSIVE |
| **F13** | Connectivity probe fresh HttpClient per call — LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15 residue / F16 / F19** | Guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (16 cycles).** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: the majors queue continues smallest-first; cupertino_icons is the smallest of all (zero-use removal, dotenv precedent) and pairs with the two one-line doc truths as a small cluster (cycles 5/8/15 precedent). All CHEAP → no e2e.

---

## Selected task (single): F11 part 3c-3 + Nit-1 + Nit-2 — small cluster

**Objective:** cupertino_icons disposed per evidence (expected: removed as a zero-use dependency); both doc surfaces state true facts; all gates + CI green.

**Version bump decision: none** — dependency removal + doc fixes are not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — since every phase below is **CHEAP-class, no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch.

**STOP RULE (binding, cycles 7/9/10/12/13/15 precedent):** P1 verifies the zero-use evidence at every level (API grep, font-family references like `fontFamily: 'CupertinoIcons'`, dynamic usage, template requirements — `cupertino_icons` is an OPTIONAL default-template asset, not a framework requirement). **If ANY usage surfaces → STOP**: re-scope to the 2.0.0 bump per its changelog instead of removal. Evidence first, always.

---

## Phase 1 — cupertino_icons disposition map (read-only evidence pass)

- **Phase id:** P1
- **Objective:** proof that the package is fully unused (or the discovery of usage → STOP/re-scope to a bump).
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only)
- **Implementation steps:**
  1. API surface: grep lib/ + test/ for `CupertinoIcons|cupertino_icons` (expected: 0 — already measured; re-verify).
  2. Font-level surface: grep for `fontFamily: 'CupertinoIcons'` and any dynamic font usage (expected: 0).
  3. Framework requirement check: confirm `cupertino_icons` is an optional default-template asset (pub.dev README — Adviser-fetched: "Default icons asset for Cupertino widgets"; the framework does not require it for Material apps; `uses-material-design: true` governs MaterialIcons separately).
  4. Primary-source citation: pub.dev/packages/cupertino_icons/changelog — 2.0.0 = SDK floor + `cupertino_ui` migration (relevant only if any consumer existed).
  5. **Disposition decision:** zero usage confirmed → REMOVE (record the reasoning; the dotenv/F8 precedent governs). Any usage found → STOP and re-scope to a cited 2.0.0 bump.
- **Acceptance criteria:** every level verified with the grep outputs recorded; disposition stated with the evidence chain.
- **Verification:** **CHEAP** — read-only; no e2e impact.
- **Dependencies / sequencing:** first; P2 executes only a clean disposition.
- **Expected result:** removal authorized on evidence.

## Phase 2 — Apply the disposition + the 2 doc nits

- **Phase id:** P2
- **Objective:** pubspec/lock without cupertino_icons; both doc surfaces truthful.
- **Responsible subagent:** middle-end
- **Files to change:** `pubspec.yaml` (remove the cupertino_icons line), `pubspec.lock` (regenerated), `docs/google-signin-setup.md` (Nit-1 row), `lib/core/config/app_config.dart` (Nit-2 comment)
- **Implementation steps:**
  1. Remove the `cupertino_icons: ^1.0.9` line from dependencies; `flutter pub upgrade` the touched set; verify the lock drops the cupertino_icons block entirely.
  2. Nit-1: `docs/google-signin-setup.md` troubleshooting row — "Check CI secret and `.env`" → "Check the CI secret (dart-define)." (row's other content byte-identical).
  3. Nit-2: `app_config.dart:168` — "/// Called when env file changes or on logout to allow re-init." → "/// Called on logout to allow re-init (dart-define config is compile-time; there is no env file to change)." (comment-only).
  4. Local validation: `flutter analyze` exit 0 (flutter_lints 6), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` → 222/222.
  5. Repo-wide grep proof: `cupertino_icons|CupertinoIcons` → zero in lib/ + test/ + pubspec.yaml + lock; `.env` config-path references → zero in the touched docs (other historical docs mentions are out of scope).
  6. **STOP-and-report on any surprise** (fallback rule).
- **Acceptance criteria:** cupertino_icons absent from pubspec + lock; both doc fixes landed; gates green; internal identifiers untouched.
- **Verification:** **CHEAP** — zero-use removal (no consumer exists to change behavior) + doc copy. The definitive acceptance is the post-push CI watch (the APK build proves the font's absence breaks nothing).
- **Dependencies / sequencing:** after P1's clean disposition (STOP forbids P2). P2 is the only application phase.
- **Expected result:** another zero-function dependency gone; the docs truthful; the majors queue shrinks to launcher_icons + the gated/blocked items.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `build(deps): remove zero-use cupertino_icons dependency (dead weight, dotenv precedent)` — pubspec.yaml, pubspec.lock. Atomic.
- Commit 2: `docs: dart-define-only config references (post-cycle-15 truth)` — docs/google-signin-setup.md + lib/core/config/app_config.dart.
- Commit 3: `docs(plans): close cycle 15 and open cycle 16 plan` — stage `plans/` explicitly (deletion of old cycle-15 path, `plans/done/cycle-15-...md`, new cycle-16 file). Never root-wide `git add -A`/`git add .`
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); no other pubspec constraints (launcher_icons stays queued).
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — the runner builds WITHOUT the cupertino font (proving the zero-use removal breaks nothing) with all guards + format gate + strict-lint analyze + 222/222 + APK build. **Failure class to name if red:** unexpected icon-font/asset references surfacing at compile (would contradict the zero-use evidence — investigate before touching anything) — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase = scoped restore of the dependency.
- **Promote to Landing** green as usual.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-17 audit (pre-ranked: F11 part 3c-4 — flutter_launcher_icons 0.14.4 map-first; B2 remains a user decision).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `cupertino_icons 2.0.0 changelog` (pub.dev — Adviser pre-fetched: SDK floor + `cupertino_ui` migration; the Reviewer re-verifies and checks whether any 2.0.0 item would matter IF usage existed).
2. `cupertino_icons required flutter material app default template` (flutter.dev / pub.dev README — confirms the package is an optional asset, not a framework requirement).

## Reviewer verification commands (single pass, after P1+P2)

1. Removal audit: `git diff pubspec.yaml` → the cupertino_icons line REMOVED (nothing else); `pubspec.lock` → cupertino_icons block absent; grep `cupertino_icons|CupertinoIcons` in lib/ + test/ + pubspec.yaml + lock → zero matches.
2. Doc-nit audit: `git diff docs/google-signin-setup.md lib/core/config/app_config.dart` → the 2 designed lines only (comment/copy-only; no code behavior).
3. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` 222/222, `dart format --output=none --set-exit-if-changed lib test` exit 0; `flutter pub get --enforce-lockfile` idempotent.
4. Scope: no other constraints; analysis_options.yaml absent; .opencode/ absent; AndroidManifest untouched.
5. STOP-echo audit: the removal cites the zero-use evidence chain (API grep + font-level grep + pub.dev README) — not silent scope creep.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-14 | Cycle-16 audit recorded; plan created `active` (cluster: cupertino_icons disposition + Nit-1 + Nit-2). Adviser pre-fetched the cupertino_icons changelog (primary source). B2 stays a user decision. F18 updated (Ubuntu 26 runner migration ~Oct 19 — watch CI behavior after the date). |
| 2026-10-14 | **P1 MAP COMPLETE (no STOP) + P2 APPLIED, SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser independently verified: scope = exactly 4 files (2 insertions / 12 deletions); pubspec.yaml = the dep line + collapsed blank removed, nothing else; **cupertino_icons absent from pubspec.lock**; Nit-1 row now reads "Check the CI secret (dart-define)."; Nit-2 comment states the dart-define compile-time truth; **zero case-sensitive matches** for CupertinoIcons/cupertino_icons in lib+test; gates re-run — analyze exit 0, format 0 changed, 222/222. Reviewer: removal surgical; zero-use re-corroborated at all levels (fontFamily literals Roboto/monospace; IconData hits type-annotations only; `flutter pub deps` full-graph clean); doc nits exact; both web searches re-verified (changelog: SDK floor + cupertino_ui internal migration; README: optional asset). P1's four-level zero-use proof + the pub-deps three-way check authorized the removal — the dotenv/F8 precedent applied to its second zero-use dependency. Non-blocking notes recorded (^1.0.9-vs-^1.0.8 conflation pre-noted; pub get over pub upgrade strictly safer). Commits: `build(deps): remove zero-use cupertino_icons dependency (dead weight, dotenv precedent)` / `docs: dart-define-only config references (post-cycle-15 truth)` / `docs(plans): close cycle 15 and open cycle 16 plan`. Version bump: none; next tag carries 1.2.4 and unlocks the ^11 fss follow-up. |
| 2026-10-14 | **Push EXECUTED** — `0cd5fdc` build(deps) (pubspec.yaml + lock), `5aeca1a` docs (2 files), `3d41302` docs(plans); remote main = `3d41302`; no version bump; tags untouched. |
| 2026-10-14 | **CI GREEN — PLAN CLOSED.** Build APK run **38510803047 SUCCESS (10m57s)**: **APK built WITHOUT the cupertino font — the zero-use removal proven**; C1 guard + format gate + strict-lint analyze + 222/222 + merged-manifest guard all green; annotations 3 informational (incl. the Ubuntu 26 runner notice — F18 watch item). Promote to Landing run **38511755124 SUCCESS (39s)**: full promotion; freshness byte-exact (183,012,379 B). Environment observation recorded (gh auth keyring token warning — operations all succeeded, non-blocking). The zero-use cleanup pattern has now removed TWO dead dependencies (dotenv, cupertino_icons). Zombie run untouched (accepted). Moved to `plans/done/`. |

- Cycle-17 pre-ranked: **F11 part 3c-4** (flutter_launcher_icons 0.14.4 — map-first; the LAST item in the small-majors queue). **B2 desktop-identity** remains a user decision; the ^11 fss follow-up remains gated on the user's next release tag; **F4/F5/F12 remain CLOUD-BLOCKED** (16 cycles) — standing user escalation.
- This plan is `done` only when P1+P2 PASS the single review, the push is Adviser-approved and executed, and BOTH workflows are green.
