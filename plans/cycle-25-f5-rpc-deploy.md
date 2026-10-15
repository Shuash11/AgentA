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
- **Objective:** the RPC live in the project; callable-verification evidence; the GoTrue rejection message captured (read-only).
- **Responsible subagent:** backend
- **Files to change:** the LIVE project's functions (via `supabase db push`) — no repo code changes
- **Implementation steps (exact commands, bounded):**
  1. **Pre-deploy evidence:** capture the function's absence (the before-state introspection: the routine-existence query via the CLI's SQL capability if available; if the before-state cannot be captured without mutation-tooling risk, record the limitation and rely on the push's own output as evidence).
  2. **THE MUTATION:** `supabase db push` (linked to `pmeygoyubqiaqvsuyjzm`) — deploys the repo's pending migrations (0002). Capture the full push output (it names the applied migration).
  3. **Post-deploy verification:** re-run the routine-existence introspection (the after-state); optionally a `select verify_recovery_code('nonexistent-hash');` smoke call expecting `false` (a read-only function call — it mutates nothing).
  4. **The Bug A addendum (read-only):** attempt the auth-log read: `GET https://api.supabase.com/v1/projects/{ref}/logs?source=auth` style (verify the exact endpoint shape per the docs; **capability check first**). Capture the GoTrue rejection entries around the failed sign-in attempt (timestamps/provider) — redact tokens/emails to hashes/last-4. **If the logs endpoint is unavailable → record the exact dashboard steps for relay** (Dashboard → Logs → Auth → filter by the failed attempt's timestamp → read the GoTrue rejection message) and STOP the addendum there.
  5. **STOP rule for mutations:** if the push fails or the post-state is unexpected → STOP, capture the exact output, report. **No force-repair, no re-run loops, no schema surgery.**
- **Acceptance criteria:** the push output names 0002 applied; the post-state introspection shows the function; the smoke call returns false; the auth-log read yields the GoTrue message or the documented dashboard fallback; zero unrelated resources touched.
- **Verification:** **EXPENSIVE** — a production mutation. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: the repo gates (analyze ×2, 241/241, format 0) + the deploy-evidence audit (before/after introspection, the push output, the smoke-call result) + the addendum's redaction audit.
- **Dependencies / sequencing:** after P1's reviewed migration. The app-side RPC switch is a FOLLOW-UP cycle (the RPC is additive).
- **Expected result:** the H8 server-side verification capability is LIVE (the documented TODO closed at the infrastructure layer); Bug A's exact rejection message is in hand (or the dashboard fallback recorded).

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `feat(backend): add the verify_recovery_code SECURITY DEFINER migration (F5/H8)` — the migration file. Atomic.
- Commit 2: `docs(plans): close cycle 24 and open cycle 25 plan` — stage `plans/` explicitly (deletion of old cycle-24 path, `plans/done/cycle-24-...md`, new cycle-25 file). Never root-wide `git add -A`/`git add .`
- Push order: both commits to main → CI watch (the standard migration-only run — no app-code change) → **the `supabase db push` executes as part of P2's phase work against the live project (NOT a CI step)** — the CI run on main is the bookkeeping validation; the deploy is the phase action with its own evidence.
- Exclusions: all `.opencode/` churn; `analysis_options.yaml` is committed state (any local diff = stop and report); the access token never committed or logged.
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — identical profile (a migration-file + plans commit; no app-code change). Watch the **F18 Ubuntu 26 runner** if post-Oct 19: record deltas, observe only.
- **Promote to Landing** green as usual.
- On red: capture `gh run view <id> --log-failed`, plan stays `active`, Adviser plans the fix phase.
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-26 audit (pre-ranked: F12 — the Edge Function deploy, the second mutation cycle; then F4 schema pull; the app-side RPC switch as its own code cycle).

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
| pending | P1 (migration + security review) → P2 (deploy + verify + the addendum) → **once-per-plan e2e run (required)** → single Reviewer pass → Adviser push confirmation → bookkeeping push + CI watch → on green: close plan, open cycle-26 audit (F12 — the Edge Function deploy). |

- Cycle-26 pre-ranked: **F12** (the Edge Function deploy — the second mutation cycle). Then F4 (schema pull, cycle 27). The app-side RPC switch (UserRepository → `_db.rpc`) is its own code cycle after F5's deploy is verified.
- F4, F5, F12: the cloud family proceeds one mutation cycle at a time under the discipline. **The GCP SHA-1 registration + the stale-APK reinstall remain the user's Bug A actions.** B2 parked. F18 deferred-with-trigger + the runner watch.
- This plan is `done` only when P1+P2 PASS review (after the e2e run), the push is Adviser-approved and executed, and BOTH workflows are green.
