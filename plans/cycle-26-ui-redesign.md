# Cycle 26 — The white-theme UI redesign (user-mandated, full app)

**status:** active — cycle-25 closed 2026-10-16; P0 (design-of-record) delegated
**created:** 2026-10-16 by Adviser (user mandate: "the UI is full of AI slop — redesign the UI completely, make it a white theme, modern style" — changing is a must)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 950f793
**task level:** **Level 3 — Complex** (observable signal: touches far more than five files — a cross-cutting visual overhaul of every screen; default Level 2 escalated upward). Security phase: NOT required (no auth/data/API surface — process depth follows the task). Contract gate: NOT triggered (no API shape; the design spec in P0 is the contract of record for the UI phases).
**environment note:** project skills are NOT in the loadable registry — every delegation reads its skills BY PATH: `C:\projects\aiproject\.opencode\skills\<name>\SKILL.md` (designer/frontend → `ui-reference`; research gates → `web-research`; Reviewer → `review-project`). The `designer` agent exists and owns the design of record.

## Ground truth (verified 2026-10-16)
- Theme tokens: `lib/theme/app_theme.dart` (287 lines: `AppSpacing`, `AppRadius`, `AppDurations`, `AppColors` — dark-first amber identity plus a light scheme — and `AppTheme.darkTheme`/`lightTheme`) + `lib/cubit/theme/theme_cubit.dart` (the `ThemeColors` palette consumed across screens, e.g. `update_available_dialog.dart:23`).
- Screen inventory (glob, 74 dart files under lib/): auth (`login`/`register`/`forgot_password`), `dashboard`, `chats` + 9 chat widgets, profile (`profilepage`/`editprofile`/`change_pass_page`/`securitypage`/`securityservice`/`confirmation`), `download_prompt_screen`, shared (`app_shell`/`bottomnavbar`/`offline_model_banner`/update dialogs/`system_keyboard_text_field`).
- Baseline gates: `flutter analyze` exit 0; `flutter test` 241/241 — the redesign may adapt widget tests; record the new count at each gate.

