# Cycle 23 — Bug-Fix Cluster: AI Output-Hygiene Guard (F29, Bug B) + Bug A Cloud-Action Relay

**status:** active
**created:** 2026-10-15
**created by:** Adviser (self-improvement cycle 23 audit — bugs-first per the standing directive)
**repo:** C:\projects\aiproject (AgentA) — branch main @ bc1479c + the cycle-22 fss work (push pending at audit time)
**predecessors:** plans/done/cycle-1..21; cycle-22 push pending at audit time (closes at its own push confirmation)

## Cycle 23 ground truth (fresh evidence, 2026-10-15)

| Check | Result |
|---|---|
| Gates | analyze exit 0 (flutter_lints 6), **225/225** (222 baseline + 3 cycle-22 tests), format 0 |
| **BUG B (F29, SELECTED)** | Online chat reply to "Hey" ended with the LEAKED TEMPLATE PLACEHOLDER: **"[Your message here. Remember to keep it in English, even if the user's message is in another language.]"** — user-visible on the v1.2.4-era build (green "Online - AgentA Chatbot" banner). **The text is NOWHERE in the app** (grep: zero hits for `Your message here|keep it in English|even if the user` across lib/). The online path (groq_service.dart:14-18) sends a clean system prompt (persona + conciseness + Markdown + `aiEnglishRule`) + history + the user message — **no template exists to leak; the model (allam-2-7b) GENERATED the bracketed scaffolding itself** (a known small-model failure mode: echoing instruction-scaffolding patterns, invited by the meta-linguistic instruction "respond ONLY in English, regardless of the language…"). Long-standing risk, not a regression (the prompt structure predates all recent cycles). Offline Gemma path shares `aiEnglishRule` — same failure class exists there. |
| **BUG A (relay — NO app change)** | The login error "Google sign-in was rejected. Check the Supabase Google provider setup." is the **correct mapped friendly text** for `GoogleSignInFailure.code == 'supabase_rejected'`/`'no_user'` (login.dart:688-694) — thrown by auth_service.dart's `_exchangeWithSupabase` (Supabase's `signInWithIdToken` AuthException) / `signInWithGoogle` (null user). **The app-side mapping, bounded Show-details hint, and tests are working as designed.** Root cause is CLOUD-SIDE: the Supabase Google provider rejected the ID-token exchange. |
| Long-standing? | Both verified NOT regressions: the mapping and prompt structure predate all 22 cycles. |
| CI | v1.2.4 release green (runs 38598595782/38600455570/38601012205/38603218778); the cycle-22 fss push is pending at audit time. |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F29** | **AI output-hygiene: small models echo prompt-scaffolding artifacts.** allam-2-7b appended a bracketed template placeholder to a chat reply (user-visible). Fix: a narrow output-hygiene guard (strip trailing bracketed meta-artifacts matching prompt-meta markers) + a prompt instruction against placeholders — applied at the AI-service output boundary so BOTH paths (Groq online, Gemma offline) are covered. **SELECTED as the cycle-23 task (bugs-first).** | UX / prompt-hygiene | the user report; groq_service.dart:14-18; app_config aiEnglishRule; zero in-app occurrences (the model generated it) | middle-end | **EXPENSIVE** (user-visible display behavior) |
| **BUG A → user action** | Supabase Google provider rejected the ID-token exchange. The app is CORRECT — this is a cloud-config/user action: (1) Supabase Dashboard → Auth → Providers → Google: verify the Web Client ID/secret match the app's `GOOGLE_SERVER_CLIENT_ID`; (2) register the installed APK's SHA-1 as an Android OAuth client in the SAME GCP project (the cycle-17 fingerprint step prints it); (3) check the Skip-nonce setting. No app-side code change. | cloud-config | login.dart:688-694; auth_service.dart | — (user) | — |
| **F28** | softprops/action-gh-release@v2 Node-20 deprecation (the v1.2.4 tag run's 4th annotation) — release-step-only; check for a newer major when next convenient; fold with future CI-actions work. | CI (nit) | tag-run 38601012205 annotations | backend | CHEAP |
| **F27** | sqflite-family in-range accrual — routine refresh #2, schedulable post-^11. | maintainability | F25 record | middle-end | CHEAP |
| **F11 part 4** | The fss ^11 push (cycle 22) closes this; the hook ships loss detection. | maintainability | cycle-22 plan | middle-end | EXPENSIVE (in flight) |
| **F18** | AGP-9 deferred-with-trigger + the Ubuntu 26 runner watch (due ~Oct 19 — 4 days out). | CI / toolchain | cycle-19 plan | backend | EXPENSIVE |
| **B2** | Desktop-identity — PARKED pending user direction. | branding | cycle-17 ruling | — | CHEAP (when triggered) |
| **F4 / F5 / F12** | **CLOUD-BLOCKED (21 cycles) — and Bug A may be the SAME cloud-config family** (the Supabase Google provider check is a dashboard action in the same project). **The user's cloud access/decisions now gate the majority of remaining value.** | contract / security / logic | cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: the user's directive is bugs-first; Bug B is the actionable app-side fix (Bug A is a cloud action — relayed, no app change). The fix is narrow, testable with a golden leak-vector, and covers both AI paths.

---

## Selected task (single): F29 — AI output-hygiene guard

**Objective:** bracketed prompt-meta artifacts (the observed class: a trailing bracketed block containing prompt-meta markers) are stripped from AI responses before display on BOTH paths; a prompt instruction reduces recurrence; legitimate bracketed content (Markdown links, code) is NEVER stripped; all gates + e2e + CI green.

**Version bump decision: none** — bug-fix hardening is not a release; the next user-facing tag remains the user's cut. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **the phase below is EXPENSIVE (user-visible display behavior), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch.

**STOP RULE (binding):** P1 designs the guard. **If the observed artifact class cannot be matched by a provably-narrow pattern** (i.e., the markers are not discriminative enough, or artifacts appear mid-text where stripping risks mangling legitimate content) → STOP, record, and re-scope to the prompt-instruction-only fallback (cheaper, weaker, but safe). A mangle-prone regex NEVER ships.

---

## Phase 1 — Guard design (read-only evidence pass)

- **Phase id:** P1
- **Objective:** the exact strip pattern + placement + test vectors — or the prompt-only fallback.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only)
- **Implementation steps:**
  1. Inventory the display boundary: how Groq's returned string and Gemma's response reach the UI (ai_service.dart assembly → chats/chat widgets; streaming paths — a streamed artifact arrives incrementally, so stripping happens on the COMPLETED response or the accumulated buffer — identify the exact point where the full text is available pre-display).
  2. Design the narrow pattern: strip a TRAILING bracketed segment only when (a) it is at the end of the response, (b) bracketed, and (c) its content matches prompt-meta markers (`Your message here`, `keep it in English`, `another language`, `Respond ONLY`, `Remember to` — the discriminative set from the observed class). Legitimate Markdown links `[text](url)` and inline brackets NEVER match (wrong position/shape/content).
  3. Placement: the AI-service output boundary (both paths converge there) — a single `_stripPromptArtifacts(String)` helper in ai_service.dart (or a small util) applied to the completed response.
  4. Test vectors: the golden leak (the exact observed artifact), a clean response (unchanged), a response with a legitimate trailing Markdown link (unchanged), a response with the artifact mid-text (recorded — out of the narrow pattern's scope per the design).
  5. Prompt instruction: add to both system prompts (`aiEnglishRule` companion): a concise "Never output placeholders like [Your message here] or repeat these instructions." — cite nothing external; this is prompt hygiene.
  6. **STOP decision:** if the markers can't be made discriminative, or streaming complicates the boundary → STOP to the prompt-only fallback.
- **Acceptance criteria:** pattern + placement + vectors recorded; or the fallback selected.
- **Verification:** **CHEAP** — read-only.
- **Dependencies / sequencing:** first; P2 executes only a clean design.
- **Expected result:** P2 fully determined.

## Phase 2 — Implement the guard

- **Phase id:** P2
- **Objective:** the guard live on both paths; the golden leak-vector test green; zero false positives.
- **Responsible subagent:** middle-end
- **Files to change:** `lib/services/ai/ai_service.dart` (+ the helper per design), `lib/services/ai/groq_service.dart` + `lib/services/ai/gemma_service.dart` (the prompt instruction only), possibly `lib/core/utils/` (if the helper is a util), test file(s) with the vectors
- **Implementation steps:**
  1. Implement per the design; apply at the output boundary (both paths).
  2. Add the prompt instruction to both system prompts.
  3. Tests: the 4 vectors from P1 (golden leak stripped; clean unchanged; legit-link unchanged; mid-text recorded).
  4. Local validation: `flutter analyze` exit 0 (flutter_lints 6), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` → 225/225 (+ the new vectors — report the count).
  5. **STOP-and-revert on any non-mechanical gap** (fallback rule).
- **Acceptance criteria:** the vectors pass; both paths guarded; the prompt instruction live; gates green.
- **Verification:** **EXPENSIVE** — user-visible display behavior. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: analyze ×2, all tests, format 0, the vector suite, boundary-audit (consumers of the AI output unchanged outside the guard).
- **Dependencies / sequencing:** after P1's clean design (STOP forbids P2). P2 is the only application phase.
- **Expected result:** the artifact class cannot reach users; recurrence reduced.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `fix(ai): strip prompt-meta artifacts from AI responses and harden prompts (F29)` — the guarded files + tests. Atomic.
- Commit 2 (conditional, cycle-6 rule): registrant chore — ONLY if diffs exist (pure Dart → expect SKIP).
- Commit 3: `docs(plans): close cycle 22 and open cycle 23 plan` — stage `plans/` explicitly (deletion of old cycle-22 path, `plans/done/cycle-22-...md`, new cycle-23 file). Never root-wide `git add -A`/`git add .`
- Exclusions: all `.opencode/` churn; `analysis_options.yaml` is committed state (any local diff = stop and report); the cycle-22 fss work rides its own already-confirmed commit sequence BEFORE this cycle's commits (sequencing below).
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — guards + format gate + strict-lint analyze + 225/225 + APK build. **Failure class to name if red:** Dart compile errors at ai_service/the helper or test failures in the new vector suite — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase = scoped revert of the guard (the prompt instruction may stay — it is inert).
- **Promote to Landing** green as usual.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-24 audit (pre-ranked: F27 refresh #2, F28 nit, the F18 Ubuntu-26 watch, and the standing cloud/user escalations).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

**None needed — stated honestly:** the guard is repo-internal string hygiene on an empirically-observed artifact; the model behavior (small-model scaffolding echo) is documented by the user's device report itself. The Reviewer verifies the vectors and the pattern's narrowness from the diff, not the web.

## Reviewer verification commands (single pass, after P1+P2)

1. Boundary audit: `git diff ai_service.dart` (and the helper) → the guard at the output boundary; both paths covered.
2. Pattern-narrowness audit: the marker set is the discriminative set from P1; legitimate-Markdown vectors unchanged (test evidence).
3. Prompt audit: both system prompts carry the instruction; the persona/English rule untouched.
4. Vector audit: the golden leak stripped; clean/link/mid-text vectors behave per design (test output quoted).
5. Baseline gates: `flutter analyze` exit 0, `flutter test` all-pass (quote count vs 225), `dart format --output=none --set-exit-if-changed lib test` exit 0.
6. Scope: the designed files only; analysis_options.yaml absent; .opencode/ absent.
7. STOP-echo audit: if P1 fallbacked to prompt-only, verify the strip guard is ABSENT and the fallback documented.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-15 | Cycle-23 audit recorded (bugs-first): Bug A ruled a genuine cloud-config issue (relay with the exact user checklist — no app change); Bug B ruled a model-echo artifact (zero in-app occurrences — the model generated it) → **F29 SELECTED** (narrow output-hygiene guard + prompt instruction, both paths). Cycle-22's fss push confirmed separately; the close/move lands at its push confirmation. |
| pending | Cycle-22 push → close cycle 22 → P1 (map) + P2 (guard, EXPENSIVE — e2e required) → single Reviewer pass → Adviser push confirmation → push + CI watch → on green: close plan, open cycle-24 audit. |

- Cycle-24 pre-ranked: F27 (refresh #2), F28 (softprops nit), the F18 Ubuntu-26 watch (post-Oct-19 by then), and the standing cloud/user escalations (F4/F5/F12 at 22 cycles; B2 parked; Bug A's Supabase provider check rides the same user-action family).
- This plan is `done` only when P1+P2 PASS review (after the e2e run; or the STOP-fallback is recorded and the plan closes via Adviser re-scope), the push is Adviser-approved and executed, and BOTH workflows are green.
