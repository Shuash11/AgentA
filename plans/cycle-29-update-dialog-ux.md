# Cycle 29 — Update-dialog UX: remind-me-later + structured changelog

**status:** queued — starts ONLY after cycle-28 closure (the Part B dogfood evidence)
**created:** 2026-10-19 by Adviser (user feedback on the live v1.4.0 dialog)
**repo:** C:\projects\aiproject (AgentA) — surface: `lib/cubit/update/update_cubit.dart`, `lib/presentation/shared/update_available_dialog.dart`, (+ a small pure parser), tests
**task level:** **Level 2 — Standard** (behavioral changes in one repo: dismissal persistence semantics + a UI parser/renderer; no manifest/permission/auth/schema surface; no engine↔UI contract change — the changelog parsing is UI-layer against the already-contracted `notes` string). Contract gate: NOT triggered (decision recorded below).
**environment note:** skills are NOT in the loadable registry — read BY PATH: `C:\projects\aiproject\.opencode\skills\<name>\SKILL.md` (`ui-reference`, `oop-modularized`, `web-research`).

## User feedback (verbatim intent)
1. Tapping **"Later"** permanently suppresses the version (`dismissUntilNextVersion()` → `update_dismissed_version` in SharedPreferences). The user expects **"remind me later"** — e.g. 24 hours or next launch — not "never for this version".
2. The dialog shows version numbers + a **raw markdown dump**. The user wants a **proper changelog UI**: structured sections (New / Improved / Fixed), version + date, readable formatting, truncation, graceful fallback for unstructured bodies.

**Ownership note (recorded):** the per-version dismissal was the cycle-27 Adviser design (`dismissUntilNextVersion`); the user's feedback amends it. The raw-notes dump was the cycle-26 P5 renderer.

## Adviser rulings (binding)

1. **"Later" = a 24-hour snooze.** Persisted (`SharedPreferencesAsync`, new key `update_snoozed_until_epoch_ms`); the dialog re-shows when the snooze expires OR immediately on a **newer** version (a newer release always re-triggers, snooze or not). **Forced updates (`min-version:`) remain non-dismissible.** The old `update_dismissed_version` key is cleared once on migration (dead data, never read).
   - Rejected alternatives: session-only dismissal (loses the point of persisting — a reboot would re-nag immediately); a "don't show for this version" checkbox (adds a permanent-suppression path the user just objected to; can be added later if requested).
2. **Changelog parsing is UI-LAYER** (a small pure function + renderer in the presentation/shared layer) — **no contract amendment**: the engine keeps passing `notes` (the raw GitHub body) and `publishedAt`; how to RENDER notes is presentation logic. `contracts/update-engine.yaml` stays v1.1.1.
   - The parser is **lenient by contract**: recognizes `### New` / `### Improved` / `### Fixed` headers (case-insensitive, optional leading whitespace), renders each as a section with a Material icon (add / trending_up / build — `ink` icons, `accentInk` optional), items as bullets (`body` role); unknown H3 sections render generically with a neutral icon; bodies with NO recognized headers fall back to the current raw-notes treatment (inset-well scroll box, neumorphic); malformed input can never crash (pure function, total).
   - Version + date: the dialog header gains the release date from `remote?.publishedAt` (formatted; `null` → omitted).
   - **Show more:** sections longer than N items (spec: 5) collapse with an `accentInk` "Show more" TextLink (a local expansion state — no persistence).
