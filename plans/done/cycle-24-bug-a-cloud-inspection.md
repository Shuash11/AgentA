# Cycle 24 — Bug A Read-Only Cloud Inspection (Supabase CLI / Management API) — zero mutations

**status:** active
**created:** 2026-10-15
**created by:** Adviser (self-improvement cycle 24 audit — the Bug A re-scope per the CLI grant)
**repo:** C:\projects\aiproject (AgentA) — branch main @ f9c52c4
**predecessors:** plans/done/cycle-1..23 (all closed, CI green; latest runs 38715001577 / 38716879093)

## Cycle 24 ground truth (fresh evidence, 2026-10-15)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — 24th consecutive clean cycle |
| `flutter test` | **241/241 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only the plans bookkeeping from the cycle-23 close |
| `flutter pub outdated` | flutter_secure_storage has LEFT the queue (11.2.0 current post-migration); the visible entries are the held edge_ai line (F26) |
| **The task** | Bug A (the login "Google sign-in was rejected" report): the app-side mapping is verified correct (login.dart:688-694); the root cause is the **Supabase cloud-side Google provider configuration**. The user granted **Supabase CLI access** ("i have supabase cli just use that") — this cycle is the **read-only inspection**: reachability → the live auth-provider config via the Management API → evidence + comparison → report. **ZERO mutations.** |
| CI | runs 38715001577 / 38716879093 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **BUG A → this cycle** | **The read-only cloud inspection** (re-scoped per the CLI grant; see cycle-23's re-scope + mutation-discipline ruling). Reachability → Management-API auth-config read → the `external_auth_google` block vs the app's `GOOGLE_SERVER_CLIENT_ID` → report. Zero mutations; **GCP SHA-1 registration remains a GCP Console action regardless**. **SELECTED as the cycle-24 task.** | cloud-inspection | login.dart:688-694 (mapping verified); the user's CLI grant | backend | CHEAP (read-only) |
| **F5 → cycle 25** | The `verify_recovery_code` SECURITY DEFINER RPC via `supabase db push` — **unblocked by the CLI grant**; mutation → the discipline; security reviews the SQL pre-deploy. Scheduled next after the inspection. | security / cloud | docs/backend-rls.md §H8 | backend + security | EXPENSIVE |
| **F12 → cycle 26** | The `sync-offline-user` Edge Function via `supabase functions deploy`. | logic / cloud | cycle-1 plan | backend | EXPENSIVE |
| **F4 → cycle 27** | Schema versioning via `supabase db pull` introspection → version-controlled migrations. | contract / cloud | cycle-1 plan | backend | EXPENSIVE |
| **F11 part 4** | fss 11 + the hook — **SHIPPED (cycle 22)**; the upgrade-in-place + skip-path device smoke tests remain the user's advisory. | maintainability | run 38675897935 | middle-end | closed |
| **F29** | The AI output-hygiene guard — **SHIPPED (cycle 23)**. | UX | run 38715001577 | middle-end | closed |
| **F18** | AGP-9 deferred-with-trigger + the Ubuntu 26 runner watch (due ~Oct 19 — 4 days out; the first post-date run is the observation point). | CI / toolchain | cycle-19 plan | backend | EXPENSIVE |
| **F27** | sqflite in-range refresh #2 — routine, schedulable. | maintainability | F25 record | middle-end | CHEAP |
| **F28** | softprops Node-20 nit — fold with future CI-actions work. | CI (nit) | tag-run 38601012205 | backend | CHEAP |
| **B2** | Desktop-identity — PARKED pending user direction. | branding | cycle-17 ruling | — | CHEAP (when triggered) |

Ranking rationale: the CLI grant makes the Bug A inspection the cheapest unblocked diagnostic with the highest user-value (the user cannot sign in with Google until the provider config is right); the cloud queue (F5/F12/F4) follows one-cycle-at-a-time under the mutation discipline.

---

## Selected task (single): Bug A — read-only Supabase cloud inspection

**Objective:** establish, from the LIVE project's own configuration and with captured evidence, whether the Supabase Google provider settings explain the rejected ID-token exchange — and state exactly what (if anything) must change, split into (a) Supabase-dashboard/CLI-actionable items, (b) GCP-Console items (SHA-1), and (c) any app-side items (expected: none). **ZERO mutations this cycle.**

**Version bump decision: none** — a read-only inspection changes nothing; the bookkeeping push is docs-only. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — the phase below is **CHEAP-class (read-only inspection), no e2e run occurs**; the Reviewer executes the verification commands itself. Definitive acceptance = post-push CI watch (the bookkeeping push; docs-only).

**CLOSE RULE (binding — how a read-only inspection cycle closes):**
- **If the inspection completes (findings or no-findings):** the cycle closes **WITHOUT a code push**. The only commit is the plans bookkeeping (`docs(plans): close cycle 23 and open cycle 24 plan`) + **the inspection report recorded in this plan file's cycle-status row** (the Adviser amends it from the phase report before the bookkeeping push). CI runs on the bookkeeping push (docs-only) and must be green.
- **If the inspection is BLOCKED** (CLI/token unavailability, Management-API capability absent): the blocked state + exact gap is recorded in the plan; the Adviser re-scopes (the user runs the specific dashboard checks manually, or a Management-API token path is arranged) — the cycle stays open until the evidence exists or the re-scope lands.

**MUTATION DISCIPLINE (binding, from the cycle-23 ruling):** this cycle is READ-ONLY. Any config change (PATCH) discovered to be needed becomes its own explicitly-planned phase with the exact commands and rollback note — it does NOT happen in this cycle, even if the inspection makes it look trivial.

---

## Phase 1 — The inspection (read-only evidence pass)

- **Phase id:** P1 (single phase)
- **Objective:** the live Google-provider auth config captured and compared; the capability boundary verified; a split report (Supabase-actionable / GCP-Console / app-side).
- **Responsible subagent:** backend
- **Files to change:** NONE (read-only; the evidence lands in the phase report → the Adviser records it in the plan)
- **Implementation steps (exact, bounded):**
  1. **Reachability:** `supabase --version`; if not authenticated, check for `SUPABASE_ACCESS_TOKEN` in the environment (NEVER echo it; never log it in full); `supabase projects list` → confirm project `pmeygoyubqiaqvsuyjzm` is reachable and capture its name/region/created-at ONLY.
  2. **Capability-boundary verification:** attempt the auth-config read via the Management API with the CLI's access token: `GET https://api.supabase.com/v1/projects/pmeygoyubqiaqvsuyjzm/config/auth` (the CLI-era Management API endpoint). If the endpoint/fields are unavailable in this CLI/API version, report EXACTLY what was attempted, the response (status + safe body excerpt — no tokens), and what remains dashboard-only. **This verification is itself a deliverable** (the true capability boundary, evidenced).
  3. **The comparison:** from the captured config, extract the `external_auth_google` block: `enabled`, `client_id`(s), `redirect_uri`(s), `skip_nonce_check` if present. Compare against the app's expectation: the configured client ID matches `GOOGLE_SERVER_CLIENT_ID` (compare **last-4 characters or a SHA-256 hash only** — never log the full secret/ID values), `enabled == true`, and the redirect-URL expectations. Record every mismatch verbatim (redacting secret values to last-4).
  4. **The split report:** (a) **Supabase-actionable** items (provider config the user can fix via Dashboard/Management API — with the exact setting names), (b) **GCP-Console items** (the SHA-1 registration for the installed APK's signing cert — the fingerprint is printed in every Build APK job summary; the user registers it as an Android OAuth client), (c) **app-side items** (expected: none — the mapping/validation is verified correct; if the inspection surprises us, record it).
  5. **Evidence discipline:** redact all secrets to last-4/hash; never echo tokens; capture statuses and safe excerpts only; if a command errors, record the error class (not raw tokens).
  6. **NO mutations:** if the config is wrong, DO NOT PATCH — the finding comes back to the Adviser for an explicitly-planned mutation phase.
- **Acceptance criteria:** the reachability result, the capability boundary (evidenced), the `external_auth_google` block (redacted), the comparison verdict, and the split report — or the precise blocked-state record.
- **Verification:** **CHEAP** — read-only inspection; the Reviewer re-runs the reachability checks if the token remains available (and otherwise verifies the captured evidence's internal consistency).
- **Dependencies / sequencing:** single phase.
- **Expected result:** the user knows EXACTLY why Google sign-in was rejected and exactly what to do — or the precise tooling gap.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1 (bookkeeping only): `docs(plans): close cycle 23 and open cycle 24 plan` — stage `plans/` explicitly (deletion of old cycle-23 path, `plans/done/cycle-23-...md`, new cycle-24 file). **No code changes ride this commit** (the close rule). Never root-wide `git add -A`/`git add .`
- **The inspection report itself is recorded in this plan file (the Adviser amends the cycle-status row from the phase report) — NOT as a code/docs change to the repo's docs** (it contains project-specific config evidence; the plans/ archive is the right home).
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report).
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — identical profile (docs-only bookkeeping). This run also serves the **F18 Ubuntu 26 watch** if it lands post-Oct 19: record deltas, observe only.
- **Promote to Landing** green as usual.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-25 audit — **pre-ranked: F5 (the recovery-code RPC deploy) as the first cloud-mutation cycle** (if the inspection's findings don't reprioritize), or the inspection-driven provider-config fix phase if a mismatch was found (that mutation phase comes back through the Adviser first).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `Supabase Management API projects config auth endpoint` (supabase.com/docs/reference/api — verify the exact `GET /v1/projects/{ref}/config/auth` endpoint, its auth header, and the `external_auth_google` field names; genuinely web-dependent this time — the capability boundary claim is load-bearing).
2. `supabase cli access token SUPABASE_ACCESS_TOKEN management api` (supabase.com/docs — how the CLI's token authorizes Management API calls outside `supabase` subcommands).

## Reviewer verification commands (single pass, after P1)

1. Evidence audit: the phase report contains the reachability result, the capability-boundary attempt (endpoint + response class), the redacted `external_auth_google` block, and the split report — with **zero full secrets/tokens anywhere** (grep the report for token-shaped strings).
2. Comparison audit: the mismatch verdict (if any) cites the redacted values and the app's expectation.
3. Mutation audit: **zero PATCH/POST/DELETE commands in the phase record** (read-only discipline).
4. Baseline gates: `flutter analyze` exit 0 (flutter_lints 6), `flutter test` 241/241, `dart format --output=none --set-exit-if-changed lib test` exit 0.
5. Scope: zero code diffs outside plans/; analysis_options.yaml absent; .opencode/ absent.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-15 | Cycle-24 audit recorded; plan created `active` (the Bug A read-only cloud inspection — zero mutations). The close rule defined: inspection report → the plan's cycle-status row → bookkeeping-only push; blocked → re-scope. The mutation discipline referenced (cycle-23 ruling). |
| 2026-10-15 | **P1 INSPECTION COMPLETE (read-only, zero mutations, evidence discipline held) — FINDINGS RECORDED PER THE CLOSE RULE.** (1) **Reachability:** CLI v2.115.0 (keyring-authenticated); `projects list` OK; project `pmeygoyubqiaqvsuyjzm` = "Shuash11's Project", Singapore, created 2026-08-19. (2) **Capability boundary (evidenced):** `GET /v1/projects/{ref}/config/auth` → **HTTP 200, 243 fields — fully available; NOTHING about the provider config remains dashboard-only**; fields are flat `external_google_*`; **no per-provider redirect-URI field** (redirects are global `site_url`/`uri_allow_list`); dashboard-only remains: auth-log CONTENT + GCP-side secret pairing. (3) **The config (redacted):** `external_google_enabled=true`; `external_google_client_id` set (len 72, sha256_16=C27DC0AC7FB7580D); `additional_client_ids=null`; secret set (len 64, last4 fa40); `skip_nonce_check=false`. (4) **Comparison verdict: the app's GOOGLE_SERVER_CLIENT_ID (len 72) is SHA-256 BYTE-EQUAL to the live Supabase value — EXACT MATCH; enabled ✓** (CI-secret byte-equality inferred via length + local match; GitHub secrets are write-only). (5) **Root-cause analysis: the provider config does NOT explain Bug A** — audience check passes; nonce ruled out as non-causal (`skip_nonce_check=false` diverges from the runbook's ON guidance but is latent-risk only); `at_hash` is token-level; **the remaining vector is "Unacceptable audience" from a STALE installed APK embedding a different client ID**. (6) **Split report:** (a) Supabase-actionable: NO required change; optional hardening = `skip_nonce_check=true` per the runbook; diagnostic = Dashboard → Logs → Auth holds the exact GoTrue rejection message. (b) **GCP-Console REQUIRED: register SHA-1 `11afea0ce4aece4e4f65b00aee30e073746a6d1b` (V2 signer, stable release keystore, from run 38715001577) as an Android OAuth client for `com.agenta.AgentA`**. (c) App-side: NONE. (7) Recommendation: next read-only diagnostic = the Auth log's exact GoTrue message + the installed APK's build provenance; the nonce PATCH + the SHA-1 registration are separately-scoped items. **RESIDUAL RULINGS (binding):** (a) the AUTH-LOG read is schedulable as a bounded read-only addendum to the cycle-25 F5 work (the Management-API logs endpoint is plausibly reachable with the same token; verify capability first; if dashboard-only → the exact dashboard steps for relay); (b) the GCP SHA-1 registration is the STANDING USER ACTION (exact steps relayed); (c) the `skip_nonce_check` PATCH is **NOT approved now** — non-causal for Bug A, and the current value is the safer posture; revisit only if the auth-log diagnosis implicates nonce handling; (d) the stale-APK provenance check is a USER ACTION (reinstall fresh from the v1.2.4 release; the debug-fallback era cannot be fixed by registration). **Cycle-25 TASK: F5 (the recovery-code RPC deploy) — the first cloud-MUTATION cycle, per the plan's pre-rank; the inspection did not reprioritize away from it; the bounded auth-log read rides as a read-only addendum.** The Reviewer arming for the inspection pass (the 2 searches + evidence/mutation audits) CONFIRMED as armed. |
| 2026-10-15 | **P1 INSPECTION COMPLETE, SINGLE-PASS REVIEW PASS (evidence/comparison/mutation audits all verified; the root-cause spot-checks re-verified in GoTrue source; reachability re-run live), BOOKKEEPING PUSH APPROVED by Adviser.** **Backlog rulings on the Reviewer's notes:** (1) the google-signin-setup.md:104,196 "Skip nonce checks: ON" runbook recommendation (official docs call it security-reducing) → **recorded as a docs-accuracy item TIED to the skip_nonce_check deferral** — the runbook correction rides whichever future cycle revisits the nonce question (per the residual ruling; not a standalone cycle). (2) the docs-sample field-count drift (238 vs 243) → **accepted as noted** (minor, illustrative sample, exact live count unverifiable). Push: bookkeeping-only commit `docs(plans): close cycle 23 and open cycle 24 plan` — zero code/config/workflow changes (verified; gates re-run: analyze 0, 241/241, format 0). Version bump: none. |
| pending | agent-push: bookkeeping push → CI watch (Build APK green — docs-only, identical profile; **F18 runner watch: still pre-Oct-19 — observe only**; Promote green as usual). On green: Adviser closes cycle 24 (physically moved) and cycle 25 begins — **delegate P1 (the migration + security review) to backend + security per `plans/cycle-25-f5-rpc-deploy.md`**, then P2 (the deploy + the auth-log addendum), the e2e run, the Reviewer pass, my push confirmation. On red: capture `gh run view --log-failed`, plan stays `active`, fix phase planned. |
- F4, F5, F12: the cloud family is UN-BLOCKED by the CLI grant — one mutation cycle at a time under the discipline. B2 remains parked. F29/F11-part-4 are SHIPPED.
- This plan is `done` only when P1 completes (or the blocked-state is recorded and the Adviser re-scopes), the bookkeeping push is Adviser-approved and executed, and BOTH workflows are green.
