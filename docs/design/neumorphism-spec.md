# AgentA Neumorphism Redesign — Design of Record (Cycle 28, P1a)

**status:** ratified by the Adviser 2026-10-18 — conditional on the §2a addition recorded below; awaiting the user's aesthetic confirmation (post-v1.3.1-install or written waive)
**owner:** designer
**mandate:** user directive — a neumorphic, light-only, modern, professional AgentA (supersedes the cycle-26 white theme for implementation; the white spec remains the structural map). Source of truth: `plans/cycle-28-in-app-update-flow.md` (ruling 2 + the P1a delegation of record).
**scope:** every screen under `lib/presentation/` (28 files, nothing grandfathered, login included) + the theme carrier `lib/theme/app_theme.dart` / `lib/cubit/theme/theme_cubit.dart` (retheme, not fork). WS-UPD (the in-app update flow) is a separate workstream of the same plan.

---

## 0. Web-research declarations (per `.opencode/skills/web-research/SKILL.md`)

1. **Neumorphism accessibility critique + mitigations**
   - `search: done (partial)` — the canonical UX-collective critique (uxdesign.cc, "Neumorphism in user interfaces") returned **HTTP 403** and could not be fetched → recorded as **lead-only, unverified** per the skill's source filter.
   - Grounding used instead (verified): **W3C WCAG 2.2 SC 1.4.3 (contrast minimum, 4.5:1 / 3:1) and SC 1.4.11 (non-text contrast, 3:1)** — https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html (cited and verified in the cycle-26 spec §0; updated 2026-09-06). The known critique — low-contrast surfaces, states communicated only by shadow direction, grey-on-grey text — maps directly onto those SCs; this spec answers it structurally (§5 state-visibility table + §3 AA-computed ink tokens), not rhetorically.
