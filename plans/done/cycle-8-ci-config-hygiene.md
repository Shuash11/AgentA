# Cycle 8 — CI/Config Hygiene Cluster (stale pin, tag guard, cosmetic comments)

**status:** done (closed 2026-10-13 — P1-P3 PASS, push executed, both workflows green; Gradle resolved unpinned — the real F17 proof)
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 8 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ d4c852b
**predecessors:** plans/done/cycle-1..7 (all closed, CI green; latest runs 38323123097 / 38324251857)

## Cycle 8 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` (strict lints) | **"No issues found!" exit 0** — 8th consecutive clean cycle |
| `flutter test` | **208/208 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| F17 preconditions | **BOTH MET**: toolchain on Flutter 3.47.6 since cycle 1; background_downloader **9.6.4** shipped since cycle 6. The `settings.gradle` serialization pin (:18-29) and its comment are provably stale. |
| Manifest comments | `AndroidManifest.xml:5` and `:52` cite "background_downloader 9.5.9 (doc/CONFIG.md:39-46)" — version now 9.6.4 (stale comment text; the WorkManager foreground-service requirement itself is version-stable) |
| proguard-rules.pro:9 | `# MediaPipe (flutter_gemma)` comment over two `-dontwarn com.google.mediapipe.proto...` rules — the RULES are functional (flutter_edge_ai still ships MediaPipe; MediaPipeEngine preserved in cycle 7), only the comment text is stale |
| ios/Podfile:10-11 | DEVIATIONS comment cites "flutter_gemma_mediapipe 1.0.6, per its pub.dev README" for the 16.0 floor + static linking — package is now flutter_edge_ai_mediapipe 1.0.8; **functional settings (platform :ios '16.0', use_frameworks! static) must NOT change** (iOS is buildable-by-construction only on this machine — Podfile caveat :22-30) |
| CI | runs 38323123097 / 38324251857 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F17** | **Stale serialization pin** — settings.gradle:18-29 `resolutionStrategy` block forcing `kotlin.plugin.serialization` 2.3.20; both removal preconditions met (3.47+ toolchain, bgdl 9.6.4). Removal test: resolution succeeds without the force; **definitive proof = CI APK build (Gradle plugin resolution runs at build, not at pub get)**. Plus stale bgdl version comments in AndroidManifest (:5, :52). **SELECTED (cluster P1).** | maintainability | settings.gradle:18-29; AndroidManifest:5,:52 | backend | CHEAP |
| **F15** | **Tag-guard cannot catch duplicate-semver re-tagging** — the documented failure: re-tag v1.1.0 on a new commit with pubspec unchanged passes today's guard and silently publishes a release installed apps can never detect (docs/versioning.md §6 marks it a process rule because CI cannot catch it — this cycle makes CI catch it). **SELECTED (cluster P2).** | CI / logic | docs/versioning.md §6; build-apk.yml tag-assert step | backend | CHEAP |
| **F22** *(new, from cycle 7 carry-forward)* | **Stale cosmetic comments post-migration**: proguard-rules.pro:9 ("flutter_gemma") and ios/Podfile:10-11 ("flutter_gemma_mediapipe 1.0.6"). Comment-text-only; functional rules/floors stay untouched (Reviewer-validated in cycle 7). **SELECTED (cluster P3).** | maintainability | file reads (above) | middle-end | CHEAP |
| **F16** | **promote-landing main-branch fallback can promote an older commit's APK** — accepted-risk, warned in logs. No action; recorded. | CI | promote-landing.yml:123-145 | — | accepted |
| **F21** | **Transitive discontinued (flutter_secure_storage_macos, js)** — ride the blocked win32→fss-11 lattice; the 9→11 jump carries a documented data-loss risk and must be its own validated cycle. | maintainability | pub outdated resolvable "-" | backend | EXPENSIVE |
| **F11** | **Blocked-major dependency set** (win32 6.4.0, flutter_bloc 9.1.1, connectivity_plus 7.3.2, flutter_dotenv 6.0.1, cupertino_icons 2.0.0, flutter_lints 6.0.0, flutter_launcher_icons 0.14.4, package_info_plus 10.2.2) — each needs its own constraint-edit cycle. | maintainability | pub outdated | middle-end | EXPENSIVE |
| **F6** | **Local passwords = salted SHA-256** (no work factor); argon2/SQLCipher hardening path. | security | lib/services/auth/password_hasher.dart | security | EXPENSIVE |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — deliberate deferral; AGP 9 + Built-in-Kotlin migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F19** | **Zombie queued run 34749579707** — accepted cosmetic noise (cycle-5 ruling). | CI hygiene | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing escalation to the user.** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: 8 clean cycles; the remaining cheap debt is exactly this cluster — a provably stale build config (whose removal is only provable via CI's Gradle resolution), a documented CI blind spot for duplicate-semver releases, and migration leftover comment text. All CHEAP, all low-risk, no e2e.

---

## Selected task (single): F17 + F15 + F22 — CI/config hygiene cluster

**Objective:** the Gradle build resolves without stale forced versions; duplicate-semver re-tagging fails CI; zero stale `flutter_gemma` comments remain.

**Version bump decision: none** — config hygiene is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — since every phase below is **CHEAP-class, no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch — **for P1 specifically, the APK build step exercises Gradle plugin resolution, so CI green IS the real proof the pin removal is safe** (local `flutter pub get` cannot test Gradle resolution).

---

## Phase 1 — Remove the stale serialization pin + refresh manifest comments (F17)

- **Phase id:** P1
- **Objective:** Gradle resolves plugins with no forced serialization version; manifest comments state the true bgdl version.
- **Responsible subagent:** backend
- **Files to change:** `android/settings.gradle` (remove block), `android/app/src/main/AndroidManifest.xml` (2 comment lines)
- **Implementation steps:**
  1. Remove the entire `resolutionStrategy { ... }` block from `pluginManagement` in `android/settings.gradle` (lines 18-29, including the stale comment that cites background_downloader 9.6.2). Nothing else in the file changes.
  2. Sanity: `flutter pub get` → resolution succeeds (this proves pub-level health only).
  3. AndroidManifest.xml:5 and :52: update "background_downloader 9.5.9" → "background_downloader 9.6.4" in the comment text. Do NOT touch the manifest's functional elements (the CI dataSync guard greps this file — keep the `SystemForegroundService` declaration and `foregroundServiceType="dataSync"` exactly as-is; comment-only edits).
  4. Note: the definitive F17 proof is the post-push APK build (Gradle plugin resolution) — if background_downloader 9.6.4 or any other plugin reintroduces a conflicting serialization requirement, CI fails at the Gradle step with a version-mismatch error → fix phase re-adds a correctly-scoped pin.
- **Acceptance criteria:** settings.gradle has no `resolutionStrategy` block; manifest diffs = 2 comment lines only; pub get succeeds.
- **Verification:** **CHEAP** — config-only; definitive = post-push CI APK build.
- **Dependencies / sequencing:** first.
- **Expected result:** toolchain config states only true facts; resolution is unforced.

## Phase 2 — Duplicate-semver re-tag guard (F15)

- **Phase id:** P2
- **Objective:** re-tagging an already-released version at a different commit fails CI with an actionable error.
- **Responsible subagent:** backend
- **Files to change:** `.github/workflows/build-apk.yml` (the existing **"Assert v* tag matches pubspec version"** step gains the guard — no new step)
- **Implementation steps:**
  1. Inside the existing tag-assert step (runs only on `refs/tags/v*`), after the version-match check, add: query the remote for a pre-existing release of this exact tag name (`gh release view "$TAG" --repo "$GITHUB_REPOSITORY"`); if one exists, fetch the tagged commit via the git-refs API (`gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$TAG" --jq '.object.sha'`) and handle **annotated-tag peeling** (object.type == "tag" → follow to the peeled commit via `git/ref/tags/$TAG` object type check or `^{}"`-style resolution) — if the existing release's commit differs from `${GITHUB_SHA}` → `::error::` + exit 1 ("Tag '$TAG' was already released from a different commit — re-tagging an already-released version is forbidden (docs/versioning.md §6); bump the version instead"). If the commit matches → pass (idempotent re-run of the same release). If no release exists → pass (first release for this version).
  2. Auth: `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` env for the gh calls (repo already grants contents: read at workflow level — the step inherits it).
  3. Document the honest caveat as a step comment: the guard detects the duplicate-RELEASE path (release exists at a different commit); a force-pushed tag where no release was ever cut remains covered only by the process rule.
  4. YAML parse validation; no other steps touched.
- **Acceptance criteria:** guard added inside the existing step; first-time tags and idempotent re-runs pass; duplicate-version releases fail with the documented error; caveat commented; YAML valid.
- **Verification:** **CHEAP** — CI config; runtime behavior of the guard is only exercised on tag builds (acceptance is structural + Reviewer-validated semantics).
- **Dependencies / sequencing:** independent of P1/P3.
- **Expected result:** docs/versioning.md §6's "CI does NOT catch it" footnote becomes false — update that doc line in this phase too (`docs/versioning.md` §1 note and §6 row: CI now catches duplicate-version releases via the release-SHA check).

## Phase 3 — Cosmetic comment touch-ups (F22)

- **Phase id:** P3
- **Objective:** zero stale `flutter_gemma` comments; functional content untouched.
- **Responsible subagent:** middle-end
- **Files to change:** `android/app/proguard-rules.pro` (1 comment line), `ios/Podfile` (comment lines 10-11)
- **Implementation steps:**
  1. proguard-rules.pro:9: `# MediaPipe (flutter_gemma)` → `# MediaPipe (flutter_edge_ai engine)`. The two `-dontwarn` RULES stay byte-identical (functional; MediaPipe ships with the new engine too). If R8 ever reports a missing-class warning for these protos post-migration, that's a separate fix — out of scope.
  2. ios/Podfile lines 10-11: update the DEVIATIONS citation to "flutter_edge_ai_mediapipe 1.0.8, per its pub.dev README (floor requirement to be re-validated against the new package's README on a Mac — see the caveat below)". The functional settings (`platform :ios, '16.0'`, `use_frameworks! :linkage => :static`) and the honest buildable-by-construction caveat (:22-30) stay byte-identical.
  3. Comment-text-only — a functional diff in either file = STOP and report (would reclassify the phase).
- **Acceptance criteria:** both diffs are comment lines only (`git diff` inspection); gates unaffected.
- **Verification:** **CHEAP** — comment text only.
- **Dependencies / sequencing:** independent; batched last.
- **Expected result:** documentation says what the code actually is.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `build(android): remove stale serialization pin and refresh bgdl comments (preconditions met)` — settings.gradle + AndroidManifest.xml.
- Commit 2: `ci: guard against duplicate-semver re-tagging in Build APK` — build-apk.yml + docs/versioning.md (the §6 truth-table update belongs with the guard that changes it).
- Commit 3: `docs: refresh stale flutter_gemma comments in proguard rules and iOS Podfile` — proguard-rules.pro + ios/Podfile.
- Commit 4: `docs(plans): close cycle 7 and open cycle 8 plan` — stage `plans/` explicitly (deletion of old cycle-7 path, `plans/done/cycle-7-...md`, new cycle-8 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); iOS/Android registrant build artifacts stay git-ignored.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — with P1's real proof inside it: the APK build step runs Gradle plugin resolution WITHOUT the pin. If Gradle fails with a serialization version-mismatch, capture `gh run view <id> --log-failed` — that error text names the conflicting plugin and becomes the correctly-scoped re-pin evidence (fix phase).
- **Promote to Landing** green as usual. Note: P2's guard only executes on v* tag builds — main-branch runs exercise everything else.
- On red: capture evidence, plan stays `active`, Adviser plans the fix phase. Do not retry or fix autonomously.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-9 audit (pre-ranked: F21/F11 lattice work needs its own carefully-validated EXPENSIVE cycle; the user's cloud-escalation for F4/F5/F12 remains standing).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `Kotlin serialization plugin version must match compiler version gradle` (kotlinlang.org / kotlin.github.io — validates what the removed pin was forcing and what an unresolved mismatch would look like).
2. `GitHub API get tag reference annotated object type peeled commit` (docs.github.com REST — the `git/ref/tags/$TAG` object.type == "tag" vs "commit" peeling semantics P2 depends on).
3. `gh release view exit code when release does not exist` (cli.github.com — confirm the non-existence path returns non-zero so the "first release" branch is correct).

## Reviewer verification commands (single pass, after P1-P3)

1. `git diff android/settings.gradle` → resolutionStrategy block removed, nothing else; `git diff android/app/src/main/AndroidManifest.xml` → 2 comment lines only (dataSync declaration byte-identical — CI guard depends on it).
2. `flutter pub get` → succeeds on the unpinned resolution.
3. `git diff .github/workflows/build-apk.yml` → guard inside the existing tag-assert step; YAML parse; first-run/idempotent/duplicate logic present with the caveat comment; `git diff docs/versioning.md` → §6 row updated to match reality.
4. `git diff android/app/proguard-rules.pro ios/Podfile` → comment lines only; `-dontwarn` rules + platform floor + use_frameworks! + caveat byte-identical.
5. Baseline gates: `flutter analyze` exit 0 (strict lints), `flutter test` 208/208, `dart format --output=none --set-exit-if-changed lib test` exit 0.
6. Scope: no other files; analysis_options.yaml absent; .opencode/ absent.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-8 audit recorded; plan created `active` (cluster F17+F15+F22). F22 added from cycle-7 carry-forward. F16/F19 remain accepted-no-action. |
| 2026-10-13 | **P1-P3 IMPLEMENTED, SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser verified per-file: settings.gradle = block removal only; manifest = 2 comment lines with the dataSync declaration byte-identical (CI guard intact); build-apk.yml = duplicate-semver guard INSIDE the existing tag-assert step (peeled-commit handling, 4-branch logic, honest caveat) with the **evidence-backed GITHUB_SHA-premise deviation ratified** (plan's literal mechanism provably couldn't catch the motivating re-tag — GITHUB_SHA on tag pushes IS the peeled commit, empirically confirmed on this repo's runs; live-tested 6/6; Reviewer-ruled sound and necessary); docs/versioning.md §1+§6 now match reality with the residual process rule preserved (never-released force-pushed tags); proguard/Podfile = comment-only (functional content untouched, Reviewer's accepted :16 deviation included); gates re-run — analyze exit 0, format 0 changed, 208/208. Reviewer non-blocking notes recorded: guard fails closed on transient gh api failure (safe); duplicate gh api calls could combine (future nit). Commits: `build(android): remove stale serialization pin and refresh bgdl comments (preconditions met)` / `ci: guard against duplicate-semver re-tagging in Build APK` (+ versioning.md) / `docs: refresh stale flutter_gemma comments in proguard rules and iOS Podfile` / `docs(plans): close cycle 7 and open cycle 8 plan`. Version bump: none; next tag carries 1.2.4. |
| 2026-10-13 | **Push EXECUTED** — `c4231a5` build(android) (pin removed + manifest comments), `0e5fbc5` ci (duplicate-semver guard +51 lines in the existing tag-assert step, versioning.md §1/§6), `cf6208d` docs (comment refreshes), `52d96b8` docs(plans); remote main = `52d96b8`; no version bump; tags untouched. |
| 2026-10-13 | **CI GREEN — PLAN CLOSED.** Build APK run **38331155451 SUCCESS (12m40s)**: the APK build step resolved Gradle plugins **WITHOUT the serialization pin** for the first time — the real F17 proof; all 26 steps green; annotations info-only, zero failures. Promote to Landing run **38332174842 SUCCESS (38s)**: full promotion path, Vercel deploy triggered. Tag guard not exercised (main-branch run; fires only on v* tag builds — live-tested 6/6 during review). Zombie run untouched (accepted). Moved to `plans/done/`. |

- Cycle-9 pre-ranked: F21/F11 lattice work (EXPENSIVE — the 9→11 flutter_secure_storage jump carries documented data-loss risk; plan carefully with migration/data-migration research first). The user's cloud-escalation for F4/F5/F12 remains standing.
- This plan is `done` only when P1-P3 PASS the single review, the push is Adviser-approved and executed, and BOTH workflows are green.