## Design decisions (Adviser, final unless the user overrides before P1)
- **Light-only.** White/light is the ONLY theme; the dark theme and the theme-switch state are removed (the user asked for white; dark mode = a follow-up if ever requested). Flag to the user at relay.
- **Anti-slop constraints (binding on the spec and the Reviewer's grep gate):** no decorative gradients; no emoji in UI chrome (Material icons only); no glassmorphism/backdrop-blur decoration; restrained elevation; ONE accent color; WCAG AA contrast on white.
- **Modern = Material 3 light system**: a proper ColorScheme, type scale, and one spacing/radius/elevation scale — the existing `App*` token classes are the carrier: retheme them, do not fork them.
- Scope = EVERY screen; nothing grandfathered. Dialog copy stays proper English (the user's "Like you want to update?" was an example — "like").

## Backlog (re-ranked, uncapped — the user mandate jumps the queue)
| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **C26 → THIS CYCLE** | White-theme full redesign (design-of-record → foundation → screens → sweep) | UI/UX | the user mandate; lib/theme + lib/presentation inventory | designer + frontend | EXPENSIVE |
| C27 (queued) | Update-dialog audit — the feature ALREADY EXISTS (`plans/cycle-27-update-dialog-audit.md`) | feature-verify | the verified file set | middle-end + frontend | EXPENSIVE |
| F12 | Edge Function deploy (the second cloud-mutation cycle; was pre-ranked cycle 26 — pushed behind the user mandate) | cloud | cycle-25 plan | backend | EXPENSIVE |
| F4 | Schema pull — REDUCED: the base schema is captured in-repo by cycle-25's drift remedy; F4 = verify the captured chain + fresh-install coherence (the version ordering `0001` < `20260904150000` remains broken for FRESH databases — fix or explicitly accept) | data | cycle-25 STOP-2 | backend | EXPENSIVE |
| Bug A user actions | GCP SHA-1 registration + stale-APK reinstall — unchanged | user | cycle-24 closure row | user | user |
| F18 | Ubuntu-26 runner watch (from Oct 19) — observe-only | CI | cycle-25 plan | backend | observe |
| F30 | RESOLVED — project restored ACTIVE_HEALTHY (2026-10-16) | — | cycle-25 STOP-2 | — | closed |

## Phase 0 — Design-of-record (CHEAP — artifact only, no code)
- **Responsible:** designer (read `ui-reference` by path; run the P0 web searches below).
- **Deliverable:** `docs/design/ui-redesign-spec.md` — principles + the anti-slop rules; the light palette tokens (surface/card/input/border/text/subtext/accent/semantic); type scale; spacing/radius/elevation; per-screen treatment for the FULL inventory; accessibility (AA on white).
- **STOP:** a spec that is not white/light or reintroduces slop → STOP, Adviser.
- **Verification:** CHEAP — Adviser reviews the spec before P1 starts.

## Phase 1 — Theme foundation (CHEAP — visual tokens, no behavior)
- **Responsible:** frontend. **Files:** `lib/theme/app_theme.dart` (retheme the `App*` token classes + the light ThemeData), `lib/cubit/theme/theme_cubit.dart` (`ThemeColors` → the new palette; remove the dark branch/switch per the light-only decision), `lib/main.dart` (**Adviser correction 2026-10-16:** the two `darkTheme: AppTheme.darkTheme` MaterialApp call sites at :349/:477 must be removed — compile-level dark-theme detachment only; found by the Adviser's grep, missed by the designer's removal-safety check), and `lib/presentation/shared/system_keyboard_text_field.dart` (`keyboardAppearance: Brightness.light`, spec §2). Plus MECHANICAL rename-only fixes wherever removed/renamed token fields break compilation (e.g. `colors.amber` → `colors.accent`) and test adaptations — any judgment-call visual change in a consumer file is P2 scope.
- Gates: analyze 0; suite green.

## Phase 2 — Screen overhaul, batches (CHEAP per batch — markup/spacing/colors)
- **Responsible:** frontend. Batch A: auth (login/register/forgot_password). Batch B: `chats.dart` + the 9 chat widgets. Batch C: dashboard, profile ×6, `download_prompt_screen`, shared shell/nav/banner — **plus `lib/main.dart` (Adviser amendment 2026-10-16, post-P1): ALL THREE raw-color surfaces are tokenized — the `_AppLoader` splash (:349-460: navy `0xFF1A1A2E` canvas, gold `0xFFFFD700`, white/white70 text, orange/green/red status colors), the orange warning container (:319-335), and the error/offline screen (:572-627) — colors/typography/copy ONLY (boot-critical code: zero changes to `_initializeApp`/`InitState`/routing logic; reclassify rule applies), the two `themeMode: ThemeMode.dark` arguments removed (:349/:476), and the `_AppLoader` + warning-box + error-screen treatment rows added to spec §6.**
- **Reclassify rule:** any batch that touches navigation/state/forms logic becomes EXPENSIVE retroactively and gets its behavior tested before review.

## Phase 3 — Anti-slop sweep (CHEAP)
- **Responsible:** frontend + the Reviewer's grep gate: zero `LinearGradient`/`RadialGradient`/`SweepGradient`/`BackdropFilter`/`ImageFilter.blur`/emoji-in-`Text` under **`lib/`** (widened 2026-10-16 from `lib/presentation` — main.dart's surfaces must not survive), and zero raw `Colors.*`/`Color(0x…` under `lib/` **excluding `lib/theme/app_theme.dart`** (the token definitions) and the §1.2 whitelist. The §1.2 gate commands in the spec are updated to match during Batch C.

## ORCHESTRATION RULE (binding)
ALL phases implemented first, completely; NO mid-plan gates; then **e2e-tester ONCE** (EXPENSIVE — every standing flow + every screen renders with no overflow) and the **Reviewer ONCE** over the whole plan; Adviser push confirmation; bookkeeping push + CI watch. Definitive acceptance = post-push CI green + the e2e/review evidence.

## Push guidance
- Version bump: **minor** (1.3.0+1 — a user-visible overhaul). Final; the push agent must not re-decide.
- Commits: theme foundation / screen batches / docs — atomic; explicit staging; never root-wide `git add`; `.opencode/` excluded.
- On red: plan stays `active`; Adviser plans the fix phase. On green (after e2e + Reviewer): Adviser marks `done`, moves to `plans/done/`, opens the cycle-27 queue.

## Reviewer web searches (per the web-research skill, read from `.opencode/skills/web-research/SKILL.md`)
1. Material 3 color system + light-theme guidance (m3.material.io — primary).
2. Flutter contrast/accessibility guidance for AA on white surfaces.
3. Current token-driven mobile design-system practice (restrained UI, no decorative gradients/blur).

## Governance
| Date | Event |
|---|---|
| 2026-10-16 | Plan created `queued` (user-mandated; runs after cycle-25 closure). Classifications: P0 CHEAP; P1 CHEAP; P2 CHEAP per batch (reclassify-on-behavior rule); P3 CHEAP; the plan-end e2e EXPENSIVE. |
| 2026-10-16 | **P0 SPEC RATIFIED — implementation-ready with one Adviser correction; status → `active`.** Independently verified: the SyncingBanner white-on-light defect is real (`offline_model_banner.dart:206` amber@0.15 fill + `:222` `textDark` white text) and the amber left-border (:146); contrast arithmetic re-computed by the Adviser: `#3D5AFE` on white = **5.13:1 (AA normal-text pass)**, amber ink on white = **1.63:1 (fail)** — the spec's numbers are exact. **All four flagged decisions RATIFIED** (1: accent amber→indigo `#3D5AFE`; 2: canvas `#F5F5F5`→`#FAFAFA`; 3: Roboto retained with the documented type-scale decision; 4: auth padding 28→24 + copy-target 32→48dp). **Correction:** the designer's removal-safety grep missed the two `darkTheme:` MaterialApp call sites (`main.dart:349/:477`) — P1's file list amended accordingly + the spec §2 gets the two call sites synced during P1. The 61-raw-colors figure accepted as designer-reported (lib/presentation scope; non-load-bearing — the P3 gate enforces zero). The §1.2 P3 whitelist ratified as CLOSED. P1 delegation issued to frontend. |
| 2026-10-16 | **P1 GREEN + Adviser scope rulings.** P1 gates all green: analyze 0; 241/241 unchanged (zero test adaptations); grep gates clean (0 dark/token references); keyboard forced light at both widget sites; `main.dart` darkTheme args removed; spec header approved + §2 synced; 20 mechanical rename-only consumer fixes; no new deps. **Rulings:** (1) the flagged dark slop surface is REAL and BIGGER than flagged — main.dart holds THREE raw-color surfaces (splash :349-460, orange warning container :319-335, error/offline screen :572-627), all outside the spec inventory and the P3 gates → **added to Batch C** (tokenize, colors/typography/copy only, boot-critical logic untouched) and the **P3 gates widened to `lib/`** (excluding `app_theme.dart` token definitions + the §1.2 whitelist); (2) `themeMode: ThemeMode.dark` residue (:349/:476) → **removed in Batch C** (moots the framework-fallback question); (3) `textDark`→`text` rename ACCEPTED (the only possible compile fix after the dual-token collapse; incidentally fixes the SyncingBanner white-ink defect — the §6.3 StatusBanner rebuild in Batch C still applies, the rename alone leaves A4/A7 violations); (4) `inputPadding` v14 + `chatInputPadding` v12 + `AppTypography.button` VERIFIED in code as exact §4.3/§5.1 reads — ratified; (5) `change_pass_page.dart` raw amber — confirmed no-action (Batch C scope per §6.3). P2 Batch A delegated. |
| 2026-10-16 | **PUSH APPROVED (Adviser, all gates green).** P0-P3 complete; e2e ONCE PASS (release APK built, exit 0, 174.5 MB; every standing flow + light-only/anti-slop/a11y spot-checks PASS); Reviewer engagement: pass 1 FAIL → blocking defect D1 (spec §7.4 icon-only controls missing tooltip/Semantics labels) → frontend fixed 12 controls across 10 files (labels-only; Send/Stop via `Semantics(button:true, enabled:…, label:…)`; Back ×7; Select model; Show/Hide password ×3) → **pass 2 PASS** (13 label sites independently verified; IconButton 12/12, InkWell 8/8; label-only diff proven; all gates re-run clean). 241/241 throughout. **Commit plan:** 1 `feat(ui): white light-only M3 theme foundation — tokens, typography, dark-mode removal (C26)` (lib/theme + lib/cubit/theme + lib/main.dart) → 2 `feat(ui): restyle all screens to the white theme + accessibility labels (C26 P2/P3)` (lib/presentation) → 3 `docs(design): add the ratified UI redesign design-of-record + cycle-26 plan rulings (C26)` (docs/design/ui-redesign-spec.md + plans/cycle-26-ui-redesign.md) → 4 `chore(release): bump version to 1.3.0+1 (C26)` (pubspec one-liner, Adviser-authorized). Version bump **minor 1.3.0+1 — FINAL**. Exclusions: .opencode/ churn, analysis_options.yaml; never root-wide add. On green: Adviser closes the plan (done + move). **The v1.3.0 release cut (per the established release process) is the next user action and arms cycle 27's live diagnostic.** |
| 2026-10-16 | **Cycle 27 RE-SCOPED** (user defect report: the update dialog never appears on an installed CI-signed 1.2.4 build despite v1.2.5 being latest — the "audit, not a build" premise is invalidated). Re-scoped to **diagnosis + fix**; see `plans/cycle-27-update-dialog-audit.md` (retitled in place). |