2. **Flutter neumorphism practice — hand-rolled vs packages**
   - `search: done` — **`flutter_neumorphic` v3.2.0: published 4 years ago, unverified publisher, incomplete package analysis, requires Flutter ≥ 1.13** (https://pub.dev/packages/flutter_neumorphic) → **UNMAINTAINED for this Flutter 3.x app — REJECTED** (the ruling's presumptive rejection is confirmed by the fetched record). A community fork (`flutter_neumorphic_plus`) exists but was not verified → lead-only, not adopted.
   - **Recommendation: hand-rolled `BoxShadow` token pair** on the existing carrier (`AppColors`/`AppTheme` — retheme, not fork). Zero new dependencies; the full neumorphic surface language is two shadow tokens + an inset variant.
3. **Material 3 interplay with neumorphic surfaces**
   - `search: done (prior)` — Flutter `ColorScheme` API docs (verified in the cycle-26 spec §0): M3 roles/tone system is retained where it does not conflict (dialogs, sheets, snackbar, progress, FAB keep M3 component structure); the SURFACE treatment is replaced by the neumorphic dual-shadow system. `m3.material.io` remains JS-gated → `unverified` (unchanged from cycle 26).

**Codebase reads (internal facts):** `lib/theme/app_theme.dart` (the token carrier), `lib/cubit/theme/theme_cubit.dart`, all 28 files under `lib/presentation/` (the cycle-26 spec §6 inventory is the structural map), and the ui-reference reject list (`.opencode/skills/ui-reference/SKILL.md`).

---

## 1. Design principles

1. **One material.** The entire app is a single continuous surface (`base`). Elements do not float above it — they extrude from it (raised), sink into it (inset), or lie flush (flat). Depth is the hierarchy.
2. **Depth is physical, never decorative.** The dual-shadow pair is the structure (see §4). It never appears in a color other than the derived pair, never glows, never renders without a structural reason.
3. **States are honest and multi-channel.** Depth change alone never communicates a state (§5). Every interactive element answers "which state am I in?" through depth AND a second channel (accent/icon/label/opacity).
4. **Contrast is computed, not assumed.** Every ink token passes WCAG AA against `base` (§3, math shown). Grey-on-grey text is banned.
5. **One accent, used sparingly.** Accent = primary action, selection, focus, progress, links (as `accentInk`). Everything else is the base material.
6. **Color has a job.** Semantic color appears only as icon + text (status), never as surface decoration.
7. **Proper copy.** Sentence case, full sentences, no emoji, no raw errors (carried from the cycle-26 spec §8).

## 2. Amended anti-slop rules (binding on Phases P2–P5 and the Reviewer's grep gates)

| # | Rule | Amendment note |
|---|---|---|
| N1 | **No decorative gradients.** Zero `LinearGradient`/`RadialGradient`/`SweepGradient` under `lib/`. | Unchanged from A1. |
| N2 | **No glassmorphism / backdrop blur.** Zero `BackdropFilter`/`ImageFilter.blur` under `lib/presentation/`. | Unchanged from A2. |
| N3 | **No emoji in UI chrome.** Material icons only. | Unchanged from A3. |
| N4 | **No colored left-border panels.** Statuses use the raised neutral surface + semantic icon/text (§6). | Strengthens A4: the panel pattern has no neumorphic form. |
| N5 | **AMENDED (was "borders over shadows"): the neutral dual-shadow pair IS the structure.** `shadowLight`/`shadowDark` are the only shadows permitted; **no colored shadows, no glows, no drop-shadow stacks beyond the pair.** | Neumorphism's defining system, constrained to two neutral derived tokens. |
| N6 | **ONE accent.** `accent` for fills/focus/progress; `accentInk` for accent-colored text. Icons default to `ink`/`subtext`, never accent. | Carries A6 + adds `accentInk` (the AA-correct text form — §3). |
| N7 | **All color via tokens.** Zero raw `Colors.*`/`Color(0x…` under `lib/` outside `app_theme.dart` and the whitelisted scrim. | Carries A7; scope widened to `lib/` (the cycle-26 P3 gate). |
| N8 | **Differentiated radii.** The §6 radius scale — never one radius everywhere. | Carries A8; values re-judged softer (§6). |
| N9 | **Restrained motion.** 150/220/280 ms, `easeOutCubic`, `disableAnimationsOf` honored. Depth transitions animate shadow offset/blur within these bounds. No bounce/elastic. | Carries A9. |

## 2a. Light-only mechanics (RETAINED — the neumorphism retheme must not reintroduce them)

- The cycle-26 P1 deletion is **RETAINED state, not new work**: no `darkTheme`, no dark tokens, no `darkColorScheme`, no `toggleDarkMode`/`setDarkMode`, `ThemeState` light-only, `Brightness.light` keyboard forced (§7, `system_keyboard_text_field.dart`).
- A **dark neumorphic variant is OUT OF SCOPE** for this cycle (the Adviser ruling: light-only). The rejected `flutter_neumorphic` package's dark-mode showcase is explicitly not a feature to replicate.
- P2's retheme of `app_theme.dart`/`theme_cubit.dart` must preserve this state: the cycle-26 grep gate remains binding — `darkTheme|toggleDarkMode|setDarkMode|ThemeState.dark|isDark` → **0 matches** under `lib/`, and zero `AppColors.dark*` references.

## 3. Color tokens (AA math against `base` — formula: W3C relative luminance, WCAG 2.2 SC 1.4.3)

**`base` = `#E0E5EC`** — the canonical neumorphic grey-blue. Luminance L(base) = **0.7794**. Every ratio below is `(0.7794 + 0.05) / (L(token) + 0.05)`.

| Token | Hex | Role | Contrast vs base | AA |
|---|---|---|---|---|
| `base` | `#E0E5EC` | THE surface: scaffold, cards, tiles, sheets, inputs, bars, bubbles | — | — |
| `ink` | `#1A2433` | Primary text, icons | L=0.0172 → **12.3:1** | AA ✓ |
| `subtext` | `#4A5568` | Secondary text, hints, timestamps, typing dots, unselected icons | L=0.0895 → **5.9:1** | AA ✓ |
| `disabledText` | `#8B95A5` | Disabled labels (flat surfaces) | ~2.4:1 | Exempt (WCAG 1.4.3); identifiable via flat-state + N8 |
| `accent` | `#3D5AFE` | Primary button fill, focus rings, progress, selected checks, FAB | **4.05:1** | Non-text ✓ (≥3:1, SC 1.4.11). NEVER small text on base |
| `onAccent` | `#FFFFFF` | Text/icons on `accent` fill | 5.1:1 | AA ✓ |
| `accentInk` | `#2A3990` | Accent-colored TEXT on base: links, selected labels | L=0.0543 → **7.9:1** | AA ✓ |
| `successText` | `#146C2E` | Success text/icon | **5.2:1** | AA ✓ |
| `errorText` | `#8C1D1D` | Error text/icon; destructive text | **7.2:1** | AA ✓ |
| `warningText` | `#7A5200` | Warning text/icon | **5.5:1** | AA ✓ |
| `scrim` | `#000000 @ 54%` | Dialog/barrier scrim | — | M3 standard |
| `shadowLight` | `#FFFFFF` | Dual-shadow, light source (top-left) | — | decorative/structural |
| `shadowDark` | `#A3B1C6` | Dual-shadow, shade (bottom-right) — the dark complement of `base` | — | structural |

Notes: the cycle-26 multi-tone surfaces (`surface`/`card`/`input`/`border` as separate tones) **collapse into `base`** — depth comes from shadows and insets, never tone. Semantic CONTAINER fills are dropped: status color lives in icon + text on the neutral raised surface (N4/N6). `info` remains deleted. `error` FILL is allowed only on destructive confirm buttons and the chat stop button, with `onAccent`-white content. **"On base" means any base-colored surface — raised or inset wells (wells are base-colored, so the same ratios apply to text inside them).**

## 4. Shadow recipes (copyable — the ONLY shadow system, N5)

```dart
// RAISED — cards, tiles, buttons at rest, banners, dialogs, sheets, bubbles
BoxShadow(color: AppColors.shadowLight, offset: Offset(-4, -4), blurRadius: 10),
BoxShadow(color: AppColors.shadowDark,  offset: Offset( 4,  4), blurRadius: 10),

// PRESSED (inset) — buttons/tiles/tabs while pressed; selection wells
BoxShadow(color: AppColors.shadowDark,  offset: Offset(-3, -3), blurRadius: 7),
BoxShadow(color: AppColors.shadowLight, offset: Offset( 3,  3), blurRadius: 7),

// INPUT WELL (inset, at rest) — text fields, search, code blocks
BoxShadow(color: AppColors.shadowDark,  offset: Offset(-2, -2), blurRadius: 5),
BoxShadow(color: AppColors.shadowLight, offset: Offset( 2,  2), blurRadius: 5),

// FLAT (disabled) — NO shadow; disabledText label; element visually "sinks" by flattening
// FOCUSED (added to any of the above) — 2dp AppColors.accent outline, offset 2 (≥3:1 vs base: 4.05)
```

Rules: shadows animate offset/blur only (never color); blur/offset scale with element size (large surfaces 10, controls 7, wells 5); a shadow pair NEVER appears in any other color; the light source is fixed top-left app-wide.

## 5. State-visibility table (the second channel — the answer to the neumorphism critique)

Depth change is ALWAYS paired with a second channel. No state is communicated by shadow direction alone.

| Component | Default | Pressed | Focused | Selected | Disabled | Loading |
|---|---|---|---|---|---|---|
| Primary button | `accent` fill, raised | inset | 2dp `accent` ring | — | flat + `disabledText` | inset + 20dp `onAccent` spinner, label removed |
| Secondary button | `base` raised, `ink` label | inset | ring | — | flat + `disabledText` | spinner |
| Text field | input well | — | well + 1.5dp `accent` ring | — | well + `disabledText` | — |
| Error field | well + 1.5dp `errorText` ring + helper | — | — | — | — | — |
| Tile/card | raised | inset | ring | inset + `accent` check + `accentInk` label w600 | flat | spinner |
| Nav item | flat + `subtext` | inset | — | **inset pill + `accent` icon + `accentInk` label w600** | — | — |
| Link (`accentInk`) | `accentInk` | underline | — | — | `disabledText` | — |
| Chat bubble (user) | `accent` fill raised | inset | — | — | — | streaming = text updates only |
| Chat bubble (assistant) | `base` raised | inset | — | — | — | typing indicator (§6) |
| Checkbox/switch | well | inset | ring | `accent` fill | flat | — |
| Progress | inset track + `accent` bar | — | — | — | — | — |

Copy/labels/Semantics are unaffected by the aesthetic (screen-reader experience identical to the cycle-26 spec §7.4).

## 6. Scales (re-judged for neumorphic softness)

- **Type:** cycle-26 §4.1 RETAINED VERBATIM (Roboto with the documented decision; display 28/w700 → micro 11/w500; `bodyChat` 14.5 unchanged).
- **Spacing:** cycle-26 §4.3 RETAINED (xs 4 … xxl 32; usage rules unchanged).
- **Radius (re-judged — larger, softer):** chips 12 · buttons/inputs 16 · cards/tiles/FAB 20 · bubbles 24 (user tail 6 bottom-right; assistant tail 6 bottom-left) · dialogs 28 · bottom sheets 32 (top corners).
- **Elevation/motion:** cycle-26 §4.5 RETAINED (150/220/280 ms, `easeOutCubic`, no bounce; loops honor `disableAnimationsOf`). Depth transitions (shadow offset/blur, 150 ms) are the neumorphic press.

## 7. Per-screen treatment — FULL inventory (28 files; the cycle-26 spec §6 map, restated in the neumorphic language)

**Auth (Batch A):**
- `login.dart` — wordmark "AgentA" (`ink`, display) + "Sign in to continue" (`subtext`); fields = input wells (§4); Sign In = PrimaryButton (`accent` raised, loading inset-spinner, `Icons.login` leading — C28-P4); Google/fingerprint/Create Account = secondary raised with `subtext` icons; "Forgot Password?" = `accentInk` TextLink; error box = raised + `errorText` icon/text + "Show details" TextLink; `_GoogleConfigBanner`/`_StorageUpgradeNotice` = raised banner + `warningText` icon/text.
- `register.dart` — same header/fields; `_RecoveryCodeDialog` = raised dialog, code in inset well, `accentInk` mono 24 ls-4; offline note = raised + `warningText`; "shown once" = `errorText` 12.
- `forgot_password.dart` — three stages; all hardcoded colors → tokens; success = `successText` icon/text; `_ErrorBox` = `errorText`; `_ResetHeader` medallion → plain `lock_reset` `accent` 24; OTP field = inset well (20/ls-8 mono stays); Resend = `accentInk` TextLink.

**Chats (Batch B):**
- `chats.dart` — snackbar per §5.10-equivalent (inverse M3 retained); no structural change.
- `widgets/message_bubble.dart` — user = `accent` raised (tail 6); assistant = `base` raised; **the amber glow and assistant shadow are DELETED (N5)**; markdown: links `accentInk`, inline code = inset well + `ink`, code blocks = inset well radius 12 + `ink` mono 13, blockquote = italic `subtext` (the 2px rule DROPPED — depth replaces it); copy affordance 48dp `subtext`.
- `widgets/chat_input_bar.dart` — bar on `base`; field = inset pill (h16/v12); SendButton per cycle-26 states, raised→inset press; stop = `error` fill.
- `widgets/chat_screen_app_bar.dart` — `base` (no border), model line `micro` `subtext`, tune icon `ink`.
- `widgets/chat_timeline_view.dart` — loading spinner `accent`; empty = raised EmptyState (icon `subtext` 40, no tinted circle).
- `widgets/model_picker_sheet.dart` — raised sheet radius 32-top; tiles: selected = inset + `accent` check + `accentInk` w600; unselected = flat + `subtext`; disabled = flat + `disabledText`.
- `widgets/typing_indicator.dart` — `base` raised bubble; dots `subtext`; keep disable-animations.
- `widgets/image_bubble.dart` — raised; placeholder = inset well; radius 20.
- `widgets/auto_retry_image.dart` — placeholder inset; spinner `accent`; Retry/"Try HD" `accentInk` TextLinks.
- `widgets/animated_bubble.dart` — no change (motion-compliant).
- `widgets/chat_activity_state.dart` — no change (no visual surface).

**Dashboard / profile / download / shared (Batch C):**
- `dashboard/dashboard.dart` — raised tiles (radius 20), date `micro` `subtext`; stale banner = raised + `warningText` icon/text + tappable; dismiss background = `errorText`-family fill + white icon (semantic action); empty/error = raised EmptyState + Retry; FAB = `accent` raised extended; delete dialog = raised, confirm = filled `error`.
- `profile/profilepage.dart` — avatar = inset circle + `accentInk` initials; tiles = raised, icons `subtext`; Sign Out = raised destructive (`errorText` label); dialog raised.
- `profile/editprofile.dart` — fields = wells; Save = PrimaryButton (loading); avatar per above; snackbars inverse-M3.
- `profile/change_pass_page.dart` — fields = wells; error inline `errorText`; Save = PrimaryButton.
- `profile/securitypage.dart` — tiles raised, icons `subtext`, delete row `errorText`; dialogs raised.
- `profile/securityservice.dart` — no visual surface.
- `profile/confirmation.dart` — `key` icon `accent` 48 plain; field = well; Verify = PrimaryButton.
- `ai/download_prompt_screen.dart` — title `display`; `smart_toy_outlined` `subtext` 56; size chip = inset well; progress = `accent` on inset track; completion `check_circle` `successText` 48; slow/no-connection = raised + `warningText`/`errorText` icon+text.
- `shared/app_shell.dart` — no change beyond tokens.
- `shared/bottomnavbar.dart` — `base` bar, NO shadow line; selected = inset pill + `accent` icon + `accentInk` w600 label; unselected flat `subtext`; ≥48dp targets.
- `shared/offline_model_banner.dart` — **both banners rebuilt as the raised StatusBanner** (semantic icon + text; SyncingBanner = `accent` spinner + `ink` text — permanently fixing the white-on-light defect); left-border panels deleted (N4).
- `shared/update_available_dialog.dart` — raised dialog radius 28; plain `accent` icon 28 (no tint circle); Update = PrimaryButton (→ the C28 in-app flow when WS-UPD lands); Later = `accentInk` TextLink.
- `shared/update_dialog_host.dart` — scrim whitelisted; no change.
- `shared/system_keyboard_text_field.dart` — `Brightness.light` retained.

## 8. Accessibility notes

1. All ink ≥4.5:1 on `base` — computed in §3 (`ink` 12.3, `subtext` 5.9, `accentInk` 7.9, semantics 5.2–7.2). No grey-on-grey text.
2. Non-text contrast (SC 1.4.11): focus rings and selected controls use `accent` (4.05:1 ≥ 3:1 vs base). Resting well boundaries pair with the inset depth + label affordance.
3. The neumorphism critique is answered structurally: **depth is never the only state channel** (§5 table); disabled is exempt-but-identifiable (flat + `disabledText`).
4. Tap targets ≥48dp; icon-only controls keep Semantics/tooltip labels (the cycle-26 D1 rule carries forward).
5. Status = icon + text, never color-only. Screen-reader semantics identical to the cycle-26 spec.
6. Text scaling: the cycle-26 §7.7 patterns carry forward (scroll + ellipsis; verify at 1.3×/2.0× during P3 review).
7. Motion honors `disableAnimationsOf` (carried; N9).

## 9. Implementation practice

- **Hand-rolled tokens; zero new dependencies.** `flutter_neumorphic` REJECTED (unmaintained — §0.2). The shadow pair lives in `AppColors` (`shadowLight`/`shadowDark`) with the recipes as `AppShadows` helpers in `app_theme.dart` (raised/inset/well/flat) — retheme, not fork.
- `ThemeColors` becomes the flat neumorphic palette (§3 names); the `context.select` consumption pattern is retained; the withOpacity helper is retained where a scrim needs it.
- Grep gates carried forward: N1/N2/N3/N7 enforced at P3-review and the final sweep (`lib/` scope, `app_theme.dart` exempt).
- ui-reference reject-list reconciliation: Roboto = documented decision; the grey `base` = the style's defining constraint with ink contrast computed (12.3:1 — the "low-contrast grey body text" tell does not apply); no one-radius, no gradients, no glassmorphism, no tinted circles, no institutional identity.

## 10. Ratification

| Step | Status |
|---|---|
| Designer deliverable | this document |
| Adviser ratification | **RATIFIED 2026-10-18** — with one required change applied at ratification: §2a (light-only mechanics retained) was missing from the delivered draft (the delegation required it; the deliverable summary's claim "deleted in spec §2" was inaccurate) — added by the Adviser, plus a §3 clarification ("on base" = any base-colored surface, wells included). All AA math re-verified against independently computed luminance values; all delegation-required sections otherwise present. |
| User aesthetic confirmation (post-v1.3.1-install or written waive) | **RECORDED 2026-10-18/19** — the user installed v1.3.1 ("yes ive installed the latest") — which is also the cycle-27 device proof (the dialog fired: "yes it appears") — and confirmed the direction: "i wanted the ui like the neumorphism design" + "switch to neumorphism while keeping white theme" (**interpreted per this ratified spec: light-only neumorphism on the light base — no dual-theme switcher reintroduced**; the light-only greps held at 0 through P2–P7). "dont ask do it auto" = the update flow minimizes prompting to the download + handoff; **Android itself shows exactly ONE system Install confirmation per update — no app can remove it** (platform limit, on record). |
| Implementation start (P2/P4) | **EXECUTED** — the gate was satisfied on the user's recorded confirmation mid-implementation; the completion is verified (292/292, P7 PASS, Reviewer 10/10). |
