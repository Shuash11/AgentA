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
- **Responsible:** frontend. **Files:** `lib/theme/app_theme.dart` (retheme the `App*` token classes + the light ThemeData), `lib/cubit/theme/theme_cubit.dart` (`ThemeColors` → the new palette; remove the dark branch/switch per the light-only decision).
- Gates: analyze 0; suite green.

## Phase 2 — Screen overhaul, batches (CHEAP per batch — markup/spacing/colors)
- **Responsible:** frontend. Batch A: auth (login/register/forgot_password). Batch B: `chats.dart` + the 9 chat widgets. Batch C: dashboard, profile ×6, `download_prompt_screen`, shared shell/nav/banner.
- **Reclassify rule:** any batch that touches navigation/state/forms logic becomes EXPENSIVE retroactively and gets its behavior tested before review.

## Phase 3 — Anti-slop sweep (CHEAP)
- **Responsible:** frontend + the Reviewer's grep gate: zero `LinearGradient`/`BackdropFilter`/emoji-in-`Text` occurrences under `lib/presentation` (whitelist documented in the spec).

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
