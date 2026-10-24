# AgentA UI Redesign — Design of Record (Cycle 26, P0)

**status:** active — approved by Adviser 2026-10-16
**owner:** designer
**mandate:** user-judged "the UI is full of AI slop — redesign completely, white theme, modern style" (changing is a must). Source of truth: `plans/cycle-26-ui-redesign.md`.
**scope:** every screen under `lib/presentation/` (28 dart files, nothing grandfathered) + the theme carrier `lib/theme/app_theme.dart` / `lib/cubit/theme/theme_cubit.dart` (retheme, not fork).
**phase:** P0 spec only — no code in this phase. Phases 1–3 (frontend) implement from this document deterministically.

---

## 0. Web-research declarations (per `.opencode/skills/web-research/SKILL.md`)

1. **Material 3 color system + light-theme guidance**
   - `search: done - M3 color roles, surface containers, fromSeed light scheme, M3 component specs`
   - sources: Flutter `ColorScheme` API docs (primary — documents the 45 M3 color roles, `on`-color ≥4.5:1 pairing, tone-based surface containers replacing elevation overlays, `ColorScheme.fromSeed(brightness: Brightness.light)`): https://api.flutter.dev/flutter/material/ColorScheme-class.html ; component-spec corroboration via the Component Gallery index of Material 3 button/card specs: https://component.gallery/components/button
   - `unverified`: the m3.material.io pages themselves (`/styles/color/system/overview`, `/foundations/design-tokens/overview`) are JavaScript-gated and could not be fetched directly; M3 facts used here are taken from Flutter's API docs, which implement the M3 spec.

2. **Flutter contrast / accessibility for WCAG AA on white**
   - `search: done - Flutter accessibility release checklist, WCAG 2.2 SC 1.4.3 contrast minimum`
   - sources: Flutter docs *Accessibility* (contrast ≥4.5:1, 48×48 tappable targets, screen-reader legibility, no automatic context switching, colorblind/grayscale usability, large text-scale factors): https://docs.flutter.dev/ui/accessibility.md (fetched as markdown, Flutter 3.47-era docs) ; W3C *Understanding SC 1.4.3 Contrast (Minimum)* (4.5:1 normal text, 3:1 large text ≥24px or ≥18.5px bold, disabled components exempt, placeholder text is text, updated 2026-09-06): https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html

3. **Current token-driven mobile design-system practice (restrained UI, no decorative gradients/blur)**
   - `search: done - token-driven design systems index, restrained component practice`
   - sources: Component Gallery button index (118 token-driven systems surveyed; mobile-native examples used as product-category matches: Wise Design mobile, Backpack mobile, Visa mobile): https://component.gallery/components/button
   - `unverified`: individual system pages (m3.material.io, wise.design) were not fetched directly (JS-gated); the practice claims (single accent, container-tint semantics, borders-over-shadows, restrained elevation) are corroborated by the fetched Flutter M3 API docs and WCAG sources above.

**Codebase reads (internal facts — from code, never the web):** all 28 files under `lib/presentation/`, `lib/theme/app_theme.dart` (287 lines), `lib/cubit/theme/theme_cubit.dart` (63 lines), plus repo greps for gradients/blur/emoji/raw `Colors.*` and theme-switch call sites. Findings are cited inline below.

---

## 1. Design principles