3. **The neumorphism spec governs the visuals:** raised dialog (radius 28), inset wells, `ink`/`subtext`/`accentInk` per §3, icons per §5's second-channel rule (never color-only), motion per N9. Both fixes land IN the ratified style — no new components beyond the spec's language.
4. **"dont ask do it auto" alignment:** the 24h snooze *reduces* nagging (the platform's one system confirm per install remains the only unavoidable prompt — the recorded platform limit).

## Phases

### P1 — Remind-me-later (EXPENSIVE — persistence semantics + behavior)
- **Responsible:** frontend. Read BY PATH: `oop-modularized`, `web-research`, `ui-reference`.
- **Web-research (MANDATORY, declare per the skill):** in-app update-prompt "remind me later" interval conventions (24h vs next-launch; what major apps do) — ground the 24h choice or propose a better one WITH a citation.
- **Work:** the cubit — the snooze key + timestamp logic, `shouldShow` updated (forced always; available ∧ snooze-expired; newer-version override), the old-key migration/clear, the host's post-close path calls the snooze (replacing `dismissUntilNextVersion`), the `_isShadow`-era tests updated + new tests (snooze expiry boundary, newer-version override, forced override, migration).
- Gates: analyze 0; suite green (record count).

### P2 — Structured changelog UI (EXPENSIVE — new UI + parsing behavior)
- **Responsible:** frontend. Read BY PATH: `ui-reference`, `oop-modularized`, `web-research` (declaration: not required beyond P1's unless a rendering question arises).
- **Work:** the pure parser (total, lenient, per ruling 2) + its unit tests (recognized headers, unknown sections, no-headers fallback, empty/bodyless, >5-item truncation); the neumorphic sectioned renderer (version + date header, per-section icons, bullets, Show more); wire into `update_available_dialog.dart` (replacing the raw dump); the fallback path tested against a real unstructured body.
- Gates: analyze 0; suite green (record count).

### e2e ONCE (gating) → Reviewer ONCE
- e2e: the dialog scenarios (Later → gone for the session, re-shows after the snooze [test-seam time travel], newer version re-triggers immediately, forced non-dismissible; structured changelog renders sections; unstructured fallback renders) + the update-feature regression + a light standing-flow pass (the dialog is the only touched surface).
- Reviewer checklist: the snooze semantics vs this plan; the migration (the old key never read); the parser totality (no crash paths); the fallback coverage; the neumorphism conformance (§3/§5); scope (cubit + dialog + parser + tests ONLY); baseline gates re-run; declarations present.

## Push guidance (AMENDED 2026-10-19 — the bump finalized + the two-cut dogfood)
- Version bump: **patch `1.4.1+1`** — FINAL (v1.4.1 was never published; the natural next semver is reclaimed; the preliminary `1.4.2` becomes the dogfood release).
- Commits: the snooze+changelog feature (one commit — the shared test file forces the P1/P2 fold) / docs+contract-doc correction / the pubspec bump — atomic; explicit staging; never root-wide `git add`; `.opencode/` excluded.
- **The dogfood chore (pre-authorized):** `chore(release): bump version to 1.4.2+1 (C28/C29 dogfood)` — pubspec only — cut as `v1.4.2` after v1.4.1 is installed on the device; the in-app update v1.4.1 → v1.4.2 is the Part B evidence for BOTH cycles.

## Reviewer web searches (per the web-research skill, read from `.opencode/skills/web-research/SKILL.md`)
1. In-app update-prompt "remind me later" interval conventions (24h vs next-launch) in mainstream apps.
2. Release-notes/changelog rendering practice (structured sections + fallback) in Flutter/mobile apps.

## Governance
| Date | Event |
|---|---|
| 2026-10-19 | Plan created `queued` (user feedback on the live v1.4.0 dialog; gated on cycle-28 closure). Classifications: P1 EXPENSIVE; P2 EXPENSIVE; e2e EXPENSIVE. The dismiss decision (24h snooze), the UI-layer parsing decision (no contract bump), and the patch-bump preliminary recorded. |
| 2026-10-19 | **E2E PASS (4/4) + REVIEWER PASS (7/7) → PUSH APPROVED (Adviser, bump FINAL — revised).** Gates: analyze 0 / **292→291+? suite green (292 reported)** / format 0; e2e 4/4 (the six snooze sub-cases asserted directly; the changelog renderer incl. the raw fallback byte-identical; the REAL channel: v1.4.0's body is H2-only → graceful fallback, `level=none`); Reviewer 7/7 (snooze semantics field-for-field; the parser pure+total, 24 tests; §5-compliant renderer; scope exact — the contract untouched at v1.1.1, pubspec untouched). **Bump ruling: `1.4.1+1` FINAL — v1.4.1 was NEVER published** (verified: no tag, no release record — the F15 logic confirms), so the natural next semver is reclaimed; the preliminary `1.4.2` becomes the DOGFOOD release instead. **Commit plan (3 commits — the shared test file forces the P1+P2 fold):** A `feat(update): 24-hour snooze instead of per-version dismissal + structured changelog UI (C29 P1/P2)` (cubit + host + `release_notes_parser.dart` [new] + dialog + `update_feature_test.dart` + `release_notes_parser_test.dart` [new] + `update_install_flow_test.dart`; **the stale `UpdateCubit` class-doc fix folds here** — same file, the Reviewer's note 1) → B `docs(plans): record cycle-29 governance; correct the update-engine contract doc (C29)` (plans/cycle-29… + `contracts/update-engine.yaml` → **v1.1.2, DOC-ONLY: the transition_rules stanza names the snooze API instead of the removed `dismissUntilNextVersion`** — the Reviewer's note 2 ruled corrected NOW: a contract naming a removed method must not ship, even though the cycle-29 "contract untouched" ruling held for the implementation) → C `chore(release): bump version to 1.4.1+1 (C29)` (pubspec only, Adviser-authorized). **Post-push sequence (the fold corrected on one mechanical point):** CI green → cut `v1.4.1` → the 1.3.1 device's OLD dialog fires for v1.4.1 (≠ the dismissed 1.4.0) → **Update = the 1.3.1 BROWSER handoff — the in-app flow shipped in 1.4.0 and cannot run on 1.3.1** (the fold's item 2 corrected) → install v1.4.1 (same signature, data preserved) → the device now runs the snooze+changelog build → **Push 2** (`chore(release): bump version to 1.4.2+1 (C28/C29 dogfood)`, pubspec only, pre-authorized here) → CI → cut `v1.4.2` → **Part B: the device on v1.4.1 (the NEW code) discovers v1.4.2 → the NEW dialog (the structured changelog live) → Update → in-app download with progress → sha256+size verified → the ONE system confirm → installed over v1.4.1 → data preserved** → report → **the Adviser closes cycles 27 + 28 + 29 together** (one evidence chain: the dialog proof [27], the in-app flow [28], the UX fixes live [29]). |
