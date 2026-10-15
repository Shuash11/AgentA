# Cycle 25 — F5: Deploy the `verify_recovery_code` RPC (the first cloud-mutation cycle) + the bounded Bug A auth-log read

**status:** active
**created:** 2026-10-15
**created by:** Adviser (self-improvement cycle 25 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ f9c52c4
**predecessors:** plans/done/cycle-1..24 (all closed, CI green; latest runs 38715001577 / 38716879093); cycle-24's inspection findings recorded in its closure row

## Cycle 25 ground truth (fresh evidence, 2026-10-15)

| Check | Result |
|---|---|
| Gates | expected exit 0 / 241/241 — verify at execution |
| The mutation | `supabase db push` deploys the repo's migrations including **the `verify_recovery_code` SECURITY DEFINER RPC documented in `docs/backend-rls.md` §H8 and the RLS file's :68-81 comment block** — the H8 target. The work order (bounded): create the migration file FIRST (a repo commit), THEN push. |
| The Bug A addendum | bounded **read-only** auth-log read (the Management-API logs endpoint with source=auth if available — verify capability first, per the cycle-24 ruling) — captures the exact GoTrue rejection message for the failed sign-in attempt. |
| The cycle-24 findings | provider config EXACT-MATCHES the app (audience passes); `skip_nonce_check=false` is non-causal (PATCH not approved); **the remaining vectors: the GCP SHA-1 registration (USER ACTION) + the stale-APK provenance (USER ACTION) + the auth-log read (this cycle's addendum)**. |
| CI | runs 38715001577 / 38716879093 green; runner ubuntu-24.04 (pre-Oct-19); F18 Ubuntu 26 watch pending. |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F30 → BLOCKING (new 2026-10-15)** | **Production project PAUSED (INACTIVE)** — the app's cloud auth/sync has been down since the pause; gates the entire cloud family (F5 deploy, F12, F4). Free-plan auto-pause after ~7 days of low activity; restore window 1 year; restore preserves data + configs. AMENDS cycle-24's Bug A ruling: paused project = primary suspect for post-pause sign-in failures; SHA-1 + stale-APK user actions stand. | cloud / infra | P2 step-1 evidence: link → "project is paused"; GET /v1/projects/{ref} → `status: INACTIVE`; DNS failure; logs 404/410 | user (restore) + backend (post-restore verify) | USER ACTION → EXPENSIVE verify |
| **F5 → THIS CYCLE** | **Deploy the `verify_recovery_code` RPC** — closes the documented H8 security TODO (the client currently compares hashes locally; the RPC moves verification server-side). The FIRST cloud-mutation cycle under the discipline (cycle-23 ruling): explicitly planned, backend executes, **security reviews the SQL pre-deploy**, before/after evidence, production-data rails. | security / cloud | docs/backend-rls.md §H8; the RLS file's :68-81 comment block | backend + security | **EXPENSIVE** |
| **Bug A addendum → THIS CYCLE (bounded read-only)** | The auth-log read for the exact GoTrue rejection message (cycle-24 residual ruling a). | cloud-inspection | cycle-24 closure row | backend | CHEAP (read-only addendum) |
| **F4 / F12 / Bug A user actions** | F4 schema pull (cycle 27 per sequencing); F12 Edge Function (cycle 26); the GCP SHA-1 registration + the stale-APK reinstall = **USER ACTIONS** (relayed). | contract / logic / cloud | cycle-24 closure row | backend / user | EXPENSIVE / user |
| **F18** | AGP-9 deferred-with-trigger + the Ubuntu 26 runner watch (first post-Oct-19 run). | CI / toolchain | cycle-19 plan | backend | EXPENSIVE |
| **F26 / F27 / F28** | edge_ai 2.x (deferred-with-trigger); sqflite refresh #2 (post-F5); softprops Node-20 nit. | maintainability / CI | cycle-21/22 plans | middle-end / backend | CHEAP-EXPENSIVE |
| **B2** | Desktop-identity — PARKED. | branding | cycle-17 ruling | — | — |

Ranking rationale: F5 is the plan's pre-ranked first mutation cycle; the inspection didn't reprioritize. The security review gate makes it the model for every future cloud mutation.

---

## Selected task (single): F5 — deploy the `verify_recovery_code` RPC (mutation) + the Bug A auth-log read (read-only addendum)

**Objective:** the `verify_recovery_code(p_code_hash)` SECURITY DEFINER function exists in the LIVE project (deployed from a version-controlled migration), verified callable, with the security review recorded; PLUS the exact GoTrue rejection message captured from the auth logs (read-only) for Bug A's diagnosis. **The app-side switch to the RPC (`UserRepository.verifyRecoveryCodeViaRpc` → `_db.rpc(...)`) is a FOLLOW-UP code cycle — this cycle is the DEPLOY + verification only** (the RPC is additive; the client keeps working unchanged until the switch lands).

**Version bump decision: none** — a backend mutation + a read-only diagnostic change no app version. Final.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **P2 is EXPENSIVE (a production-database mutation), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch + the deploy evidence.

**MUTATION DISCIPLINE (binding, the cycle-23 ruling applies verbatim):** the exact commands are in this plan; backend executes; security reviews pre-deploy; before/after evidence captured; production-data rails (never touch unrelated resources; no autonomous retries of failed destructive steps; failures reported immediately); the access token never committed/logged in full.

**STOP RULE (binding):** if the RPC's SQL cannot be reconciled with the live schema (the migration references columns/tables the introspection shows missing), or `supabase db push` fails in a way that indicates schema drift → STOP the mutation immediately, report the exact state, and the Adviser re-scopes (a failed push is reported, never force-repaired autonomously).

## STOP RULING (2026-10-15 — P2 stopped pre-deploy, Adviser re-scope)

**What fired:** P2 step 1 found the production project unusable — `supabase link --project-ref pmeygoyubqiaqvsuyjzm` → "project is paused"; Management API `GET /v1/projects/pmeygoyubqiaqvsuyjzm` → 200 with `status: INACTIVE`; PostgREST probe → DNS failure (paused projects shed endpoints); the logs endpoints → 404 / 410 Gone. **No `supabase db push` was attempted; no unpause, no retries, no force-repair; zero commits (HEAD still 74b47f3); the untracked 0002 migration is the only repo delta.** Discipline held. P1 is COMPLETE and green (analyze exit 0, 241/241; security review PASS 9/9 — `search_path` pinned, `auth.uid()`-only scope, boolean return, idempotent, schema-qualified references, EXECUTE-to-PUBLIC acceptable). The repo was never linked (`supabase migration list` → LINKED empty).

**Rulings (Adviser, 2026-10-15):**
1. **Re-scope: land P1 now; block the deploy on the user.** The plan stays `active`. P2's deploy portion is **BLOCKED** on a deliberate user action (project restore — below). P1's reviewed artifact is an untracked file — fragile — so the two planned commits land **NOW**, before the e2e/Reviewer gates, as a **STOP-ruling exception** to the post-review push order. This approval is **bookkeeping-only**: CI green on these commits does NOT complete the plan. The gates for the resumed P2 are unchanged: e2e once → single Reviewer pass → Adviser closure.
2. **New finding F30** (ranked first in the backlog): the production project is PAUSED — the app's cloud auth/sync has been down since the pause. It **gates the entire cloud family** (F5 deploy, F12, F4). Cycle-24's residual ruling is **AMENDED, not overturned**: the GCP SHA-1 registration + stale-APK user actions stand, but the paused project is the **primary suspect** for any sign-in failure after the pause date. Diagnosis order becomes: restore → reproduce → read the fresh auth log → judge the residual vectors against fresh evidence. (Cycle-24 observed live cloud auth, so the pause postdates it; Free-plan auto-pause fires after ~7 days of low activity, and Supabase emails the owner a warning ~1 week before + a confirmation after — the email dates fix the outage window.)
3. **Bug A addendum CLOSED for this cycle.** Doubly blocked: the attempted endpoint shapes do not exist (404) / are gone (410), and the original failed sign-in predates the pause — its log entry is treated as unrecoverable (the log store was unreachable while paused; retention is plan-dependent — the commonly cited Free-plan figure of ~1 day is UNVERIFIED this session). **Terminal resolution:** the Dashboard fallback is the standing path (Dashboard → project → Logs → Auth → filter by the failed attempt's timestamp → read the GoTrue rejection message, redacted) — the user attempts it once post-restore; if the entry is absent, record **"beyond retention — unrecoverable"** and the diagnosis proceeds from a **fresh reproduction**: reproduce the failed sign-in once from the installed app while the project is live, then read the fresh entry within the retention window.
4. **e2e-tester and Reviewer correctly NOT run — confirmed.** There is no deploy to exercise and no plan-work to audit; running either now would be a no-op against a paused project and would violate the gate order (the e2e run precedes the single Reviewer pass). What IS verified: P1's local gates, the recorded security review, and (pending) CI on the landing commits.

**Load-bearing invariant (pinned for every future review of this function):** the `p.id = auth.uid()` predicate is what makes PUBLIC EXECUTE safe. Removing it in any future edit turns the function into a cross-user recovery-code oracle. Any change to this function re-runs the security review gate.

**User actions (relay verbatim; nothing programmatic, no autonomous cloud mutation):**
1. Restore: Dashboard → organization → the paused project → **Resume project** (https://supabase.com/dashboard/project/pmeygoyubqiaqvsuyjzm). Verified per current Supabase docs: the restore window is up to 1 year from the pause, and the project returns to its previous state including data and configurations. Restore promptly — every day paused keeps the app's cloud down.
2. After restore: confirm the project shows ACTIVE; spot-check Table editor → `public.profiles` (rows present, `recovery_code` column present).
3. Check the project owner's inbox for the two pause emails (warning + confirmation) and record their dates — this fixes the outage start and sharpens F30 / Bug A.
4. When `supabase link` prompts, supply the DB password (or reset it first: Settings → Database → reset database password — also a user action). **Never committed or logged.**
5. Optional, post-deploy: the fresh Bug A reproduction (ruling 3).

**Resumed P2 (same phase, amended steps; MUTATION DISCIPLINE and STOP RULE unchanged):**
0. **Precondition:** the user confirms the project is ACTIVE post-restore. Then `supabase link --project-ref pmeygoyubqiaqvsuyjzm` (DB password from the user at the prompt; never logged/committed); confirm linkage via `supabase migration list` (LINKED column populated).
1. Before-state: routine-existence introspection — expect the function ABSENT (no push ever ran).
2. THE MUTATION: one `supabase db push`. If the remote migration history lacks 0001, the push applies BOTH files — both are idempotent by design (`drop policy if exists` + create; `create or replace`); record exactly what the push names.
3. After-state: re-run the introspection (function present) + the smoke call `select verify_recovery_code('nonexistent-hash');` → expect `false`.
4. Addendum: CLOSED (ruling 3) — skip the programmatic read; relay the dashboard-fallback / fresh-reproduction step to the user.
5. STOP rule unchanged: push failure or unexpected post-state → STOP, capture the exact output, report. No force-repair, no re-run loops.

**Research note (2026-10-15, Adviser):** the `web-research` skill is unregistered in this environment; the equivalent was executed directly. Verified: Supabase "Project Pausing" (Free-plan auto-pause after ~7 days of low activity; restore window up to 1 year; restore preserves data + configurations; owner warning + confirmation emails) — https://supabase.com/docs/guides/platform/pausing-projects; Supabase "Logs in Studio" (Dashboard Logs → Auth log type; retention depends on pricing plan) — https://supabase.com/docs/guides/platform/logs. Unverified this session: the exact Free-plan retention figure (~1 day) — the docs defer to the pricing page; the addendum's terminal resolution does not depend on it.

---

## Phase 1 — The migration + security review (repo work, pre-deploy)

- **Phase id:** P1
- **Objective:** the RPC exists as a version-controlled migration file, security-reviewed, ready to push.
- **Responsible subagent:** backend (+ the security agent's review gate)
- **Files to change:** NEW `supabase/migrations/0002_verify_recovery_code.sql` (the RPC per docs/backend-rls.md §H8 + the RLS file's :68-81 comment block — the exact function the docs specify: `verify_recovery_code(p_code_hash text) returns boolean`, SECURITY DEFINER, compares against the `auth.uid()` row's stored hash)
- **Implementation steps:**
  1. Read `docs/backend-rls.md` §H8 + the RLS file's :68-81 block — the documented function shape is the source of truth.
  2. Create `supabase/migrations/0002_verify_recovery_code.sql` with the documented function (idempotent: `create or replace function`).
  3. **SECURITY REVIEW GATE:** the security agent reviews the SQL: SECURITY DEFINER + `search_path` pinned (`set search_path = public`), the function compares ONLY the `auth.uid()` row (no cross-user leakage), the return is boolean (the hash never leaves the server), and idempotency. The review verdict is recorded in the phase report.
  4. Local validation: `flutter analyze` exit 0, `flutter test` → 241/241 (the SQL doesn't touch Dart — hygiene run), `git diff` = the migration file only (+ the plans bookkeeping).
  5. **STOP:** if the docs and the migration diverge, or the security review rejects → STOP; record.
- **Acceptance criteria:** the migration file exists, matches the documented shape, security-reviewed; Dart untouched.
- **Verification:** **CHEAP** (repo-only) — the EXPENSIVE verification is P2's deploy + e2e.
- **Dependencies / sequencing:** first; P2 pushes what P1 produced.
- **Expected result:** a reviewed, version-controlled migration ready for `supabase db push`.

## Phase 2 — Deploy + verify + the Bug A auth-log read

- **Phase id:** P2
- **STATUS 2026-10-15: BLOCKED pre-mutation (STOP RULING below) — production project INACTIVE; user restore pending. Resume ONLY per the amended steps in the STOP RULING section.**
- **Objective:** the RPC live in the project; callable-verification evidence; the GoTrue rejection message captured (read-only).
- **Responsible subagent:** backend
- **Files to change:** the LIVE project's functions (via `supabase db push`) — no repo code changes
- **Implementation steps (exact commands, bounded):**
  1. **Pre-deploy evidence:** capture the function's absence (the before-state introspection: the routine-existence query via the CLI's SQL capability if available; if the before-state cannot be captured without mutation-tooling risk, record the limitation and rely on the push's own output as evidence).
  2. **THE MUTATION:** `supabase db push` (linked to `pmeygoyubqiaqvsuyjzm`) — deploys the repo's pending migrations (0002). Capture the full push output (it names the applied migration).
  3. **Post-deploy verification:** re-run the routine-existence introspection (the after-state); optionally a `select verify_recovery_code('nonexistent-hash');` smoke call expecting `false` (a read-only function call — it mutates nothing).
  4. **The Bug A addendum (read-only):** attempt the auth-log read: `GET https://api.supabase.com/v1/projects/{ref}/logs?source=auth` style (verify the exact endpoint shape per the docs; **capability check first**). Capture the GoTrue rejection entries around the failed sign-in attempt (timestamps/provider) — redact tokens/emails to hashes/last-4. **If the logs endpoint is unavailable → record the exact dashboard steps for relay** (Dashboard → Logs → Auth → filter by the failed attempt's timestamp → read the GoTrue rejection message) and STOP the addendum there. **CLOSED 2026-10-15 (STOP RULING, ruling 3) — see the ruling for the terminal resolution and the fresh-reproduction path.**
  5. **STOP rule for mutations:** if the push fails or the post-state is unexpected → STOP, capture the exact output, report. **No force-repair, no re-run loops, no schema surgery.**
- **Acceptance criteria:** the push output names 0002 applied; the post-state introspection shows the function; the smoke call returns false; the auth-log read yields the GoTrue message or the documented dashboard fallback; zero unrelated resources touched.
- **Verification:** **EXPENSIVE** — a production mutation. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: the repo gates (analyze ×2, 241/241, format 0) + the deploy-evidence audit (before/after introspection, the push output, the smoke-call result) + the addendum's redaction audit.
- **Dependencies / sequencing:** after P1's reviewed migration. The app-side RPC switch is a FOLLOW-UP cycle (the RPC is additive).
- **Expected result:** the H8 server-side verification capability is LIVE (the documented TODO closed at the infrastructure layer); Bug A's exact rejection message is in hand (or the dashboard fallback recorded).

## Push guidance (Adviser confirmation GRANTED 2026-10-15 — see STOP RULING)

- **Adviser approval GRANTED 2026-10-15 (STOP-ruling exception):** both commits land NOW, before the e2e/Reviewer gates — bookkeeping only; CI green on them does NOT complete the plan (closure still requires the resumed P2 + e2e + Reviewer + deploy evidence).
- Commit 1: `feat(backend): add the verify_recovery_code SECURITY DEFINER migration (F5/H8)` — stage `supabase/migrations/0002_verify_recovery_code.sql` only. Atomic.
- Commit 2 (amended by the STOP RULING — the cycle-24 closure move is already committed): `docs(plans): record cycle-25 STOP ruling and re-scope (P2 blocked on project restore)` — stage `plans/cycle-25-f5-rpc-deploy.md` explicitly. Never root-wide `git add -A`/`git add .`
- Push order: both commits to main → CI watch (the standard migration-only run — no app-code change) → **the `supabase db push` executes as part of P2's phase work against the live project (NOT a CI step)** — the CI run on main is the bookkeeping validation; the deploy is the phase action with its own evidence.
- Exclusions: all `.opencode/` churn; `analysis_options.yaml` is committed state (any local diff = stop and report); the access token never committed or logged.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — identical profile (a migration-file + plans commit; no app-code change). Watch the **F18 Ubuntu 26 runner** if post-Oct 19: record deltas, observe only.
- **Promote to Landing** green as usual.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase.
- **AMENDED 2026-10-15 (STOP RULING):** green CI on the landing commits is bookkeeping validation only. The plan is NOT done: closure still requires the resumed P2 (deploy evidence), the once-per-plan e2e run, the single Reviewer pass, and both workflows green on the final state.
- On green (after the resumed P2 + e2e + Reviewer): Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-26 audit (pre-ranked: F12 — the Edge Function deploy, the second mutation cycle; then F4 schema pull; the app-side RPC switch as its own code cycle).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `Supabase Management API logs endpoint source auth` (supabase.com/docs — verify the logs-read endpoint/shape for the Bug A addendum; capability check is load-bearing).
2. `supabase db push linked project migrations` (supabase.com/docs — the push semantics + the applied-migration output shape).
3. `postgres security definer set search_path best practice` (the security review's checklist basis).

## Reviewer verification commands (single pass, after P1+P2)

1. Migration audit: `git diff` → the new 0002 migration matching the documented §H8 shape; idempotent (`create or replace`); `search_path` pinned; boolean return; no cross-user access.
2. Security-review audit: the security agent's verdict recorded (the review gate happened BEFORE the deploy).
3. Deploy-evidence audit: the before/after introspection (function absent → present), the push output naming 0002, the smoke call `false`.
4. Addendum audit: the auth-log read evidence (redacted) OR the documented dashboard fallback; **zero full tokens/emails**.
5. Mutation-discipline audit: zero commands outside the planned set; zero unrelated resources touched; the STOP rule available and unused-or-documented.
6. Baseline gates: `flutter analyze` exit 0, `flutter test` 241/241, format exit 0.
7. Scope: the migration file + plans only (no app code); analysis_options.yaml absent; .opencode/ absent.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-15 | Cycle-25 audit recorded; plan created `active` (task F5 — the first cloud-mutation cycle + the bounded Bug A auth-log read addendum). The cycle-24 findings recorded; the residual rulings issued (auth-log = bounded addendum; SHA-1 = user action; nonce PATCH not approved; stale-APK = reinstall). |
| 2026-10-15 | **STOP RULING (P2 pre-deploy):** production project INACTIVE (paused — link refused, DNS shed, logs endpoints 404/410); NO mutation attempted; discipline held; P1 complete + security review PASS 9/9. Adviser re-scope: P1 artifact lands via the two planned commits (bookkeeping-only exception); P2 deploy BLOCKED on the user's project restore (1-year window; data preserved); **F30 added** (project paused — gates the cloud family; AMENDS Bug A); Bug A addendum CLOSED (dashboard fallback + plan-dependent retention as terminal resolution; fresh reproduction post-restore is the standing path); e2e/Reviewer correctly not run. Amended P2 steps in the STOP RULING section. |
| pending | P1 (migration + security review) → P2 (deploy + verify + the addendum) → **once-per-plan e2e run (required)** → single Reviewer pass → Adviser push confirmation → bookkeeping push + CI watch → on green: close plan, open cycle-26 audit (F12 — the Edge Function deploy). |

- Cycle-26 pre-ranked: **F12** (the Edge Function deploy — the second mutation cycle). Then F4 (schema pull, cycle 27). The app-side RPC switch (UserRepository → `_db.rpc`) is its own code cycle after F5's deploy is verified.
- F4, F5, F12: the cloud family proceeds one mutation cycle at a time under the discipline. **The GCP SHA-1 registration + the stale-APK reinstall remain the user's Bug A actions.** B2 parked. F18 deferred-with-trigger + the runner watch.
- This plan is `done` only when P1+P2 PASS review (after the e2e run), the push is Adviser-approved and executed, and BOTH workflows are green.