1. **White and light, only.** Light is the sole theme. White first: cards and sheets are `#FFFFFF` on a `#FAFAFA` canvas; color appears only where it has a job.
2. **One accent.** A single accent color carries all primary action, selection, focus, and links. No secondary/tertiary accents, no duotone chips, no rainbow semantics.
3. **Color has a job.** Accent = action/selection/focus/link. Semantic = status only (success/warning/error). Neutral = everything else. No color applied as decoration (the current app tints nearly every icon, circle, and chip amber — that is the slop).
4. **Borders over shadows.** Structure comes from 1px hairlines and tonal fills, not glows. Elevation is reserved for the FAB and M3 overlay components.
5. **Typography does the hierarchy.** Weight and size from one type scale; no letterspacing tricks, no gradient text, no decorative type.
6. **Honest states.** Every interactive element specifies default/pressed/focused/disabled/loading; every list specifies loading/empty/error. No fake affordances.
7. **Proper copy.** All user-facing strings: correct English, sentence case, no raw errors, no emoji. (The plan's example slop string "Like you want to update?" no longer exists in the repo — verified by grep — and the rule stands as a gate for any string touched in Phases 2–3.)

### 1.1 Anti-slop rules (binding on the spec, Phases 1–3, and the Reviewer's P3 grep gate)

| # | Rule | Current-repo evidence |
|---|---|---|
| A1 | **No decorative gradients.** Zero `LinearGradient`/`RadialGradient`/`SweepGradient` under `lib/`. | grep: 0 occurrences today — keep at 0 |
| A2 | **No glassmorphism / backdrop blur.** Zero `BackdropFilter`/`ImageFilter.blur` under `lib/presentation/`. | grep: 0 occurrences today — keep at 0 |
| A3 | **No emoji in UI chrome.** Material icons only (`Icons.*`). Zero emoji/symbol glyphs in `Text` literals. | grep (surrogate-pair scan): 0 occurrences today — keep at 0 |
| A4 | **No colored left-border panels.** The strongest single generated-UI tell (per `ui-reference` reject list). Three exist today: dashboard stale banner, `OfflineModelBanner`/`_StatusBanner`, `SyncingBanner` — all replaced by the `StatusBanner` component (§6.7). | `dashboard.dart:433`, `offline_model_banner.dart:146` (+206), markdown blockquote in `message_bubble.dart:83,145` (whitelisted, see §1.2) |
| A5 | **No decorative shadows/glows.** Remove the user-bubble amber glow and assistant-bubble shadow; remove the bottom-nav `BoxShadow`; borders and fills carry structure. | `message_bubble.dart:34-54`, `bottomnavbar.dart:113-119` |
| A6 | **ONE accent, used sparingly.** Accent appears only on: primary buttons, selected states, focus rings, links, progress. Icons default to neutral ink/subtext, not accent. | today ~every icon/chip/banner is amber |
| A7 | **All color via tokens.** Zero raw `Colors.*` / hardcoded `Color(0x…)` in `lib/presentation` except the whitelisted scrim (§1.2). Fixes today's 61 raw usages (e.g. `forgot_password.dart` `0xFF00C853`/`0xFFE53935`, `change_pass_page.dart:175` `Colors.amber`, `editprofile.dart` `Colors.green/red`, `message_bubble.dart` `0xFFE0E0E0`). | grep: 61 matches |
| A8 | **Differentiated radii.** No single radius across every element type. See scale (§4.2). | today buttons/inputs/cards all share 12 |
| A9 | **Restrained motion.** Fade/slide only, ≤280ms, `Curves.easeOutCubic`; no bounce/elastic; honor `MediaQuery.disableAnimationsOf` (already implemented in `animated_bubble.dart`/`typing_indicator.dart` — keep). | existing `AppDurations` |

### 1.2 P3 grep-gate whitelist (the ONLY exceptions)

| Pattern | File | Reason |
|---|---|---|
| `Border(left: BorderSide(color: <border token>, width: 2))` | `message_bubble.dart` markdown `blockquoteDecoration` only | semantic markdown blockquote marker (typographic convention, not a slop panel); neutral border color, 2px — not a colored panel |
| `Colors.black54` (dialog scrim) | `update_dialog_host.dart:86` | scrim semantics, not surface color; M3-standard scrim |
| `Colors.white` (icon on destructive filled button) | dialogs' destructive confirm only | `onError` token equivalent where a static const is required |

Everything else must come from `AppColors`/`ThemeColors`. Gate commands (P3 — **widened to `lib/` by Adviser amendment 2026-10-16**; the token definitions in `lib/theme/app_theme.dart` and this closed whitelist are the only exclusions):

```
rg -n "LinearGradient|RadialGradient|SweepGradient|BackdropFilter|ImageFilter\.blur" lib/
rg -n "Border\(left: BorderSide" lib/                       # only message_bubble blockquote allowed
rg -n "(^|[^p])Colors\.(amber|red|green|blue|orange|redAccent|grey)" lib/   # zero raw Colors.*; AppColors.<token> is the token layer
rg -n "Color\(0x" lib/ --glob "!lib/theme/app_theme.dart"  # zero outside the token definitions
```

Emoji scan: any surrogate-pair or dingbat-range glyph inside a `Text(...)` literal = fail.

---

## 2. Light-only mechanics (removal of dark + theme switch)

- `AppTheme`: **delete `darkTheme`**, delete all `dark*` colors, delete `darkColorScheme`. `lightTheme` becomes the app theme; `MaterialApp.theme` is the only theme.
- `main.dart` (Adviser correction 2026-10-16): the two `darkTheme: AppTheme.darkTheme` MaterialApp call sites (`:349`, `:477`) are removed in P1 — compile-level detachment only. The `themeMode: ThemeMode.dark` lines remained untouched in P1 (outside the delegated scope; functionally inert without a `darkTheme` — SDK `material/app.dart:1011`) and were **removed in Batch C (§6.4)**.
- `ThemeColors`: loses `isDark` and every `isDark ? … : …` branch; becomes a flat light palette (§3). All `background/surface/card/input/text/subtext/border/accent/success/error/warning` getters return constants. `withOpacity` helper stays.
- `ThemeCubit`: initial state `ThemeState.light()`; **remove `ThemeState.dark()`, `toggleDarkMode`, `setDarkMode`**. Verified by grep: no call sites for `toggleDarkMode`/`setDarkMode`/`ThemeState.dark()` outside `theme_cubit.dart` itself — removal breaks nothing. The cubit shell (and `state.colors` consumed via `context.select` in every screen) is retained to keep Phase 2 diffs mechanical.
- `system_keyboard_text_field.dart`: `keyboardAppearance: Brightness.light` (currently `MediaQuery.platformBrightnessOf` — under a dark system theme it would raise a dark keyboard over a light app; force light).
- No settings screen exposes a theme switch today (verified: none in inventory); nothing else to remove.

---

## 3. Color tokens (light palette)

Named on the existing carrier classes (`AppColors` + `ThemeColors`); hex is normative. All text-on-token pairs below are computed per the WCAG relative-luminance formula (§0 source 2) and pass AA unless marked otherwise.

### 3.1 Neutrals

| Token | Hex | Usage | Contrast |
|---|---|---|---|
| `background` | `#FAFAFA` | Scaffold behind scrollable content | — |
| `surface` | `#FFFFFF` | App bars, bottom nav, sheets, snackbar | — |
| `card` | `#FFFFFF` | Cards, tiles, bubbles, dialogs | — |
| `input` | `#F1F3F5` | Filled text fields, icon-chip rest state, image placeholders, code blocks | subtext on it 5.4:1 |
| `border` | `#E2E5EA` | 1px hairlines: card outlines, dividers, sheet handles, blockquote rule | decorative (no 3:1 duty) |
| `inputBorder` | `#D5DAE0` | 1px resting input/outline-button border | affordance = fill + label; focus ring carries the 3:1 duty |
| `text` | `#111827` | Primary text, icons | ~17:1 on white |
| `subtext` | `#5B6472` | Secondary text, hints, icons, timestamps, typing dots | 6.0:1 on white, 5.7:1 on background, 5.4:1 on input |
| `disabledText` | `#9AA1AA` | Disabled labels (exempt from AA per WCAG 1.4.3) | ~2.9:1 (exempt) |
| `scrim` | `#000000 @ 54%` | Dialog barriers | M3 standard |

### 3.2 Accent (the ONE accent)

Deep indigo replaces amber as the app accent. Amber `#FFC107` cannot pass AA as text/ink on white (≈1.6:1) and its tint-everywhere usage is the current slop; indigo keeps a modern identity while meeting AA on white. *(Flagged decision — see §12.)*

| Token | Hex | Usage | Contrast |
|---|---|---|---|
| `accent` | `#3D5AFE` | Primary button fill, links, selected checks, progress, focus rings, FAB | 5.1:1 on white (AA normal text) |
| `onAccent` | `#FFFFFF` | Text/icons on `accent` | 5.1:1 (AA) |
| `accentContainer` | `#E8ECFF` | Selected nav pill, selected model tile, icon chips, status-tint banners, user-bubble container alternative | — |
| `onAccentContainer` | `#2A3990` | Text/icons on `accentContainer` | 8.5:1 (AA) |

### 3.3 Semantic (status only — never decoration)

| Token | Hex | Container | On-container | Contrast (text form on white) |
|---|---|---|---|---|
| `success` | `#1B7F3B` | `#E6F4EA` | `#146C2E` | 5.1:1 |
| `error` | `#C62828` | `#FCE8E8` | `#8C1D1D` | 5.6:1 |
| `warning` | `#9A6700` | `#FFF4D6` | `#7A5200` | 4.9:1 |
| `info` | — | — | — | **deleted**; informational states use `accentContainer`/`onAccentContainer` (one-accent rule) |

Rules: semantic text always uses the strong form (`success`/`error`/`warning`) on white or the container's on-color; containers appear only in `StatusBanner`, input error helper, and the recovery-code dialog offline note. Error fill (`#C62828`) is allowed **only** on destructive confirm buttons and the chat stop button, with `#FFFFFF` content.

### 3.4 Gradient/overlay rules
No gradient tokens exist. Opacity-of-accent tints (`amber @ 0.12` etc., ~30 current usages) are **replaced by the container tokens** — never alpha-composite accent ad hoc. If a tint is needed and no container token exists, add a token; do not inline `withValues(alpha:)`.

---

## 4. Foundations

### 4.1 Type scale (one scale; carrier: `AppTypography` new class or `TextTheme` in `AppTheme.lightTheme`)

Font: **Roboto retained** (platform-native on Android, zero new assets, Phase 1 stays CHEAP). The tell in the reject list is *default type with no decision behind it*; the decision here is documented: Roboto + deliberate weight/size hierarchy. *(Flagged — §12.)*

| Role | Size/weight | Line-height | Used for |
|---|---|---|---|
| `display` | 28 / w700 | 1.2 | auth headers, empty-state headers, download title |
| `title` | 20 / w700 | 1.25 | dialog titles, sheet title, card section headers |
| `subtitle` | 16 / w600 | 1.3 | app-bar title, list-item titles (chat tile 15/w600 may stay for density) |
| `body` | 14 / w400 | 1.45 | body copy, buttons (w600), list secondary |
| `bodyChat` | 14.5 / w400 | 1.45 | chat bubble text (unchanged size — avoids chat relayout) |
| `label` | 13 / w500 | 1.4 | banner text, helper text, list secondary |
| `labelSm` | 12 / w500 | 1.3 | timestamps, chips, hints, banner subtext |
| `micro` | 11 / w500 | 1.2 | nav labels, chat app-bar model line, dates |

### 4.2 Radius scale (differentiated — anti-slop A8)

| Token | Value | Applies to | Reason |
|---|---|---|---|
| `sm` | 8 | inline chips, small badges | tightest inline elements |
| `md` | 12 | buttons, inputs, banners, icon chips, snackbar | control radius — controls read tighter than containers |
| `lg` | 16 | cards, tiles, image bubbles, FAB | container radius |
| `xl` | 20 | chat bubbles (4px tail corner), dialogs | speech/dialog radius |
| `xxl` | 24 | bottom sheets (top corners only) | sheet radius |

Bubble tails (keep): user bubble 4px bottom-right; assistant bubble 4px bottom-left — a deliberate chat affordance, not uniformity.

### 4.3 Spacing scale (values unchanged; usage normalized)

`xs 4 / sm 8 / md 12 / base 16 / lg 20 / xl 24 / xxl 32` (existing `AppSpacing`). Usage rules:
- **List screens** (dashboard): page padding `base` (16).
- **Settings/profile** pages: page padding `lg` (20).
- **Auth/form screens**: horizontal padding `xl` (24) — replaces today's off-scale 28.
- Card internal padding `base`; list-item vertical `md`; input padding h16/v14 (chat pill: h16/v12).
- Component gaps: title↔body 8, between tiles 12, section gap 24, hero gap 32.

### 4.4 Elevation (restrained)

| Surface | Elevation | Separation |
|---|---|---|
| App bars, bottom nav, cards, tiles, bubbles | 0 | 1px `border` hairline |
| Bottom sheets | 0 | scrim + top hairline; no shadow |
| Dialogs | M3 default | scrim |
| FAB | 3 | M3 default |
| SnackBar (floating) | M3 default | — |
| Removed | user-bubble glow, assistant-bubble shadow, bottom-nav `BoxShadow` | (A5) |

### 4.5 Motion

Keep `AppDurations`: quick 150ms (taps/state), standard 220ms (container transitions), entrance 280ms (list entrance, `Curves.easeOutCubic`). No bounce/elastic; entrance = fade + ≤16dp slide; all loops (typing dots) honor `disableAnimationsOf` (already in `typing_indicator.dart`, `animated_bubble.dart` — keep).

---

## 5. Component inventory & states (shared)

Every component lists its required states. `pressed` = InkWell default ripple on `surface`/`card`; `focus` = 2dp `accent` outline offset 2 (visible for keyboard/stylus; mobile shows pressed).

1. **PrimaryButton** — `accent` fill, `onAccent` label (`body` w600), radius `md`, height 52, full-width in forms.
   States: default / pressed (11% onAccent overlay) / **loading** (20dp `onAccent` spinner, label removed, onPressed null) / disabled (`input` fill, `disabledText` label) / destructive variant = `error` fill + white.
2. **OutlinedButton (secondary)** — transparent fill, 1px `inputBorder`, `text` label w600, radius `md`, height 52.
   States: default / pressed (4% text overlay) / disabled (`disabledText`, `border`) / leading icons `subtext` (not accent).
3. **TextLink** — `accent`, `body`, underline on press only; min tap target 48×48 via padding.
4. **TextField** — filled `input`, 1px `inputBorder`, radius `md`, h16/v14; label above field (`label` w600 `text`) or floating per existing screens; prefix/suffix icons `subtext` 20.
   States: default / focused (1.5px `accent`) / error (1.5px `error` + helper `error` 12) / disabled (`disabledText`, `input`) / with-suffix (visibility toggle, `subtext`).
5. **ListItemTile** — `card` fill, 1px `border`, radius `lg`, padding 16; leading icon `subtext` (destructive: `error`); title `subtitle`; trailing chevron `subtext`. States: default / pressed (4% ink overlay) / disabled.
6. **Card** — `card` fill, 1px `border`, radius `lg`, elevation 0. States: default / pressed (for tappable cards).
7. **StatusBanner** — replaces every colored left-border panel. Full-width, semantic-container fill, radius `md` (inline) or 0 (flush under app bar), padding h16/v8-12; leading semantic icon 16–18; primary line `label` in `text`; optional subtext `labelSm` in `subtext`; optional trailing chevron (semantic). Four variants: success/warning/error/accent. States: static or tappable (pressed overlay).
8. **Dialog** — `surface`, radius `xl`, padding 24; leading icon `accent` 28 (no tinted circle); title `title` `text`; body `body` `subtext`; actions right-aligned TextButtons (destructive = `error` text or filled `error` button).
9. **BottomSheet** — `surface`, top radius `xxl`, drag handle 40×4 `border`, title `title` centered; scrim `scrim`.
10. **SnackBar (floating)** — inverse M3 pattern retained (dark fill on light app) for global feedback; content `onInverse`; action `inversePrimary`. Semantic snackbar colors (`Colors.green/red/amber` today) are removed — feedback color lives in copy + optional leading icon.
11. **EmptyState** — centered: Material icon 40 `subtext`, title `title` (or `display` on auth-hero contexts) `text`, body `body` `subtext`, optional action (PrimaryButton small or TextLink). **No tinted circles** (removes today's amber circles on dashboard/chats/empty states).
12. **BottomNav** — `surface`, top 1px `border`, no shadow; 2 items (Home, Profile). Item: icon 24 + `micro` label. States: **selected** (pill `accentContainer`, icon+label `onAccentContainer`, w600) / unselected (`subtext`) / pressed. Tap target ≥48h.
13. **AppBar** — `surface`, elevation 0, bottom hairline 1px `border`; title `subtitle` centered; back icon `text` 20.
14. **FAB (extended)** — `accent` fill, `onAccent` icon+label, radius `lg`, elevation 3, label `body` w600. States: default/pressed/disabled.
15. **ChatBubble (user)** — `accent` fill, `onAccent` text `bodyChat`, radius `xl` (tail 4 bottom-right), max width 75%. States: default / streaming (text updates; no visual pulse) — **no glow shadow**.
16. **ChatBubble (assistant)** — `card` fill, 1px `border`, radius `xl` (tail 4 bottom-left), text `text`. Markdown: links `accent` underline; inline code `input` bg + `text`; **code block** `input` bg + `border` radius `sm` + monospace 13 `text` (replaces `0xFFE0E0E0`); blockquote 2px `border` left rule + italic `subtext` (whitelisted §1.2); headings per type scale. Copy affordance: 48×48 IconButton, icon `subtext` 16, tooltip "Copy message" (fixes today's 32×32 target vs 48dp a11y rule).
17. **ImageBubble** — square `input` placeholder → image radius `lg`; caption "Generated image" `labelSm` `subtext` on load. Loading: indeterminate 24 accent / progress 2dp accent; error: `broken_image` `subtext` + Retry TextLink + optional "Try HD version" TextLink (`accent`).
18. **TypingIndicator** — assistant-bubble shape, `card` + border; 3 dots 7dp `subtext` at animated opacity (decorative — subtext, not accent); text variants ("Generating response", "Initializing model...", "Generating your image") `label` `subtext`.
19. **ChatInputBar** — `surface` + top hairline; pill field `input` radius 20 (matches bubble radius — deliberate), h16/v12, multiline max 120h; hint "Ask AgentA..." `subtext`.
20. **SendButton** — 48×48, radius 16. States: idle-hidden (`input` fill, `subtext` icon) / ready (`accent` fill, `onAccent` send icon) / **stop** (`error` fill, white stop icon) / disabled (idle look, onPressed null).
21. **Avatar** — initials on `accentContainer`, `onAccentContainer` `display`; sizes 100 (profile) / 40 (icon chips).

---

## 6. Per-screen treatment — FULL inventory (28 files + the 3 `lib/main.dart` boot surfaces in §6.4, Adviser amendment 2026-10-16)

Legend: **→** = change required. All token references are §3/§4/§5.

### 6.1 Auth (Phase 2, Batch A)

| File | Current (verified) | Treatment |
|---|---|---|
| `auth/login.dart` | Amber tinted-circle bolt logo; amber prefix icons; amber-focused borders; amber links; tinted warning banners; `Colors.black` spinner on amber | Wordmark "AgentA" (`display`) + "Sign in to continue" (`subtitle` in `subtext`), **no icon medallion**; labels `label`; fields per TextField spec (§5.4); "Forgot Password?" TextLink; error box → semantic error container + `error` text + "Show details" TextLink; primary Sign In (loading state §5.1); Google + fingerprint + Create Account as OutlinedButtons with `subtext` icons; `_GoogleConfigBanner`/`_StorageUpgradeNotice` → StatusBanner (warning/accent variant). Diagnostics dialog → Dialog spec (title + rows, `label`/`body`). |
| `auth/register.dart` | Same amber medallion; amber icons; recovery-code dialog with amber-tinted code box, warning/confirmEmail tinted rows | Header per login; fields per TextField; error box → error container; primary Create Account (loading); "or" divider in `border`; "Sign In" TextLink. `_RecoveryCodeDialog` → Dialog spec; recovery code in `accentContainer` box, `onAccentContainer` mono 24 letterspacing 4; offline note → StatusBanner warning; "shown once" note `error` 12. |
| `auth/forgot_password.dart` | Hardcoded `0xFF00C853`/`Colors.green` success boxes, `0xFFE53935` error box, amber icons/links, tinted circles | Three stages keep structure; all hardcoded colors → tokens: success box → success container + `success` text; `_ErrorBox` → error container + `error`; `_ResetHeader` medallion → plain `lock_reset` icon `accent` 24 beside title; OTP field per TextField (20/ls8 mono style stays); Resend TextLink; primary buttons per §5.1. |

### 6.2 Chats (Phase 2, Batch B)

| File | Current | Treatment |
|---|---|---|
| `chats/chats.dart` | Amber spinners/snackbars; logic otherwise sound | Colors only: snackbar per §5.10; "Get model" SnackAction. No structural change (delegates to widgets). |
| `widgets/message_bubble.dart` | User bubble amber 0.9 + **amber glow shadow**; assistant shadow; hardcoded markdown colors (`0xFFE0E0E0`, `0xFF757575`, amber blockquote rule, `Colors.amber` links); 32×32 copy target | User bubble = `accent` fill + `onAccent` (§5.15, glow removed); assistant = `card` + border (shadow removed); markdown stylesheet → tokens (§5.16); blockquote rule → `border` 2px (whitelisted); copy button 48×48 `subtext` icon. |
| `widgets/chat_input_bar.dart` | Amber send button, `Colors.black` icon, transparent-border pill | SendButton states (§5.20); field per §5.19; bar top hairline `border`. |
| `widgets/chat_screen_app_bar.dart` | Model name in amber 11 (fails contrast) | AppBar spec (§5.13); model line `micro` in `subtext`; tune icon `text`. |
| `widgets/chat_timeline_view.dart` | Amber spinner; empty state amber tinted circle + bolt | Loading placeholder: 40dp spinner `accent` + "Loading messages..." `body` `subtext`; empty → EmptyState (icon `chat_bubble_outline` `subtext` 40, title "Start the conversation", body unchanged); entrance animation per §4.5 (keep). |
| `widgets/model_picker_sheet.dart` | Amber selection text/check; border-alpha icon chips | Sheet per §5.9 (title "Select AI Model" `title`); tiles: selected → `accentContainer` leading chip + check `accent` + title `subtitle` `text` w600 (selected text stays **ink**, not accent); unselected icon chip `input` + `subtext`; disabled `disabledText` + wifi_off; gemma-unready → download icon `accent` + subtitle "Download to use offline" `subtext`. |
| `widgets/typing_indicator.dart` | Amber dots (`AppColors.amber` direct) | Dots → `subtext` (decorative, A6); bubble per §5.18; text variants `label` `subtext`; keep disable-animations handling. |
| `widgets/image_bubble.dart` | OK structurally | Caption stays `labelSm` `subtext`; radius `lg`; no color change beyond tokens. |
| `widgets/auto_retry_image.dart` | Amber retry/spinner icons; `input` placeholders | Placeholders keep `input`; spinner `accent`; Retry/"Try HD version" TextLinks `accent`; error icon `subtext`. |
| `widgets/animated_bubble.dart` | Compliant (fade/slide/scale, disable-animations aware) | No change. |
| `widgets/chat_activity_state.dart` | Pure state, no UI | No change (no visual surface). |

### 6.3 Dashboard, profile, download, shared (Phase 2, Batch C)

| File | Current | Treatment |
|---|---|---|
| `dashboard/dashboard.dart` | **Amber left-border stale banner**; amber tinted circles on empty/error; amber icon chips + FAB; raw `Colors.red.shade400`/`Colors.white` dismiss bg; delete dialog error button | AppBar per §5.13 (logo 32 + "AgentA" `subtitle`); stale banner → StatusBanner (warning, tappable Retry); list tiles → Card + icon chip `accentContainer`/`onAccentContainer`, date `micro`; dismiss background → `errorContainer` + `error` delete icon; empty/error → EmptyState + Retry (PrimaryButton small); FAB per §5.14 ("New Chat"); delete dialog per §5.8 (destructive confirm = filled `error`). |
| `profile/profilepage.dart` | Amber avatar, amber tile icons, tinted sign-out dialog texts | Avatar per §5.21; tiles per §5.5 (icons `subtext`, chevron `subtext`); Sign Out → OutlinedButton destructive (`error` text + 1px `error` border); dialog per §5.8 ("Sign Out?" title, confirm = TextButton `error`). |
| `profile/editprofile.dart` | `Colors.green`/`Colors.red` snackbars; amber avatar/icons | Fields per TextField; avatar §5.21; Save = PrimaryButton (loading state); snackbars per §5.10 (no semantic bg colors). |
| `profile/change_pass_page.dart` | `Colors.amber` raw on button + snackbar; `Colors.redAccent` error text; amber icons | Fields per TextField; error inline → `error` `label`; Save = PrimaryButton; snackbar §5.10. |
| `profile/securitypage.dart` | Amber key icon; card tiles without borders; delete tile error text | Tiles per §5.5 (key icon `subtext`; delete row `error` text + `error` icon); "View Recovery Code" dialog per §5.8 (`key_off` `subtext`); delete-account dialog per §5.8 (confirm = TextButton `error`). |
| `profile/securityservice.dart` | Logic only (no widgets) | **No visual surface — no styling work.** Listed for inventory completeness. |
| `ai/download_prompt_screen.dart` | Amber robot icon 72; amber size chip; amber progress; `Colors.black` label; warning slow-connection box | Title "Download Offline AI" `display`; robot icon → `smart_toy_outlined` `subtext` 56 (neutral, A6); size chip → `input` fill + `subtext` `labelSm`; progress bar `accent` on `input` track; completion → `check_circle` `success` 48 + text; slow-connection → StatusBanner warning; no-connection → StatusBanner error; primary button per §5.1 (disabled while waiting = §5.1 disabled); "Use Online AI Instead" TextLink. |
| `shared/app_shell.dart` | Passthrough IndexedStack + nav | No change beyond tokens. |
| `shared/bottomnavbar.dart` | **BoxShadow + amber pills** | Remove shadow (A5); border-top hairline; selected pill `accentContainer` + `onAccentContainer` (§5.12); tap targets ≥48h. |
| `shared/offline_model_banner.dart` | **Hardcoded amber left border**; `SyncingBanner` uses `AppColors.textDark` (white text — broken on light) | Rebuild both as StatusBanner: online → success variant "Online — {model}"; limited → warning variant + disclaimer subtext; offline-ready → accent variant; offline-unready → error variant + "Tap to get the offline model." SyncingBanner → accent variant + 14dp `accent` spinner + `onAccentContainer` text. |
| `shared/update_available_dialog.dart` | Amber tinted-circle hero; dialog radius 16 | Dialog per §5.8 (radius `xl` 20; plain `system_update_alt`/`system_security_update_warning` icon `accent` 28, no tint circle); version line `subtitle`; release notes box `input` fill + `border` radius `md`, capped 160h scroll; Update = PrimaryButton; Later = TextLink. Copy already proper English — keep ("New version available" / "Update required"). |
| `shared/update_dialog_host.dart` | Host logic; `Colors.black54` scrim | No change (scrim whitelisted §1.2). |
| `shared/system_keyboard_text_field.dart` | Keyboard follows platform brightness | `keyboardAppearance: Brightness.light` (§2). No other change. |

---

### 6.4 Boot surfaces — `lib/main.dart` (Adviser amendment 2026-10-16)

Added to the inventory by the P1 ruling: these raw-color surfaces sat outside the original 28-file sweep (and outside the old `lib/presentation` gates). **Tokenization only** — colors/typography/copy; boot-critical logic (`_initializeApp`, `InitState`, routing) untouched.

| Surface | Current (verified, raw) | Treatment |
|---|---|---|
| `_AppLoader` splash | Navy canvas `0xFF1A1A2E`; gold `0xFFFFD700` robot, spinners, Retry buttons; `white`/`white70` text | Canvas `background`; robot/spinners `accent`; Retry = themed PrimaryButton (`accent`/`onAccent`); 'AgentA' wordmark `display` in `text`; 'Initializing...' `label` `subtext`; backend-failed `warning`, error `error`, ready `success`; 'Continue Offline' `subtext` |
| Google-config warning banner | `Colors.orange` tint + `0.4` border + orange icon/text | StatusBanner warning variant: `warningContainer`, `warning` icon 18, `label`/`text` (no border) |
| Offline-model gate screens | `0xFF0D0D0D` canvas; red icon, `white`/`white54` text; gold spinner/button; AuthGate loaders `0xFFFFC107` | Canvas `background`; icon `error`; 'Failed to load offline model' `subtitle`/`text`, body `labelSm`/`subtext`; spinners `accent`; Retry = themed PrimaryButton |

Also: the `MaterialApp` `themeMode: ThemeMode.dark` residues were removed — `theme` is the only theme (§2).

---

## 7. Accessibility notes (AA on white — binding)

1. **Contrast.** All body/label text ≥4.5:1 on its actual background (token table §3 states the computed ratios; `subtext` is the floor at 5.4:1 on `input`). Large text (≥24px or ≥18.5px bold) needs ≥3:1 — met everywhere by `text`/`onAccent`. Placeholder/hint text counts as text (WCAG 1.4.3) — hints use `subtext` (≥5.4:1), never light greys.
2. **Non-text contrast (SC 1.4.11).** Meaningful boundaries (focused input border, selected pill, progress bar) ≥3:1 — provided by `accent` (5.1:1). Resting input hairline is paired with fill+label affordance (M3 filled-field practice, §0 source 1).
3. **Tap targets.** ≥48×48 dp for all interactive elements (Flutter checklist): copy buttons (today 32×32 → 48), send button (48 ✓), nav items, visibility toggles, TextLinks via padding.
4. **Screen readers.** Every icon-only control keeps/gets a tooltip or `Semantics` label ("Copy message", "Send", "Stop", "Select model"). StatusBanner conveys state in text, not color alone (icon + label + subtext).
5. **Color independence.** Status is never color-only: banners have icons + text; selected tiles have check icons; destructive actions are labeled.
6. **Motion.** All loops/entrances honor `disableAnimationsOf` (already implemented; must be preserved).
7. **Text scaling.** Layouts use `SingleChildScrollView` + ellipsis patterns already present; verify at 1.3×/2.0× system font scale during P2 review — no fixed-height text containers except the release-notes scroll box.
8. **Disabled controls** are exempt from contrast (WCAG) but must remain visually identifiable (`disabledText` on `input`).

---

## 8. Copy rules (dialog/screen strings)

Proper English, sentence case, full sentences for explanations, no emoji, no raw exception text (raw detail stays in debug logs per `docs/error-hygiene.md` conventions already in the code). The plan's example ("Like you want to update?") no longer exists in the repo (grep-verified); the rule applies to every string Phases 2–3 touch. Standard pairs to keep consistent: "Couldn't load your conversations." / "Please try again." / "Image failed to load" / "Are you sure you want to delete this chat? This action cannot be undone."

---

## 9. Phase mapping (frontend execution order)

- **P1 — theme foundation:** implement §2 (light-only removal), §3 tokens, §4 scales, §5 component themes in `app_theme.dart` + `theme_cubit.dart`. Gates: analyze 0, suite green (tests may be adapted; record count).
- **P2 — batches:** A auth (3 files) → B chats (11 files) → C dashboard/profile/download/shared (14 files). Markup/spacing/colors only; any behavior change ⇒ reclassify EXPENSIVE per plan.
- **P3 — anti-slop sweep:** run §1.2 gates + emoji scan + copy pass; whitelist is closed (no additions without Adviser).

---

## 10. STOP-rule self-check (plan §Phase 0)

- Spec is white/light-only: **yes** — dark theme and switch removed (§2); no dark-mode content anywhere.
- No slop reintroduced: **yes** — gradients/blur/emoji banned with zero current occurrences to preserve; the three existing colored left-border panels are specified for removal; the amber-tint constellation is replaced by a single AA-passing accent.
- Violations found in current code are documented for removal, not carried forward (A4/A5/A7 rows cite file:line).

**No STOP condition hit.**

---

## 11. Verification (per plan: CHEAP — Adviser reviews this spec before P1)

Deliverable = this document. Recommended Adviser spot-checks: (1) §12 flagged decisions ratified or overridden; (2) §6 inventory rows count = 28 files matching `lib/presentation/**/*.dart`; (3) §1.2 whitelist acceptable as the P3 gate's only exceptions.

## 12. Flagged decisions (designer judgment calls — need Adviser ratification, none violate the plan)

1. **Accent swap: amber → deep indigo `#3D5AFE`.** The plan binds *ONE accent* but not *which*; amber (a) fails AA as ink on white and (b) is the identity of the slop being removed. Indigo keeps a modern identity and passes AA (5.1:1).
2. **Canvas `#F5F5F5 → #FAFAFA`.** Same neutral family, cleaner white-first read; not the reject-listed "cream" (it is neutral grey-white, no warm cast).
3. **Roboto retained.** Deliberate, documented (§4.1): platform-native, no new assets in a CHEAP phase; the type decision is the scale itself. Swapping fonts is a trivial follow-up if the Adviser wants one.
4. **Auth page padding 28 → 24** (on-scale); chat copy-button target 32 → 48dp (a11y checklist).

## 13. References used (ui-reference report)

- Flutter `ColorScheme` API docs — M3 roles, on-color pairing, surface containers, `fromSeed`: https://api.flutter.dev/flutter/material/ColorScheme-class.html *(layout/role model + contrast pairing)*
- Flutter Accessibility docs — release checklist (contrast, 48dp targets, screen reader, scale factors): https://docs.flutter.dev/ui/accessibility.md *(a11y constraints)*
- W3C WCAG 2.2 Understanding SC 1.4.3 (updated 2026-09-06) — AA thresholds, placeholder text, disabled exemption: https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html *(contrast math)*
- Component Gallery — token-driven systems index (mobile-category exemplars: Wise, Backpack, Visa): https://component.gallery/components/button *(component-state practice)*
- Reject-list patterns deliberately avoided (per `ui-reference` baseline): colored left-border panels (removed ×3), purple-blue gradients (none), one-radius-everywhere (differentiated §4.2), tinted-circle icon medallions (removed on auth/empty states), decorative glow shadows (removed), low-contrast grey body text (subtext ≥5.4:1), cream backgrounds (neutral `#FAFAFA`).
