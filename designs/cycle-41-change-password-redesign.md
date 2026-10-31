# Cycle 41 · P1 — Change-Password Redesign — Design Spec of Record

**Status:** draft for Adviser ratification (the §5-P1 GATE) — written 2026-10-31 by the designer.
**Phase:** plans/cycle-41-change-password-redesign.md §5-P1. The plan file is authoritative; where this spec quotes it, the quote is from the plan's §1/§4/§6.
**Consumed by:** P2 (frontend — the page rebuild), P3 (conditional, one comment-only service doc update), P4 (e2e pair), the Reviewer (grep criteria live in §12).

## 1. Problem, scope, boundaries

### 1.1 The problem being designed away

The user's directive (verbatim, the plan's §header): **"i dont want this type of change password"**, with the queued ask **"search for reliable and best practice for change password"**. The page of record is `lib/presentation/profile/change_pass_page.dart` (v1.8.1, HEAD `27ca470` — every anchor re-verified against the tree this session; see §12.4). The rejected experience is a three-factor maze (plan F1):

1. A form with **no why-copy** — nothing explains why the current password, a device prompt, or a code is asked for.
2. A **blocking emailed 6-digit code for BOTH online classes** (`change_pass_page.dart:248` — "The emailed 6-digit code is the mandatory final verifier for BOTH"), pausing the flow on a code-entry stage (`enum _ChangeStage { form, otpCode }`, `:153`).
3. A **device-credential prompt stacked on top** — in the shipped code the prompt runs after reauthentication and *before* the email send (`:245-251`; the `:246` no-waste comment exists precisely because a canceled prompt must not consume a send), so the felt sequence is *type → phone prompt → wait for email → type code* — three factors, none explained. (The plan's F1 narrative phrases the felt order prompt-last; the tree's actual order is as stated here — recorded as a report note, not a ground-truth conflict: every line-referenced plan fact verifies, and the plan's own `:246` fact carries the true order.)
4. A **terminal dead-end** when the device prompt is canceled: "Device confirmation was canceled. Your password was not changed." (`:327`, `:415`) — no retry, no explanation, no next step (F2).
5. The **numeric keyboard occluding the Change Password CTA** on the code stage (`:650`, no scroll-inset handling) (F3).
6. **No show-password toggle** on either password field (F6).

The plan's diagnosis (§1.2 synthesis): the security baseline (session + current-password reauthentication, bound authenticators) is **already met** by cycle-31's factor matrix; the blocking emailed code is an application-added hardening with a **narrow** security value (the phished-credential class) and the UX cost that triggered this cycle; NIST SP 800-63B-4 §3.1.3 prohibits email out-of-band secrets **as authentication**; OWASP's "Change Password Feature" baseline requires exactly session + current-password verification and prescribes "Minimize User Friction".

### 1.2 In scope (the plan's selected findings)

| Finding | This spec delivers |
|---|---|
| **F1** — the maze | One coherent, explained flow per account class (§3, §5, §6); why-copy on every step |
| **F2** — the dead-end | The cancel path becomes an inline retry-with-explanation (§7); the dead-end strings retire (§10.3) |
| **F3** — keyboard occlusion | The never-occluded-CTA rule (§8), satisfied on every stage |
| **F4** — the emailed step | The §4.3 ruling (§4), with the S2 baseline comparison recorded per path |
| **F6** — show-password | Show/hide on both password fields (§5.4), per NIST §3.1.1.2 "SHOULD offer an option to display the password" |

### 1.3 Out of scope (recorded, never silently added — plan S4)

- **F5 (NIST blocklist on change)** and **F8 (minimum-length policy)** are **policy changes** requiring a separate Adviser ruling. This spec does **not** add a blocklist, a strength meter, or a length change. The inline verification it specifies (§5.5) surfaces the **existing recorded policy** (≥6 characters) honestly; it does not invent a strength claim the app does not implement.
- **F7 (adjacent flows)** — see the boundary below.

### 1.4 The S3 boundary (binding)

The **forgot-password flow** (`login.dart` → `AuthService.sendOtpForReset`/`resetPasswordWithOtp`) and the **admin mandatory-change-code flow** (cycle-34) must emerge **byte-for-byte behaviorally unchanged**. They keep their blocking codes, their screens, their copy, and their use of the OTP template machinery ("Your AgentA verification code" — the cycle-34 template of record). This redesign touches **only** `change_pass_page.dart`, its widgets, its tests, and (comment-only, §12.2) one `auth_service.dart` doc comment. The Google-linked class's code stage **reuses** the same step-up machinery (`sendOtpForStepUp`/`verifyOtpStepUp`) with zero changes to it.

### 1.5 The S1 boundary (binding)

No design or test in this spec triggers a live email send beyond the user's own action. Every send in the redesigned flows is triggered by the user's submit or resend tap; tests exercise sends only through the `PasswordChangeFactorGate` fake (the recording fake-gate pattern already in `test/cycle31_p3_change_password_test.dart`). The e2e harness MUST NOT trigger real sends (the cycle-34 precedent).

## 2. Design system of record

The app's design system is `lib/theme/app_theme.dart` (the cycle-26 neumorphism spec, retained verbatim). This redesign **invents no tokens, no colors, no radii, no type sizes**. Every visual decision below is expressed in this vocabulary and P2 must consume it as-is.

### 2.1 Color (flat neumorphic, light-only, ONE surface)

| Token | Hex | Role on this page |
|---|---|---|
| `colors.base` | `#E0E5EC` | The only surface — scaffold, fields, cards, bars |
| `colors.ink` | `#1A2433` | Primary text: labels, titles, CTA-adjacent text |
| `colors.subtext` | `#4A5568` | Secondary text: why-copy, helper text, field icons |
| `colors.disabledText` | `#8B95A5` | Disabled CTA label |
| `colors.accent` | `#3D5AFE` | The ONE accent — fills (CTA), focus ring; **never small text** |
| `colors.onAccent` | `#FFFFFF` | CTA label, progress indicator on the CTA |
| `colors.accentInk` | `#2A3990` | Accent-colored **text** (text buttons only) |
| `colors.successText` | `#146C2E` | Success status ink (icon + text) |
| `colors.errorText` | `#8C1D1D` | Error status ink (icon + text, field errors) |
| `colors.warningText` | `#7A5200` | Notice ink (the notice box; the retry card icon) |

Rules inherited from the theme doc: status is **icon + text in the semantic ink on the neutral surface — never surface decoration** (no colored boxes/banners). AA contrast is pre-computed against `base`; no new color pairs are introduced.

### 2.2 Spacing, radius, shadow, motion

| System | Tokens | Use on this page |
|---|---|---|
| `AppSpacing` | xs 4 · sm 8 · md 12 · base 16 · lg 20 · xl 24 · xxl 32 | Page gutter `xl` (24, the page's existing value, retained); label→field `sm`; between groups `xl`; before CTA `xxl` |
| `AppRadius` | input/button `md` 16 · card `lg` 20 · dialog `xxl` 28 | Fields and CTA 16; the retry card 20 |
| `AppShadows` | `well` (inputs at rest) · `raised` (cards, CTA at rest) · `pressed` (active) · `flat` (disabled) | Fields = well; retry card and CTA = raised; disabled CTA = flat (theme handles fill) |
| `AppDurations` | quick 150 ms · standard 220 ms · entrance 280 ms, `easeOutCubic`, no bounce | State transitions (retry card in/out, toggle icon swap) |

### 2.3 Type scale (verbatim, retained)

| Style | Spec | Use |
|---|---|---|
| `AppTypography.title` | 20/w700, h1.25 | Stage headers ("Verification Code") |
| `AppTypography.subtitle` | 16/w600, h1.3 | Retry-card title, app bar title (theme) |
| `AppTypography.body` | 14/w400, h1.45 | Why-copy, explainers, retry-card body |
| `AppTypography.label` | 13/w500, h1.4 | Field labels (w600 at rest above fields, as today), notice/error text |
| `AppTypography.labelSm` | 12/w500, h1.3 | Helper text, resend countdown helper (theme's helper/error styles) |
| `AppTypography.button` | body @ w600 | CTA and retry-card button labels (theme-applied) |

### 2.4 Controls already themed (do not restyle)

`ElevatedButton` (min height 52, `buttonRadius`, accent/onAccent, disabled = `base` fill + `disabledText`), `TextButton` (min 48, `accentInk`), `InputDecorationTheme` (well at rest, no border; focused = accent 1.5; error = `errorText` 1.5; helper/error text styles pinned), `SnackBar` (floating, `snackbarRadius`). The shared `SystemKeyboardTextFormField` wrapper (force-light keyboard, `autofillHints` supported) is the field widget of record.

## 3. Per-account-class flows

Classification is unchanged from the shipped machinery: `PasswordChangeFactorGate.loadSession()` returns `PasswordChangeSession(email, isGoogleLinked, hasPassword)`; a **null session** (no Supabase user) routes to the offline flow. The class decides the chain; the user never chooses.

### 3.1 Local (never-synced) accounts — mechanics unchanged, presentation redesigned

**Invariant (plan §4.1): NO email, ever.** The row is the credential; the whole flow is on-device (`OfflinePasswordService.updateLocalPassword` — Argon2id verify, device credential, compare-and-swap write; zero Supabase imports).

| Stage | What the user sees | Why (grounding) |
|---|---|---|
| Enter | Form: **Current Password** + **New Password**, why-line under the page title (CP-02), CTA "Change Password" | OWASP baseline: current-password verification before a change |
| Submit → verify | Button → loading; wrong current password → **inline field error** (CP-10), values kept; lockout → chain-level error (CP-12a) | Rate-limiting duty (NIST §3.1.1.2); `OfflineLoginGuard` 5-attempt lockout reused unchanged |
| Device step | System prompt: "Confirm your identity to change your password" (the existing step-up wording, unchanged). **Pre-probed**: no screen lock → degrade **notice** (CP-14), never a block — the cycle-31 P1 fail-open policy | Possession factor; "Bound Authenticators" (OWASP) |
| Cancel on prompt | **The retry card replaces the dead-end** (§7): what happened, that nothing was saved, Try again / Back (CP-15…CP-17) | F2 fix; cycle-38 P6 recovery pattern applied to auth |
| Write + success | CAS write; success SnackBar (CP-18); pop to profile | Compare-and-swap never claims a false success (existing service contract) |

**Chain order pin (page-level):** `deviceCredentialPromptAvailable → updateLocalPassword` (the service internally orders verify → prompt → CAS, unchanged).

### 3.2 Cloud email+password accounts — one progressive form, code stage removed

| Stage | What the user sees | Why (grounding) |
|---|---|---|
| Enter | Form: **Current Password** + **New Password** with why-line (CP-02), CTA "Change Password". **No code-entry stage exists in this class's flow** | OWASP "Change Password Feature": session + current-password verification IS the baseline; "Minimize User Friction" |
| Submit → reauthenticate | `reauthenticate(email, currentPassword)` (typed current password = the visible verification). Wrong → inline field error (CP-10), values kept | "Require Re-authentication for Sensitive Features" (OWASP); blocks the session-thief class |
| Device step | System prompt (same wording); pre-probe + degrade notice (CP-14) as in 3.1; **cancel → retry card** (§7) | Possession factor; fail-open policy |
| Write + success | `updatePassword`; success SnackBar (CP-18); pop | — |
| Notification (post-write) | A best-effort security-notification send fires **after** the successful write, fire-and-forget (§4.3): the user's inbox is pinged at the verified channel. No in-app code entry, no in-app email promise (the success surface stays CP-18); a failed send is debug-logged, never surfaced | Anti-silent-change posture preserved as **detection**; the code is inert (nothing consumes it); NIST-consistent — email OOB is no longer used as authentication on this path |

**Chain order pin:** `reauthenticate → deviceCredentialPromptAvailable → confirmDeviceCredential → updatePassword → sendOtpStepUp` (the send is last, post-write; a failed factor attempt never consumes a send — the `:246` no-waste rule, generalized further).

Offline gate retained: `!isOnline` → inline error CP-11 (the offline path never needs connectivity).

### 3.3 Google-linked accounts — Google prompt first (the cycle-31 pairing restored), code stage retained

This class has **no current password** (`hasPassword == false`): the field is hidden, `reauthenticate` is skipped. The emailed code remains the **decisive verifier** (the §4 ruling below) — it is this class's only guaranteed factor, exactly as cycle-34 ruled; the presentation is rebuilt around it.

| Stage | What the user sees | Why (grounding) |
|---|---|---|
| Enter | Form: **New Password** only, with a class explainer naming all three checks up front (CP-01). CTA "Change Password" | No reauthentication exists for this class; the user deserves the whole picture before the first prompt |
| Submit → Google prompt | The **Google prompt first** (plan §4.1 — the cycle-31 pairing restored; `verifyGoogleReauth`, the gate method that cycle-34 retained with zero call sites). Runs on the **first submit per page visit**; any non-success (canceled / unsupported / email-mismatch / error) is **non-fatal**: inline notice CP-13 and the flow continues | An additive bound authenticator (OWASP); canceled/silent results are never read as a satisfied factor (google_sign_in 7.x throws — cycle-31 N5 evidence); the code gates regardless, so Google failing weakens nothing |
| Device step | System prompt, **once per submit**; pre-probe + degrade (CP-14); **cancel → retry card** (§7) | The co-factor that covers the undetectable silent-resolve case (cycle-31 N5 ruling) |
| Code send | `sendOtpStepUp(session.email)` — **only after** both prompts resolved (no-waste); send failure → retryable inline error (CP-19), no stage advance, no weaker fallback (cycle-34 Ruling 8 shape) | The SMTP quota governs every send; aborted attempts must not consume one |
| Code entry | Stage 2 (§6): 6-digit field, why-copy, resend with the 60 s window, verify → error stays retryable (CP-20/CP-21) | The decisive typed verifier — nothing can pass invisibly (cycle-34's structural closure) |
| Write + success | `updatePassword`; success SnackBar (CP-18); pop; session kept (the cycle-31 P2 ruling: the OTP-refreshed session is OWASP's password-change token renewal) | — |

**Chain order pin:** `verifyGoogleReauth (first submit only) → deviceCredentialPromptAvailable → confirmDeviceCredential → sendOtpStepUp → verifyOtpStepUp → updatePassword`.

### 3.4 Shared behavior (all classes)

- **One prompt per submit, in this order** — knowledge (current password / code) → possession (device) → write. The order is the OWASP friction rule plus the no-waste rule: nothing is sent or prompted after a step has already failed.
- **Never a dead-end**: every cancel/failure lands on a state with a named next action (§7).
- **Values kept on error**: neither password field is ever cleared by an error (GOV.UK technique; the existing code already does this — preserved).
- **Back affordance**: the app-bar back button exists on every stage; on the code stage it returns to the form (`_backToForm` semantics, retained).
- **Connectivity**: the online chains are gated by `ConnectivityCubit`; the local chain never is.

## 4. The emailed-step ruling (§4.3 P1 gate)

**RULING: reclassify per path. Cloud email+password → the emailed code becomes a NON-BLOCKING security notification (sent after the change). Google-linked → the emailed code STAYS BLOCKING, presentation rebuilt. Local → no email, unchanged.**

### 4.1 What cycle-34's recorded rationale actually names

From `plans/done/cycle-34-forgot-password-otp-template-mandatory-change-code.md` (read in full this session):

- The S2 finding that selected the work (its §2 table): *"Password change can pass with no user-visible verification (N5 silent Google resolve residual); user requires an emailed code."*
- Ruling 3: *"emailed OTP mandatory for both online classes, Google re-auth off the decisive chain, offline unchanged — N5 residual closed structurally."*
- The order rationale: *"This closes the N5 residual **structurally**: no silent resolve can satisfy the factor anymore, because the factor is a code that must be typed — there is nothing left that can pass invisibly."*
- Ruling 8 (the failure posture this spec preserves): no weaker-factor fallback, no silent skip; the retryable send-failure abort **is** the quota/revocation state, with cause-honest copy.

**The rationale names exactly one threat: a change completing with no user-visible verification (the N5 silent-resolve class).** It does not name the phished-credential class (an attacker holding the current password but not the inbox) — that threat appears only in cycle-41's own §1.2 synthesis as the blocking step's *value*. The rationale's character is therefore the **anti-silent-change posture** — "confirm the change via a verified channel" — which plan §4.3's own gloss maps to the notification branch *where the named threat is already covered*.

### 4.2 The per-path ruling and why

**Cloud email+password — RECLASSIFY.** On this path the rationale's named threat is **already covered** by `reauthenticate`: typing the current password *is* the user-visible verification (an OWASP bound authenticator). There is no factor that can "pass invisibly" past a typed current password. With the threat covered, the code's remaining role is the anti-silent-change posture — deliverable as a notification: **the password changes; the email informs the verified channel**; the code entry stage (and its keyboard problem, F3, for this class) disappears. NIST §3.1.3's prohibition on email OOB **as authentication** is thereby resolved for this path — the send is no longer an authentication step, and the SMTP quota (S1) still governs it.

**Google-linked — KEEP BLOCKING.** On this path **no reauthenticate exists** (no password). Cycle-34's named threat is *not* covered by anything that survives reclassification: with a non-blocking code, a Google-only account on a **no-screen-lock device** could complete a change with the Google credential resolving silently (best-effort-interactive, cycle-31 N5) and the device credential fail-open — a zero-factor pass, the exact residual cycle-34 closed structurally. A covered threat would be lost → S2 forbids reclassification. The code stays the decisive typed verifier; the presentation is rebuilt around it (why-copy CP-01/CP-23, the Google prompt first per plan §4.1, the device prompt ordered before the send — the `:246` no-waste rule — and a retry-safe resend, §6.3). The NIST email-OOB tension therefore **remains on this one path** as a recorded, accepted residual of the keep-branch (the plan's §4.3 keep-branch contemplates exactly this trade).

### 4.3 S2 baseline comparison (recorded per path)

| Threat | Email+password BEFORE (v1.8.1) | Email+password AFTER | Google BEFORE | Google AFTER |
|---|---|---|---|---|
| Session thief (session, no password) | Blocked by `reauthenticate` | Blocked by `reauthenticate` — **unchanged** | Blocked by the typed code | Blocked by the typed code — **unchanged** |
| Invisible pass (no user-visible verification — cycle-34's named threat) | Blocked by typed current password + typed code | Blocked by typed current password — **still covered** | Blocked by the typed code | Blocked by the typed code — **unchanged** (Google + device added *on top*) |
| Possession factor | Device credential, fail-open | Device credential, fail-open — **unchanged** | Device credential, fail-open | Device credential **plus the Google bound factor** — **strengthened** (§4.1 restored) |
| Phished-credential swap (attacker has the current password, not the inbox, on their own device) | Blocked by the emailed code | **NOT blocked — residual recorded** (§4.4) | N/A (no password to phish) | N/A |
| Email OOB used as authentication (NIST §3.1.3 tension) | Yes — in tension | **Resolved** on this path | Yes — in tension | Remains — **accepted residual** of the keep-branch |
| Rate limiting | Supabase-side; unchanged | **Unchanged** (no new bypass; `reauthenticate` failures map to CP-10) | Unchanged | **Unchanged** (send still quota-governed) |

Net: local unchanged; Google strictly strengthened (an additive factor, nothing removed); email+password loses exactly one protection (the phished-credential swap prevention) and gains NIST consistency plus the flow the user asked for. No path drops below its cycle-31 ratified baseline.

### 4.4 The recorded residual (for the Adviser gate)

The reclassification's one honest loss on the email+password path: an attacker who already holds the current password can now complete the swap from their own device. Bounding facts, recorded: (a) that attacker **already has full account access** — the swap adds sole control, not first access; (b) the notification pings the verified channel at the moment of the change — the owner **detects** the swap and can recover through the untouched forgot-password flow (a blocking recovery code to the inbox the attacker lacks); (c) **no in-app email-change surface exists** (grep-verified this session: zero hits for `updateEmail`/`UserAttributes(email` in `lib/`) — the recovery channel cannot be moved from inside the app, so the recovery path is robust. The residual is bounded and detectable; S2's "recorded per path" duty is discharged here and at the gate.

### 4.5 The notification send — mechanics and residuals

- **Trigger:** the user's own successful submit only; fired **after** `updatePassword` succeeds, fire-and-forget with a debug-log swallow — the success surface never waits on SMTP and never promises the email.
- **Machinery:** the existing, proven `sendOtpForStepUp` send (the cycle-34 template of record, untouched per S3). The email that arrives is therefore still subject "Your AgentA verification code" with a 6-digit code **that nothing consumes** — it is the channel-ping. A dedicated "password changed" template would be a cloud mutation: **recorded-only** (S4-class), out of scope, a future Adviser ruling.
- **In-app honesty:** because the email's content is the code template, the app makes **no promise about the email's content** — the success surface stays CP-18; the email explains itself at the inbox.
- **Fallback option for the gate:** if the Adviser rejects the inert-code notification, **Option B** is *no send at all* on the email+password path (OWASP-pure baseline; posture rests on reauthenticate + device credential, the phished-credential residual unchanged, §4.4 unchanged). The spec's default is the send (it preserves cycle-34's anti-silent-change posture as detection); Option B costs nothing security-wise and removes the template-mismatch cosmetic residual.

## 5. Stage redesign — the form stage

One progressive form for all classes (the class only decides which fields exist and which prompts follow — §3). Order top→bottom; every value is a §2 token.

### 5.1 Layout (token-pinned)

| # | Element | Specification |
|---|---|---|
| 1 | App bar | Unchanged: `base` background, title "Change Password" (`subtitle`, `ink`), back `IconButton` (`arrow_back_ios_new_rounded`, 20, `ink`, tooltip + Semantics "Back") |
| 2 | Class explainer — **Google class only** | CP-01, `body` in `subtext`, full-width, wraps; `AppSpacing.sm` below |
| 3 | Why-line | CP-02, `body` in `subtext`; `AppSpacing.xl` below it (all classes) |
| 4 | Current Password group — **hasPassword classes only** | Label "Current Password" (`label` w600 `ink`) → `sm` → field (5.2) → inline error line (5.5) |
| 5 | `AppSpacing.xl` between field groups | |
| 6 | New Password group | Label "New Password" (`label` w600 `ink`) → `sm` → field with helper "At least 6 characters" (5.4) → inline error line |
| 7 | Notice box | The existing icon+text notice pattern (CP-14 degrade; icon `info_outline` 18 in `warningText`, text `label` in `warningText`) — retained verbatim as a component |
| 8 | Retry card | §7 — replaces today's terminal error string on the cancel path |
| 9 | Error box | The existing error-line pattern (`label` in `errorText`) — for **chain-level** errors only (connectivity CP-11, session CP-12, lockout, send failure CP-19); field-level errors move inline (5.5) |
| 10 | `AppSpacing.xxl`, then CTA | Full-width `ElevatedButton`, min height 52, `buttonRadius`, `raised` shadow, label CP-18-adjacent "Change Password" (`button`, `onAccent`) |

Page gutter `AppSpacing.xl` (24 — the page's existing value, retained). The scroll view is the existing `SingleChildScrollView` with the §8 keyboard rules added.

### 5.2 Field shell (both password fields)

`SystemKeyboardTextFormField` inside the existing well-decorated container: `fillColor colors.base`, `AppShadows.well`, `inputRadius`. Prefix icons: `lock` (current) / `lock_outline` (new), 20, `subtext`. `obscureText: true` at rest, `autocorrect: false`, `enableSuggestions: false`. Autofill (GOV.UK technique; the wrapper already supports it): `autofillHints: [AutofillHints.password]` on current, `[AutofillHints.newPassword]` on new. `textInputAction`: `next` on current (advances focus), `done` on new (submits — same action as the CTA). **No `maxLength`** on either field (GOV.UK: never truncate passwords silently; the ≥6 rule is a validator, not a cap). Pasted and password-manager-filled values must survive untouched.

### 5.3 Show/hide toggle (F6)

A suffix `IconButton` per field, **independent state per field**, minimum touch target 48×48, icon 22 in `subtext`:

| State | Icon | Semantics label + tooltip (states the action) |
|---|---|---|
| Hidden (rest) | `visibility` | "Show password" (current field) / "Show new password" (new field) |
| Visible | `visibility_off` | "Hide password" / "Hide new password" |

Distinct labels per field (the GOV.UK two-toggles rule); the toggle never clears the field or moves focus; the icon swap animates at `AppDurations.quick`.

### 5.4 Inline verification (honest, no invented policy)

- **New password helper** (visible while the field can be edited): "At least 6 characters" — the app's **recorded** minimum (N3, held per cycle-32 Ruling 3). Stating it up front satisfies NN/g's no-hidden-rulebook rule; a strength meter is **not** built (the app implements no strength definition — a meter would be a fake claim; S4).
- **Validators**: current — empty → CP-08; new — empty → CP-08, `< 6` chars → CP-09.
- **Error timing**: validate on submit; after a failed submit, re-validate per keystroke so the error clears the moment the input satisfies the rule.
- **Values kept on error** (GOV.UK technique): a wrong current password (CP-10) is shown inline under the current field; both fields keep their values; focus moves to the current field.

### 5.5 Field-level vs chain-level errors

Field-level errors (CP-08/09/10) render under their field via the theme's `errorBorder`/`errorStyle` (adjacency technique — GOV.UK), and are announced by the framework's semantics. Chain-level outcomes (CP-11 connectivity, CP-12 session/lockout, CP-19 send failure, the generic CP-22) render in the error box below the groups — they are not field problems. The two channels are never mixed.

## 6. Stage redesign — the code stage (Google-linked class only)

The emailed code survives as a blocking verifier **only** on the Google-linked path (§4.2). This stage is rebuilt for that class: same machinery, honest copy, fixed keyboard behavior, a retry-safe resend.

### 6.1 Layout (token-pinned)

| # | Element | Specification |
|---|---|---|
| 1 | Stage header | "Verification Code" — promoted from the old field-label style to `AppTypography.title` in `ink` (a stage header, not a field label) |
| 2 | Body line | CP-23 (existing string retained — it names the exact address) |
| 3 | Why-line | CP-24, `body` in `subtext` |
| 4 | Code field | 5.2 shell; `keyboardType: TextInputType.number` (**retained — this class only**), `maxLength: 6`, digits-only enforced (`FilteringTextInputFormatter.digitsOnly` — the numeric keyboard alone does not block pasted non-digits), tracking `letterSpacing: 8`, hint "000000", prefix `password_rounded` 20 `subtext`, `textInputAction: done` (submits) |
| 5 | Notice box / error box | Same patterns as the form stage; CP-19 (send failure, retryable) and CP-21 (wrong/expired code, retryable no-op) render here |
| 6 | `AppSpacing.xxl`, then CTA | Full-width, label "Verify & Change Password" (existing string retained) |
| 7 | `AppSpacing.sm`, then resend row | §6.3 |
| 8 | `AppSpacing.sm`, then back link | "Back to password form" `TextButton` in `accentInk` (existing string and `_backToForm` semantics retained) |

The field **auto-focuses on stage entry** (the stage has one job) with the §8 keyboard rules active. **No auto-submit** at 6 digits — the explicit CTA is the single submit pattern; the keyboard's `done` submits.

### 6.2 Verify semantics (retained, restated for P2)

A wrong or expired code is a **retryable no-op**: no state loss, no stage change, the value kept for editing, CP-21 shown. The empty-field case is CP-20.

### 6.3 Resend (retry-safe, quota-honest)

- A `TextButton` "Resend code" plus a `labelSm` helper showing the countdown: "You can request a new code in {n}s" — disabled while the **60 s window** (the Supabase per-user resend window recorded in cycle-34 Rulings 8–9) is running; the button re-enables at 0.
- Each tap fires `sendOtpStepUp` again (quota-governed, S1 — user-action-triggered), restarts the window, clears the previous code error, and shows notice CP-25 ("A new code is on its way to {email}.").
- A failed resend renders CP-19 (the same retryable send-failure error the initial send uses — cycle-34 Ruling 8's cause-honest shape; **no** weaker fallback, **no** silent skip).
- The 60 s window also runs after the **initial** send (the send the flow just did counts as the first request).

## 7. The cancel-retry card (F2) and notices

### 7.1 The retry card — the dead-end's replacement

Today a canceled device prompt ends the change with "Device confirmation was canceled. Your password was not changed." (`:415` online, `:327` offline enum mapping) — terminal, unexplained, no next step. **Both sites are replaced by one inline retry card.** The retired string must be grep-zero after P2 (§12.4).

**Composition** (all tokens from §2; status = icon + text on the neutral surface — never a colored panel):

| Part | Specification |
|---|---|
| Container | `base` surface, `AppShadows.raised`, `AppRadius.cardRadius` (20), `AppSpacing.cardPadding` (16) |
| Icon | `phonelink_lock`, 24, `warningText` |
| Title | CP-15 — "Your phone's screen lock didn't confirm" — `subtitle`, `ink` |
| Body | CP-16 — "Your password was not changed. Nothing has been saved yet. Try again to continue." — `body`, `subtext` |
| Primary action | "Try again" — `ElevatedButton` (accent), min height 52 |
| Secondary action | "Back" — `TextButton` in `accentInk` |

**Placement:** inline in the status stack — after the notice box, above the error box and CTA; enters at `AppDurations.entrance`/`standardCurve`; disappears on success or when "Back" is taken. It is inline content, **never a dialog** — the form (and its values) stays visible above it.

**Actions:**

- **"Try again"** re-runs **only the failed step**, never the whole chain: online — `confirmDeviceCredential` alone (the typed current-password proof already passed this submit; re-asking for the password would be punitive); offline — the local proof re-runs (`_submitOffline` with the still-held values; no email exists on this path). No send is ever consumed by a retry (the no-waste rule).
- **"Back"** returns to the form state with both fields intact and every chain state cleared.

**No loop limit:** canceling is user intent, not an error condition — the card reappears with the same explanation on every cancel. (Rate-limiting duties live where they belong: the current-password lockout and Supabase's server-side limits — both unchanged.)

### 7.2 The degrade notice (retained verbatim)

"No screen lock" is not a cancel — it is the cycle-31 P1 fail-open policy. The existing notice-box pattern and strings (CP-14 online, CP-14a offline) are **retained verbatim**: icon `info_outline` 18 + text in `warningText`, the change proceeds, the user is told why the prompt did not appear.

### 7.3 Notice vs error (the channel rule)

Notices (icon + `warningText`) explain **what is happening** (degrade, code sent CP-25). Errors (inline field or the error box in `errorText`) name **what failed and what to do** (CP-10, CP-19, CP-21, CP-22). Service problems the user cannot fix are never dressed as field errors (GOV.UK technique) — e.g. CP-19 renders as a chain-level error with a retry action, not as a field error.

## 8. Keyboard handling (F3)

**The rule: on every stage, while any field has focus, the primary CTA is visible above the keyboard.** The user must never wonder whether the button exists (the defect in the user's screenshot: the numeric keyboard fully covered "Change Password" on the code stage).

Behavior requirements for P2 (implementation-flexible, behavior-pinned):

1. **Inset-aware viewport** — the scroll content's bottom padding accounts for `MediaQuery.viewInsets.bottom` (or the scroll view's `scrollPadding` is set so the CTA can always be brought above the inset). The CTA is the last element of every stage's content and can always scroll fully above the keyboard.
2. **Focus brings the action with it** — when a field gains focus, the focused field **and the CTA** are scrolled into the visible viewport (`Scrollable.ensureVisible`, bottom-aligned). The user sees the primary action while typing, on the form stage and the code stage alike.
3. **The code stage fits without scrolling** — its content above the CTA is short (header, two text lines, one 52-px field). With the numeric keyboard open on a standard phone viewport, field + CTA must both be visible with zero scrolling; P4's regression test asserts this behaviorally (§12.3).
4. **The keyboard type itself is unchanged** — the numeric keyboard on the code field stays (§6.1); the defect was the viewport, not the keyboard.
5. **Dismiss-on-tap-outside retained** — the existing `GestureDetector` unfocus behavior stays: tapping outside a field dismisses the keyboard, revealing the full stage.
6. The shared wrapper's `keyboardAppearance: Brightness.light` is retained on every field.

## 9. Component states matrix

Every interactive component × every state. All styling comes from §2; "n/a" = the state cannot occur for that component. Mobile-first: `pressed` replaces hover (the theme's overlay); no hover state is specified.

| Component | Rest | Focus | Pressed | Error | Disabled | Loading | Success |
|---|---|---|---|---|---|---|---|
| Password field (current/new) | Well shadow, no border, label above, prefix icon `subtext` | Accent border 1.5 (theme); helper visible (new field) | n/a (text field) | `errorText` border 1.5 + inline message (CP-08/09/10); **value kept** | — during save (`_isSaving`) | n/a | n/a (page navigates) |
| Show/hide toggle | Icon per §5.3 state, 48×48, `subtext` | Theme focus ring | Theme overlay (onAccent @ 11%) | n/a | With its field during save | n/a | n/a |
| Code field (Google class) | Well shadow, hint "000000", tracking 8 | Accent border 1.5; auto-focused on stage entry | n/a | CP-20 (empty, inline) / CP-21 (wrong, chain-level) | During save/verify | n/a | n/a |
| CTA "Change Password" / "Verify & Change Password" | Accent fill, `raised` shadow, `onAccent` label | Theme focus | Overlay + `pressed` shadow per theme | n/a (errors render elsewhere) | `base` fill + `disabledText` (theme), `flat` shadow | 20 px `CircularProgressIndicator` in `onAccent`, button disabled | n/a (pops to profile) |
| Retry card (§7) | Hidden | — | — | Shown on device-cancel: raised card, icon+title+body | Buttons disabled during the retry's prompt | "Try again" shows the button spinner | Card dismissed |
| Notice box | Hidden | — | — | — | — | — | Shown while the condition holds (CP-14/14a/25) |
| Error box | Hidden | — | — | Chain-level message in `errorText` (CP-11/12/19/21/22) | — | — | Cleared |
| Resend button (§6.3) | `accentInk` text, enabled after the 60 s window | Theme focus | Theme overlay | CP-19 on failure | **During the window** + its countdown helper | — | CP-25 notice on send |
| "Back to password form" link | `accentInk` text, 48 min | Theme focus | Theme overlay | n/a | During save | — | n/a |
| Success SnackBar | — | — | — | — | — | — | CP-18 "Password changed!", floating, `snackbarRadius` |

## 10. Copy table + retirements

Tone of record (matching the app's existing auth copy): plain, sentence case, direct, "you/your", one short sentence per idea, honest about cause and next step, no jargon, no apology filler. `{email}` is the live session email, interpolated, never a placeholder. **Strings marked "retained" must land byte-for-byte** — they are pinned by existing tests and the Reviewer's greps.

### 10.1 New copy (P2 adds these)

| ID | Surface · state | Verbatim string |
|---|---|---|
| CP-01 | Form · Google class explainer | "This account signs in with Google. To confirm it's you, we'll check your Google account and phone lock, then email a code to {email}." |
| CP-02 | Form · why-line under the title (current-password classes: local, email+password) | "We ask for your current password to make sure it's really you." |
| CP-06 | Show/hide toggle · semantics label + tooltip (state-swapped) | "Show password" / "Hide password" / "Show new password" / "Hide new password" |
| CP-13 | Form · Google prompt non-success (non-fatal, flow continues) | "Google confirmation didn't go through. We'll confirm it's you with the emailed code instead." |
| CP-15 | Retry card · title | "Your phone's screen lock didn't confirm" |
| CP-16 | Retry card · body | "Your password was not changed. Nothing has been saved yet. Try again to continue." |
| CP-17 | Retry card · actions | "Try again" / "Back" |
| CP-24 | Code stage · why-line (Google class) | "This is the final check that it's you before your password changes." |
| CP-25 | Code stage · after a successful resend | "A new code is on its way to {email}." |
| CP-26 | Code stage · resend countdown helper | "You can request a new code in {n}s" |
| CP-27 | Code stage · resend button | "Resend code" |

### 10.2 Retained copy (byte-for-byte; sources are the shipped page)

| ID | Surface · state | Verbatim string | Source |
|---|---|---|---|
| CP-00 | App bar title | "Change Password" | `:482` |
| CP-03 | Current-password label | "Current Password" | `:527` |
| CP-04 | New-password label | "New Password" | `:557` |
| CP-05 | New-password helper | "At least 6 characters" | the validator at `:587`, now surfaced as helper text |
| CP-07 | Form CTA | "Change Password" | `:613` |
| CP-08 | Field empty validator | "Required" | `:551` |
| CP-09 | New-password validator | "At least 6 characters" | `:587` |
| CP-10 | Wrong current password (inline) | "Current password is incorrect" | `:325`/`:460` |
| CP-11 | Online class, offline device | "Changing password needs internet. Your current password still works offline." | `:225`/`:321` |
| CP-12 | Session gone | "Session expired. Please log in again." | `:319`/`:464` |
| CP-12a | Current-password lockout | "Too many attempts. Try again later." | `:323` |
| CP-14 | Degrade notice (online) | "This phone has no screen lock, so it can't confirm it's you. Continuing with the check you already passed." | `:421` |
| CP-14a | Degrade notice (offline) | "This phone has no screen lock, so it can't confirm it's you. Continuing with your current password check only." | `:282` |
| CP-18 | Success SnackBar | "Password changed!" | `:295`/`:438` |
| CP-19 | Code send failure (initial + resend, Google class) | "We couldn't send the code right now — try again in a bit" | `:343` |
| CP-20 | Empty code | "Enter the 6-digit code from your email." | `:370` |
| CP-21 | Wrong/expired code | "That code is invalid or expired. Check the email and try again." | `:388` |
| CP-22 | Generic failure | "Something went wrong. Your password was not changed." | `:305` |
| CP-23 | Code stage body | "Enter the 6-digit code we emailed to {email} to confirm this password change." | `:639` |
| CP-28 | Code stage CTA | "Verify & Change Password" | `:696` |
| CP-29 | Code stage back link | "Back to password form" | `:706` |
| CP-30 | Code stage header | "Verification Code" | `:631` |
| CP-31 | CAS conflict | "Your account changed before the update finished. Your password was not changed." | `:329` |
| CP-32 | Device-prompt system reason (unchanged step-up wording) | "Confirm your identity to change your password" | `:159` |
| — | Network error | "Network error. Check your connection." | `:467` |

### 10.3 Retired copy (must be grep-zero after P2, unless noted)

| Retired string | Where it lives today | Replaced by |
|---|---|---|
| "Device confirmation was canceled. Your password was not changed." | `:415` (online abort) and `:327` (offline `deviceCancelled` mapping) | The retry card (CP-15/16/17) — **both sites**; the §12.4 grep expects zero hits |
| "We'll email a 6-digit code to {email} to confirm this change." | `:520` (Google form explainer) | CP-01 (names all three checks, not just the email) |
| "We emailed a 6-digit code to {email}. Enter it below to finish." | `:353` (stage-advance notice) | Redundant with CP-23 on the rebuilt stage |
| "Failed. Check current password." | `:470` (`_mapError` fallback) | CP-22 (specific cases already map to CP-10/CP-12; the fallback must not guess) |
| "Failed. Check your connection and try again." | `:471` (`_mapError` fallback) | CP-22 (the network case keeps its own specific string) |

## 11. Accessibility + platform conventions

### 11.1 Touch targets

- Every interactive element ≥ 48×48 dp: CTA and retry-card button (min height 52 via theme), text buttons (48 via theme), both show/hide toggles (48×48, §5.3), the app-bar back button (system default). No bespoke control may land below 48 dp.

### 11.2 Semantics and announcements

- **Show/hide toggles** carry state-swapped `Semantics` labels stating the **action** (CP-06) and a matching tooltip; the obscured/visible state is never conveyed by icon alone to assistive tech.
- **Field errors** render via the theme's `errorText` slot so the framework announces them with the field; the GOV.UK "Error:" prefix pattern is the framework's native behavior here — no custom announcement is needed.
- **The retry card** is announced as a unit when it appears (its title is the semantic header); its two buttons carry plain labels (CP-17).
- **The code field** is labeled "6-digit verification code"; the resend countdown helper is a live-updating label (the countdown number changes are announced by label text change).
- **The success SnackBar** (CP-18) uses the framework's spoken-snackbar behavior.

### 11.3 Focus order and keyboard navigation

- Traversal order = visual order, top to bottom, on every stage (no custom traversal): current password → new password → CTA; code stage: code field → verify CTA → resend → back link. No focus traps; the app-bar back button is reachable first, as shipped.
- `textInputAction` moves focus forward (§5.2); `done` submits — an external-keyboard user completes the flow without touching the screen.

### 11.4 No color-only signaling

- Every error carries text (and, for chain errors, the established icon+text pattern); every notice carries an icon **and** text; field errors add the theme's error border. The toggle's state is icon + semantics label. Success is a spoken, written snackbar. No state is encoded in color alone.

### 11.5 Platform conventions

- **Autofill**: `AutofillHints.password` / `AutofillHints.newPassword` (§5.2) — password managers fill correctly; no `maxLength` truncation on password fields (§5.2).
- **System prompts**: the device-credential prompt keeps its dedicated step-up wording (CP-32, unchanged — the P2 contract's distinct step-up wording).
- **Text scaling**: all copy wraps (`whiteSpace: wrap` behavior via theme styles; no fixed-height text containers); the CTA stays full-width at large font scales; the retry card grows with its text.
- **Light keyboard appearance** on every field (the shared wrapper, retained); the app is light-only by design system (§2).

## 12. P2/P3 handoff, tests, and verification

### 12.1 P2 scope (frontend — unconditional after ratification)

| File | Change |
|---|---|
| `lib/presentation/profile/change_pass_page.dart` | The rebuild per §§3–9. **Constructor seams unchanged** (`factorGate`, `offlineService` — the test fakes depend on them). `PasswordChangeSession`/`PasswordChangeFactorGate` stay as-is (the gate already exposes every method the redesign calls, including the currently-unused `verifyGoogleReauth`) |
| New private widgets, same directory (P2's discretion) | The retry card, the show/hide field wrapper — `lib/presentation/profile/` only |
| Tests (§12.3) | Updated pins + the new coverage |

**Explicitly unchanged:** `profilepage.dart` (the entry tile is untouched), `offline_password_service.dart` (mechanics unchanged; the zero-Supabase-imports invariant holds), `local_user_dao.dart`, `biometric_auth_service.dart`, all forgot-password code, all cloud config. **No new dependencies, no new permissions.**

### 12.2 P3 scope (CONDITIONAL — one comment-only doc update; plan §4.4)

`auth_service.dart` `sendOtpForStepUp`'s doc comment (`:721-730`) states the code is *"the MANDATORY final factor when the password changes online — sent unconditionally for both account classes"* — false under the §4 ruling. P3 (or the gate's consolidated rider) updates that comment to the per-class truth: **blocking verifier for the Google-linked class; post-write best-effort security notification for the email+password class; never invoked for local accounts.** Zero behavior change; `verifyOtpStepUp`'s comment needs no change.

### 12.3 Test guidance (the order pins are the contract)

All through the existing fake-gate seams; **no test triggers a real send (S1)**; the notification send is asserted as a recorded call that happens **after** `updatePassword`.

| Suite | Updates |
|---|---|
| `test/cycle31_p3_change_password_test.dart` | New order pins: email+password = `[reauthenticate, deviceCredentialPromptAvailable, confirmDeviceCredential, updatePassword, sendOtpStepUp]`; Google = `[verifyGoogleReauth, deviceCredentialPromptAvailable, confirmDeviceCredential, sendOtpStepUp, verifyOtpStepUp, updatePassword]`. Google non-success outcomes (canceled/unsupported/mismatch) are non-fatal and still reach `sendOtpStepUp`. Canceled device prompt → NO `sendOtpStepUp` (quota discipline, retained) and the **retry card** renders; "Try again" re-calls `confirmDeviceCredential` without a second `reauthenticate`. The dead-end string assertions are replaced by retry-card assertions. No code stage exists for the email+password class |
| `test/cycle31_p4_offline_password_test.dart` | The page-level `deviceCancelled` assertion moves to the retry card; the **19 offline-flow service tests stay byte-untouched** (the invariance precedent); the online control case's pin becomes the §3.2 email+password order |
| `test/cycle31_e2e_gate_test.dart` | Same pin updates as p3 |
| New: F3 keyboard regression | A widget test with a simulated keyboard inset asserting the code-stage field + CTA are both above the inset with zero scrolling (§8.3) |
| New: F6 toggle | Independent state per field; semantics labels swap (CP-06); value preserved across toggles |
| New: resend window | The 60 s window after the initial send and after each resend; CP-25 on success; CP-19 on failure (fake time / pumped clocks) |

### 12.4 Reviewer grep expectations (mapping the plan's §10 commands to this spec)

- `grep -n "Device confirmation was canceled" lib/` → **zero hits** (§10.3).
- `grep -rn "keyboardType: TextInputType.number" lib/presentation/profile/` → **exactly one hit: the Google-class code field** — the plan's conditional resolves to "kept, for the Google class only" (§4.2, §6.1).
- `grep -rn "updateLocalPassword" lib/ test/` → intact; `offline_password_service.dart` unchanged with zero Supabase imports.
- The retired strings of §10.3 → zero hits each.

### 12.5 S5 pre-check

Every pattern specified here is implementable with Flutter core + the app's existing dependencies (standard `Form`/`TextFormField` mechanics, `Scrollable.ensureVisible`, `Semantics`, timers for the resend window) and the page's existing seams. **No service-layer behavior change is required anywhere** — the §4 flows reorder and repurpose existing calls. Nothing in this spec should trip the plan's STOP rule; if P2 finds a layout or state the framework resists, S5 fires with the specific gap.

## 13. References (ui-reference) and reject-list check

### 13.1 References used (per the ui-reference skill's citation rule)

1. **NN/g — Password Creation: 3 Ways To Make It Easier** (https://www.nngroup.com/articles/password-creation/) — taken: state the requirements up front and keep them visible while the field is selected (→ CP-05 as always-visible helper, never placeholder); allow unmasking (→ §5.3); no hidden rulebook.
2. **GOV.UK Design System — Password input** (https://design-system.service.gov.uk/components/password-input/) — **techniques only, house style left behind**: hide by default with a show/hide control; distinct toggle labels per field; no confirm-password field (tested decision — this page never had one; it stays absent); autocomplete/current-password vs new-password (→ `autofillHints`); never truncate passwords with a length cap; keep entered values on error; allow paste.
3. **GOV.UK Design System — Error message** (https://design-system.service.gov.uk/components/error-message/) — **techniques only**: error adjacent to its field; describe what happened + how to fix; match the message to the label; be specific (no "An error occurred"); service problems are not field errors (→ §5.5's channel rule, §7.3).

The institutional (GOV.UK) visual identity — palette, type, left-border panels — is explicitly **not** adopted; only the tested interaction/technique patterns are. Tooling note: no websearch tool was available this session, so the skill's search step was executed as direct fetches of these canonical sources; the AI-tell refresh query could not be run — the skill's baseline reject list was applied instead (below).

### 13.2 Reject-list check (declared)

- No colored left-border panels, no purple-blue gradient backgrounds, no new typeface (the app's Roboto system stands), no card grids, no glassmorphism, no gradient text, no bounce easing, no pill/eyebrow badges. The one accent (`#3D5AFE`) keeps a single job (primary action + focus). Status is icon + text in semantic inks — never decorative surfaces. The design is the app's own system applied, not a template imported.

### 13.3 Visual annex (framesmith canvas) — verification record

The three key states are built as a visual annex in the repo-bound canvas store (`.framesmith/`): canvas **"C41 · Change-Password Redesign — stage annex"** (`XXx6E1EuRj`, project `UI`, workspace `Aiproject`; viewer http://localhost:3001/canvas/XXx6E1EuRj). It renders the form stage (email+password class), the code stage (Google-linked class), and the retry-card state, using only the §2 tokens (set once as workspace tokens).

**Verification outcome (canvas_evaluate, fast mode, `genre: material` — the app is Material 3 per `app_theme.dart`): 87/100**, color 100, spacing 85, structure 85, consistency 75, typography 80, cliché 94. Fixed during the loop: the one AA contrast error (annex caption on the backdrop), every off-scale spacing value (snapped to the app's scale), a needless wrapper level, and a non-rendering icon. **Accepted residuals, each with its reason:**

- *Typography warnings (14→13, 13→12 ratio 1.08)* — these are the app's **verbatim type scale** (`AppTypography.body/label/labelSm`); the ui-reference rule that the project's design system outranks the generic heuristics governs. Resolving them would falsify the annex.
- *Tree-depth warning (9 levels on one node)* — the retry-card composition mirrors the real widget tree, which is legitimately deeper; flattening further would distort the mock.
- *Consistency/spacing infos* — zoned padding (app bar vs body vs card) is intentional structure; the annex uses the app's full 7-token spacing scale by design.
- *One honest-content info* — a factual caption containing the flow-class name was misread as a brand wordmark; it is a label, not fabricated content.
- The LLM-critique tier of the evaluator was **unavailable** (no provider key in this environment) — the fast-mode result above is the full available verification record; the Adviser gate should treat the annex as supporting evidence, with this spec's tables as the normative design.

## 14. Open items for the Adviser ratification gate

1. **Confirm the §4 ruling** (email+password → notification; Google → keeps the blocking code) and the S2 residual of §4.4.
2. **Choose the notification shape**: the default (post-write send via the proven machinery, template-mismatch residual accepted — §4.5) or Option B (no send; OWASP-pure). The spec's default is the send.
3. **Confirm P3's shape**: the one comment-only `auth_service.dart` doc update (§12.2) as a tiny P3, or consolidated into P2's commit at the gate's discretion.
4. **Note the recorded policy gaps** (untouched by design, for the backlog): F5 (NIST blocklist) and F8 (minimum length) remain S4-class policy items; the NIST email-OOB tension remains **accepted** on the Google path only (§4.2).
5. **Delegation path note for the record**: the delegation named `lib/presentation/auth/change_pass_page.dart`; the file of record is `lib/presentation/profile/change_pass_page.dart` (the plan's own §10 grep uses `lib/presentation/profile/`; the tree matches the plan). No other divergence between the plan's §1 ground truth and the tree was found — every cited anchor re-verified this session.
