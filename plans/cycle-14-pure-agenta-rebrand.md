# Cycle 14 — Pure AgentA Rebrand (F23) — "AI Skill Coach" removal + brand normalization

**status:** active
**created:** 2026-10-14
**created by:** Adviser (self-improvement cycle 14 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 3e709bb
**predecessors:** plans/done/cycle-1..13 (all closed, CI green; latest runs 38434757176 / 38436746278)

## Cycle 14 ground truth (fresh evidence, 2026-10-14)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 13th consecutive clean cycle |
| `flutter test` | **222/222 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts |
| `pub outdated` queue | cupertino_icons 2.0.0, flutter_dotenv 6.0.1, flutter_launcher_icons 0.14.4 (+ gated ^11 fss 11.2.0) — deferred behind the user's request this cycle |
| **User request** | "make the Agenta pure Agenta remove the ai skill coach" — remove "AI Skill Coach" branding; the app identity becomes purely AgentA. Applied per loop rules (explicit user request; Adviser concurs — the app's own UI already leads with AgentA) |
| **Verified "AI Skill Coach" surface** | `lib/main.dart:330` + `:458` (both MaterialApp `title:`), `pubspec.yaml:2` (`description: "AgentA - AI Skill Coach"`). **Zero platform-surface hits** (AndroidManifest/Info.plist/web/desktop swept — none carry it). **Zero test assertions on it.** |
| **Verified coach-wording surface** | `dashboard.dart:392` `'Tap "New Chat" to start coaching'`; `chat_input_bar.dart:32` `hintText: 'Ask your coach...'` |
| **Verified Agenta/AgentA case split (display strings)** | Wrong case "Agenta": `ai_model.dart:7,9,11,20`, `ai_service.dart:35`, `online_ai_service.dart:47,71`, `chat_error_classifier.dart:11`, `offline_model_banner.dart:94,103` (11 strings / 6 files). Correct "AgentA" already: dashboard :252, chats :35, chat_timeline_view :157, main :349, gemma/groq prompts, download_prompt_screen :168 ("Get AgentA…" — recon's truncation corrected) |
| **Internal identifiers — OUT OF SCOPE (must not change)** | `pubspec name: aiproject` (+ every `package:aiproject/` import), `app_constants.dart:2` dbName, `com.agenta.AgentA` package ids, `com.agenta.agenta/notification` channel id, `User-Agent` header values, github URLs, MainActivity.kt path |
| **TEST ASSERTION FOUND** | `test/chat_error_classifier_test.dart:25` + `:71` assert the exact legacy string ('Agenta Offline AI is still getting…') — **renaming requires updating these 2 assertion lines in the same cycle** (mechanical fixture update) |
| **Display-only confirmation** | logic-grep (`== 'Agenta`, `.contains('Agenta`, etc.) across lib+test → **empty**; strings are returned-for-display or passed as display params only |
| **Platform brand state (NEW FINDINGS)** | Android: `android:label="AgentA"` ✓ already correct. **iOS Info.plist: STALE TEMPLATE BRANDING — `CFBundleDisplayName "Aiproject"`, `CFBundleName "aiproject"`**. **web/index.html: `<title>aiproject</title>`, apple-mobile-web-app-title "aiproject", meta description "A new Flutter project."** + **web/manifest.json: name/short_name "aiproject"**. Desktop runners (linux/windows/macos): **no AgentA-branded strings, but the Reviewer confirmed Flutter-template "aiproject" strings ARE present** (B4 correction of the original "no brand strings found" note — see backlog rulings at closure) |
| CI | runs 38434757176 / 38436746278 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F23** | **Pure-AgentA rebrand (user request).** Remove "AI Skill Coach" (2 titles + pubspec description), replace 2 coach-copy lines, normalize 11 wrong-case "Agenta" display strings to "AgentA", update 2 test assertions, fix stale iOS/web template branding ("Aiproject"/"aiproject"). **SELECTED as the cycle-14 task (user request; Adviser concurs).** | UX / branding | sweep table above | middle-end + backend | CHEAP |
| **F11 part 3c-2..4** | **Small majors** (flutter_dotenv 6 — AppConfig-only surface, cupertino_icons 2, flutter_launcher_icons 0.14) — deferred behind the user's request; each its own cycle. | maintainability | pub outdated | middle-end | EXPENSIVE |
| **F11 part 4** | **^11 fss `checkUpgradeStatus()` follow-up** — GATED on the user cutting the next release tag. | maintainability | cycle-9 plan | middle-end | EXPENSIVE (gated) |
| **F6-residue** | `hashPassword` outside `tryUpgrade`'s try (login.dart:365,459) — theoretical only. | security (nit) | cycle-10 review | middle-end | CHEAP |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** — future-threshold warnings now visible in every CI run (informational); AGP 9 migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | Connectivity probe fresh HttpClient per call — same file as cycle 13's map; LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15 residue / F16 / F19** | Guard live; promote-landing staleness + zombie run accepted. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (14 cycles).** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: explicit user request outranks the queued majors; all surfaces verified display-only; the one behavioral-adjacent item (test assertions) is mechanical.

---

## Selected task (single): F23 — Pure AgentA rebrand

**Objective:** zero occurrences of "AI Skill Coach", "coach", or wrong-case "Agenta" in lib/, test/, and pubspec description; iOS + web surfaces carry "AgentA"; Android confirmed already-correct; internal identifiers untouched; all gates + CI green.

**Brand-spelling ruling:** normalize to **"AgentA"** everywhere (the repo's dominant brand: app bar, prompts, dialogs, and the user's own capitalization in context; "Agenta" appears only in display strings).

**STOP RULE (binding):** if any touched string turns out to be logic-bearing (key, comparison, persistence) — the sweep says none are, but the implementer verifies at edit time — STOP on that string and report; do not rename it.

**Version bump decision: none** — copy/config changes are not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — since every phase below is **CHEAP-class, no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch.

---

## Phase 1 — lib copy + pubspec description + test assertions (F23 part 1)

- **Phase id:** P1
- **Objective:** zero "AI Skill Coach"/"coach"/wrong-case "Agenta" in lib/ + test/ + pubspec description.
- **Responsible subagent:** middle-end
- **Files to change:** `lib/main.dart` (:330, :458 → `title: 'AgentA'`), `pubspec.yaml` (:2 → `description: "AgentA"` — version line untouched), `lib/presentation/dashboard/dashboard.dart` (:392 → `'Tap "New Chat" to start chatting with AgentA'`), `lib/presentation/chats/widgets/chat_input_bar.dart` (:32 → `hintText: 'Ask AgentA...'`), **Agenta→AgentA normalization**: `lib/services/ai/ai_model.dart` (:7 `'AgentA Image Gen'`, :9 `'AgentA Chatbot'`, :11 `'AgentA Offline AI'`, :20 `'Chat with the AgentA …'`), `lib/services/ai/ai_service.dart` (:35), `lib/services/ai/online_ai_service.dart` (:47, :71), `lib/core/utils/chat_error_classifier.dart` (:11), `lib/presentation/shared/offline_model_banner.dart` (:94, :103), **+ `test/chat_error_classifier_test.dart` (:25, :71 — assertions updated to the new exact strings)**
- **Implementation steps:**
  1. Apply the exact replacements above; change NOTHING else in those files (no formatting churn — the format gate guards it).
  2. At each edit, re-verify display-only (the sweep says yes; if any string turns out logic-bearing → STOP per the rule).
  3. Local validation: `flutter analyze` exit 0 (flutter_lints 6), `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` → 222/222 (the 2 updated assertions must still pass — the classifier's friendly() output now carries "AgentA").
  4. Repo-wide grep proof: `AI Skill Coach|coach` and wrong-case `Agenta` → zero matches in lib/ + test/ (excluding the pubspec `name: aiproject` and internal identifiers, which are untouched).
- **Acceptance criteria:** greps clean; 222/222; diffs = the listed lines only; internal identifiers byte-identical.
- **Verification:** **CHEAP** — display copy + mechanical test-fixture update; zero logic (sweep-verified).
- **Dependencies / sequencing:** first.
- **Expected result:** the app identity is purely AgentA in code.

## Phase 2 — Platform brand surfaces (F23 part 2)

- **Phase id:** P2
- **Objective:** iOS + web carry "AgentA"; Android recorded already-correct; desktop recorded no-brand.
- **Responsible subagent:** backend
- **Files to change:** `ios/Runner/Info.plist` (CFBundleDisplayName "Aiproject" → "AgentA"; CFBundleName "aiproject" → "agenta" — the ≤15-char internal name), `web/index.html` (`<title>aiproject</title>` → `<title>AgentA</title>`; apple-mobile-web-app-title "aiproject" → "AgentA"; meta description "A new Flutter project." → "AgentA — your offline-first AI assistant."), `web/manifest.json` (`"name": "AgentA"`, `"short_name": "AgentA"`)
- **Implementation steps:**
  1. Apply the plist/html/json value edits; NOTHING else in those files (structure, keys, and the rest of the manifest stay byte-identical).
  2. Android: verify (no-diff evidence) `android:label="AgentA"` already correct — change nothing.
  3. Desktop runners: record the no-brand finding (no AgentA/agenta/window-title strings found) — out of scope, no changes (Android-first app; desktop titles would be a separate decision).
  4. Local validation: `flutter analyze` exit 0; plist/XML well-formedness (manual inspection — plist has no linter in the loop; the Reviewer eyeballs the diff).
- **Acceptance criteria:** the 3 platform files carry AgentA; Android manifest untouched (evidence recorded); desktop untouched (recorded); diffs = value-only.
- **Verification:** **CHEAP** — platform display-name values; data-only edits (iOS is buildable-by-construction per the Podfile caveat — plist values are safe data).
- **Dependencies / sequencing:** independent of P1; batched.
- **Expected result:** springboard, web tab, and PWA install name all say AgentA.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `feat(branding): pure AgentA rebrand — remove AI Skill Coach, normalize brand spelling (F23)` — P1 files. (Type `feat(branding):` — a user-visible identity change; finalize at push confirmation.)
- Commit 2: `chore(branding): AgentA on iOS display name and web surfaces` — P2 files.
- Commit 3: `docs(plans): close cycle 13 and open cycle 14 plan` — stage `plans/` explicitly (deletion of old cycle-13 path, `plans/done/cycle-13-...md`, new cycle-14 file). Never root-wide `git add -A`/`git add .`
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); `pubspec.yaml` version line untouched (description-only change); internal identifiers byte-identical.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — copy/config changes with the manifest grep-guards still passing (the dataSync guard greps the manifest — P2 must not have touched it) + format gate + strict-lint analyze + 222/222 + APK build.
- **Promote to Landing** green as usual — the promoted APK is the branding smoke-test artifact (user advisory: launch the app; app label/springboard (after reinstall) show "AgentA"; no "AI Skill Coach" anywhere).
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-15 audit (pre-ranked: F11 part 3c-2 — flutter_dotenv 6).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

**None needed — stated honestly per the web-research skill:** every changed string is internal copy or platform display-name config with no external contract to verify (no API, no spec, no dependency behavior). The Reviewer's verification is repo-internal: greps, gates, and diff inspection. The one external-ish fact (CFBundleName ≤15-char convention) is noted in the plan, not load-bearing.

## Reviewer verification commands (single pass, after P1+P2)

1. Grep `lib/ test/ pubspec.yaml` for `AI Skill Coach|coach` → zero matches; for wrong-case `Agenta` → zero matches in lib/ + test/ (display strings normalized).
2. Grep the internal-identifier set (`aiproject` package imports, `com.agenta`, dbName, `User-Agent`) → byte-identical to HEAD (untouched).
3. `git diff pubspec.yaml` → description line only; version line untouched.
4. Platform diffs: Info.plist = the 2 value lines; web/index.html = 3 value lines; web/manifest.json = 2 value lines; AndroidManifest.xml = untouched (the CI dataSync guard depends on it).
5. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` 222/222, `dart format --output=none --set-exit-if-changed lib test` exit 0.
6. STOP-rule audit: no logic-bearing string was renamed (cross-check the sweep's display-only evidence).

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-14 | Cycle-14 audit recorded; plan created `active` (task F23 — user request). Recon verified and EXTENDED (iOS/web stale template branding found: "Aiproject"/"aiproject"; download_prompt_screen case corrected in recon; test assertions found at classifier_test :25/:71). Small majors deferred behind the user request. |
| 2026-10-14 | **P1+P2 IMPLEMENTED, SINGLE-PASS REVIEW PASS, PUSH APPROVED by Adviser.** Adviser independently verified: scope = exactly the planned files (10 P1 + 3 P2 + plans artifacts); **case-sensitive zero-match proof** for "AI Skill Coach"/"coach"/wrong-case "Agenta" across lib+test+pubspec (the Adviser's first grep was case-insensitive and false-positived on correct-case "AgentA" — redone with -CaseSensitive: clean); internal identifiers untouched in the diff (com.agenta / package:aiproject / dbName / User-Agent — zero hits); pubspec = description line only, **version line untouched (1.2.3+6)**; platform diffs value-only. Gates re-run — analyze exit 0, format 0 changed, 222/222. **Backlog rulings at closure:** **B1 ACCEPT** (stale doc comment chat_error_classifier.dart:5-6 "Brand copy is frozen" — backlog nit). **B2 ACCEPT-as-own-item** (desktop template "aiproject" strings — a separate desktop-identity decision, not accepted-as-fine). **B3 ACCEPT** (web/manifest.json description still "A new Flutter project." — one-liner pre-ranked into cycle 15 alongside flutter_dotenv 6). **B4 CORRECTED** — the ground-truth desktop note below is amended per the Reviewer (template strings ARE present in desktop runners; the original audit grep only proved absence of AgentA-brand strings). Commits: `feat(branding): pure AgentA rebrand — remove AI Skill Coach, normalize brand spelling (F23)` / `chore(branding): AgentA on iOS display name and web surfaces` / `docs(plans): close cycle 13 and open cycle 14 plan`. Version bump: none; next tag carries 1.2.4 and unlocks the ^11 fss follow-up. |
| pending | agent-push: push main (3 commits), watch BOTH workflows → **Build APK green** (copy/config changes; manifest grep-guards still pass — the dataSync guard greps the manifest, Android untouched), format gate + strict-lint analyze + 222/222 + APK build; Promote to Landing green — **the promoted APK is the branding smoke-test artifact** (launch the app: app label shows AgentA, no "AI Skill Coach" anywhere; springboard name after reinstall). On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-15 audit (pre-ranked: F11 part 3c-2 flutter_dotenv 6 + the B3 manifest-description one-liner + B1 comment nit). On red: capture `gh run view --log-failed`, plan stays `active`, fix phase planned. |

- Cycle-15 pre-ranked: **F11 part 3c-2** (flutter_dotenv 6 — AppConfig-only surface, map-first).
- F4, F5, F12 remain **CLOUD-BLOCKED** — live Supabase access required; standing user escalation (14 cycles). The ^11 fss follow-up remains gated on the user's next release tag.
- This plan is `done` only when P1+P2 PASS the single review, the push is Adviser-approved and executed, and BOTH workflows are green.
