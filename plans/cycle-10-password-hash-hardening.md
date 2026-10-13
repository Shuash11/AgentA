# Cycle 10 — Password-Hash Hardening (F6) — Verify-Then-Upgrade Migration

**status:** active
**created:** 2026-10-13
**created by:** Adviser (self-improvement cycle 10 audit)
**repo:** C:\projects\aiproject (AgentA) — branch main @ 1e65dc6
**predecessors:** plans/done/cycle-1..9 (all closed, CI green; latest runs 38340769615 / 38341929662)

## Cycle 10 ground truth (fresh evidence, 2026-10-13)

| Check | Result |
|---|---|
| `flutter analyze` (strict lints) | **"No issues found!" exit 0** — 9th consecutive clean cycle |
| `flutter test` | **208/208 "All tests passed!" exit 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** |
| `git status` (app scope) | clean — only plan artifacts (post-lattice tree) |
| **F6 surface (45 matches mapped)** | Producer: `register.dart:157-166` (offline signup), `login.dart:230-239` + `:473-482` (offline account creation / password-change). **Verifier (critical path):** `login.dart:352-355` (offline login verify) + `:414-417` (second verify site). Storage: sqflite `pending_signups` (`password_hash` + `password_salt` TEXT columns — **NOT secure storage**; fss 10.3.4 holds only biometric/session state). Migration machinery precedent: `database_helper.dart:190-209` (PRAGMA table_info → ALTER ADD COLUMN → legacy rows wiped to `{'password':'', 'password_salt':''}` = force re-enroll — the documented v7 C5 precedent). Also: `session_manager.dart:27-30` stashes a hash via `PasswordHasher.hashWithSalt(password, salt-or-empty)`. |
| Current scheme | salted SHA-256, no work factor — documented "minimum bar" (docs/backend-rls.md §C5), argon2 upgrade path noted |
| CI | runs 38340769615 / 38341929662 green; zero deprecations |

## Findings backlog (re-ranked, uncapped)

| ID | Title | Category | Evidence | Responsible | Check |
|---|---|---|---|---|---|
| **F6** | **Local passwords hashed with salted SHA-256 — no work factor.** GPU brute-forceable if the app-private DB leaks. Documented "minimum bar" with an argon2/PBKDF2 upgrade path (C5). The app has in-house migration machinery (v7 legacy wipe precedent) and a natural verify-then-upgrade seam at the login verify sites. **SELECTED as the cycle-10 task** — deliberately sequenced after the lattice (cycle 9) so the new hash storage lands on the maintained stack. | security | password_hasher.dart; the 45-match surface above; docs/backend-rls.md §C5 | middle-end | **EXPENSIVE** |
| **F11 part 3** | **Remaining blocked majors** (flutter_bloc 9.1.1, connectivity_plus 7.3.2, flutter_dotenv 6.0.1, cupertino_icons 2.0.0, flutter_lints 6.0.0, flutter_launcher_icons 0.14.4) — independent constraint-edit cycles, each lower-risk than the fss lattice. Next-up after F6 (bloc 9 + lints 6 are the natural pair). | maintainability | pub outdated | middle-end | EXPENSIVE |
| **F11 part 4** | **^11 `checkUpgradeStatus()` follow-up** — design recorded (cycle 9 P1); **GATED on the user cutting the next release tag** (staged-rollout safety: ^10 must be in users' hands before ^11). Same user-action family as the cloud-blocked items. | maintainability | cycle-9 plan; pubspec ^10.3.4 | middle-end | EXPENSIVE (gated) |
| **F18** | **Gradle 8.14 / AGP 8.11.1 below Flutter warn thresholds** (9.1.0 / 9.0.1) — deliberate deferral; AGP 9 + Built-in-Kotlin migration phase. | CI / toolchain | DependencyVersionChecker.kt warn values | backend | EXPENSIVE |
| **F13** | **Connectivity probe builds a fresh HttpClient per call**; `_lastStatus` defaults offline until first probe. LOW. | performance | connectivity_service.dart:44 | middle-end | EXPENSIVE |
| **F15 residue** | Duplicate-semver guard live (cycle 8); force-pushed never-released tags remain a process rule. | CI | build-apk.yml guard | — | accepted |
| **F16 / F19** | promote-landing staleness fallback / zombie queued run — accepted, no action. | CI | — | — | accepted |
| F4 / F5 / F12 | Supabase schema unversioned / H8 recovery RPC undeployed / offline-signup Edge Function stub. **CLOUD-BLOCKED — standing user escalation (10 cycles).** | contract / security / logic | see cycle-1 plan | backend / security | EXPENSIVE |

Ranking rationale: the cheap backlog is exhausted and the lattice is landed; F6 is the last documented security debt, its migration pattern is industry-standard (verify-then-upgrade with self-describing hashes), the blast radius is the local auth flow with an existing force-re-enroll fallback precedent, and F6 was deliberately sequenced here. Honest risk: a broken verify path locks users out — hence the evidence-first phase with a binding STOP rule.

---

## Selected task (single): F6 — password-hash hardening, lockout-safe

**Objective:** offline-account passwords are hashed with a work-factor scheme (argon2id or high-iteration PBKDF2 — P1 decides with citations); **every existing stored hash keeps verifying** (no lockout by design); successful legacy verifications transparently upgrade to the new scheme; failure modes degrade to the existing force-re-enroll precedent, never a crash.

**Version bump decision: none** — security hardening is not a release; the next user-facing tag still carries 1.2.4 per docs/versioning.md. Final; the push agent must not re-decide.

**ORCHESTRATION RULE (binding, per user directive):** ALL phases implemented first, completely; NO mid-plan gates. Then e2e-tester and Reviewer run **ONCE each over the whole plan** — **P2 is EXPENSIVE (credential-verification behavior), so the e2e run IS REQUIRED before the single review pass.** Definitive acceptance = post-push CI watch.

**STOP RULE (binding, mirrors cycles 7/9):** if P1 cannot establish a **lockout-safe** migration from official documentation and the repo's own evidence — i.e., no sound scheme choice, or the verify-then-upgrade seam cannot cover all 45-match sites without behavioral risk — P1 ends in STOP: no code change in P2, evidence and gaps recorded, the Adviser re-scopes the cycle (deferral with evidence, or substitution). A hardening that could lock users out on guesswork NEVER ships.

**RISK ACKNOWLEDGMENT (honest, plan-level):** the 208-test suite covers the hasher and login flows at unit level; **real device login with pre-existing stored hashes is not gate-coverable** — non-gating advisory: after green, the user smoke-tests offline login on a device holding a pre-upgrade account (verify succeeds; hash transparently upgrades; second login uses the new scheme). The verify-then-upgrade design (old scheme stays verifiable forever) is the primary mitigation.

---

## Phase 1 — Migration evidence + scheme design (read-only)

- **Phase id:** P1
- **Objective:** a documentation-backed answer to "which work-factor scheme, and how does every existing hash transition without lockout" — or an honest STOP.
- **Responsible subagent:** middle-end
- **Files to change:** NONE (read-only evidence pass)
- **Implementation steps:**
  1. Finalize the inventory: every PasswordHasher call site (the 45-match map above), every `pending_signups` column consumer, the SessionManager stash-hash path (:27-30), and the biometric uid (NOT password-derived — confirm out of scope).
  2. Scheme research with citations: (a) **argon2id** via a maintained Flutter plugin (e.g. dargon2_flutter / argon2_ffi — native dep, platform coverage, latent API), vs (b) **PBKDF2-HMAC-SHA256** with high iterations via `pointycastle` (pure Dart, no native dep, iteration budget guidance from OWASP). Compare on: dependency weight, platform coverage, login-latency budget (offline login frequency is low), maintenance status, and the C5 note's own suggestion.
  3. Hash-format design: self-describing versioned strings (PHC-style `$argon2id$…` / `$pbkdf2$rounds$salt$hash`) vs a new `password_algo` column (the database_helper migration precedent supports either). Decide with rationale; old rows (bare 64-hex SHA-256) remain identifiable via the existing `looksLikeLegacyHash` pattern.
  4. Verify-then-upgrade flow design for BOTH verify sites (login.dart:352-355, :414-417): verify with the row's recorded scheme (legacy → old verify; new → new verify); **on successful legacy verify → re-hash with the new scheme and update the row atomically** (same DB write pattern as the existing `update` calls); on failure → exactly today's behavior. Upgrade failure must never block the login itself (best-effort, logged per docs/error-hygiene.md).
  5. SessionManager stash path: same verify-then-upgrade treatment or leave-as-legacy (stash hashes are transient re-login helpers — P1 decides with rationale; both are lockout-safe).
  6. pending_signups sync-path check: the row's hash is synced to Supabase? (Per docs the remote stores the hash too — confirm whether the remote column ever receives the local hash; if yes, upgrading local-only creates a mixed-fleet concern → design the upgrade to happen before sync or keep remote compatibility. Cite the sync code.)
  7. **STOP decision:** if the scheme choice is unsound, or any site cannot be covered lockout-safely → STOP; record everything.
- **Acceptance criteria:** scheme chosen with citations; format decided; per-site flow mapped (all 45-match sites classified); lockout-safety argument written; or STOP with the specific gap.
- **Verification:** **CHEAP** — read-only; no e2e impact.
- **Dependencies / sequencing:** first; P2 executes only a clean design.
- **Expected result:** P2 fully determined, or an honest deferral.

## Phase 2 — Implement the hardened scheme + verify-then-upgrade

- **Phase id:** P2
- **Objective:** the app hashes new passwords with the work-factor scheme, verifies ALL legacy hashes transparently, and upgrades on successful legacy verification — with zero lockout paths.
- **Responsible subagent:** middle-end
- **Files to change:** `lib/services/auth/password_hasher.dart` (versioned scheme), `lib/presentation/auth/login.dart` (2 verify sites), `lib/presentation/auth/register.dart`, `lib/services/auth/session_manager.dart` (per P1), `lib/data/local/database_helper.dart` (only if a column migration is the chosen format), `lib/data/local/local_user_dao.dart` (upgrade write helper), possibly `pubspec.yaml`/`pubspec.lock` (if a plugin/pointycastle is added — IN SCOPE per P1), possibly test/ mocks
- **Implementation steps:**
  1. Implement per the P1 design: versioned hash format; new-scheme hash + verify; legacy verify retained (SHA-256 path stays functional forever); `upgradeHash` helper (re-hash + atomic row update).
  2. Wire verify-then-upgrade at both login.dart verify sites exactly per the map; best-effort upgrade (failure never blocks login).
  3. register/login-create/password-change sites: new hashes use the new scheme from day one.
  4. SessionManager stash per the P1 decision.
  5. Tests: legacy-hash verify + transparent upgrade (golden legacy vector), new-scheme verify, wrong-password unchanged, upgrade-failure-doesn't-block-login. Report any test-count change explicitly.
  6. Local validation: `flutter analyze` exit 0, `dart format --output=none --set-exit-if-changed lib test` exit 0, `flutter test` all pass.
  7. **STOP-and-revert on any non-mechanical gap** (fallback rule).
- **Acceptance criteria:** zero legacy-hash lockout paths (old verify works forever); upgrade-on-success implemented at both sites; new hashes versioned; gates green; diffs match the P1 map site-by-site.
- **Verification:** **EXPENSIVE** — credential-verification behavior changes. The once-per-plan **e2e-tester run IS REQUIRED before the Reviewer gate**: analyze ×2 exit 0, 208/208 (or updated count), format 0, legacy-vector upgrade test evidence.
- **Dependencies / sequencing:** after P1's clean design (STOP forbids P2).
- **Expected result:** the C5 "minimum bar" note becomes obsolete — upgraded to a work-factor scheme with a provably lockout-safe transition.

## Push guidance (after Adviser confirmation — do not push before it)

- Commit 1: `feat(security): work-factor password hashing with verify-then-upgrade (F6/C5)` — or `refactor(security):` if P1's design is purely additive-with-compat; exact type per the final diff character (decide at push confirmation).
- Commit 2 (conditional, cycle-6 rule): `chore: regenerate plugin registrants to match updated dependencies` — ONLY if a new native plugin changes registrants; otherwise SKIP.
- Commit 3: `docs(plans): close cycle 9 and open cycle 10 plan` — stage `plans/` explicitly (deletion of old cycle-9 path, `plans/done/cycle-9-...md`, new cycle-10 file). Never root-wide `git add -A`/`git add .`.
- Exclusions: all `.opencode/` churn (including the tracked `D .opencode/tasks.json`); `analysis_options.yaml` is committed state (any local diff = stop and report); `docs/backend-rls.md` §C5 note update belongs in commit 1 if the scheme lands (doc must match reality).
- Version bump: none.

## Post-push CI watch (definitive acceptance)

- **Build APK** on main must conclude **green** — the runner compiles the new scheme (and any native plugin) with guards + format gate + strict-lint analyze + tests + APK build. **Failure class to name if red:** native-plugin/toolchain resolution errors (if argon2 chosen) or Dart compile errors — capture `gh run view <id> --log-failed`; plan stays `active`; fix phase likely scoped revert to salted-SHA-256 (the old scheme remains verifiable by design, so a revert is always lockout-safe).
- **Promote to Landing** green as usual — the promoted APK is the offline-login smoke-test artifact (user advisory: log in once with a pre-upgrade offline account).
- On green: Adviser marks the plan `done`, moves to `plans/done/`, opens the cycle-11 audit (pre-ranked: F11 part 3 — bloc 9 + lints 6 pair).

## Reviewer web searches for the whole plan (single place, per orchestration rule)

1. `OWASP password storage cheat sheet argon2id PBKDF2 parameters` (cheatsheetseries.owasp.org — the authoritative work-factor/parameter guidance P1's scheme choice must satisfy).
2. `dart argon2 flutter plugin maintained` OR `pointycastle PBKDF2 dart` (pub.dev — maintenance status, platform coverage, API for the chosen scheme).
3. `PBKDF2 iterations recommendation 2026 OWASP` (the concrete round count for the pure-Dart option).
4. `PHC string format password hash self-describing` (github.com/P-H-C/phc-string-format — the versioned-hash format precedent, if chosen).

## Reviewer verification commands (single pass, after P1+P2)

1. Scheme audit: `git diff lib/services/auth/password_hasher.dart` — versioned format + new-scheme hash/verify + legacy verify retained (the 64-hex path still functional).
2. Site audit: both login.dart verify sites show verify-then-upgrade with best-effort semantics (upgrade failure cannot block login — assert from the diff); register/login-create use the new scheme.
3. Lockout-safety audit: for a legacy stored hash, trace the code path (old verify → success → upgrade write) — no path returns lockout for a correct password; wrong-password behavior byte-equal to today.
4. Scope: pubspec.yaml = only the P1-designed dependency (if any); no other constraints; database_helper changes = only the designed migration (if any).
5. Baseline gates: `flutter analyze` exit 0 (strict lints), `flutter test` all-pass (quote count vs 208), `dart format --output=none --set-exit-if-changed lib test` exit 0.
6. If P1 STOPped: verify clean revert (empty git diff) + recorded gaps.

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-13 | Cycle-10 audit recorded; plan created `active` (task F6). Surface mapped (45 matches; 2 verify sites; sqflite storage; v7 wipe precedent). STOP rule + risk acknowledgment recorded. F6 deliberately sequenced post-lattice. |
| 2026-10-13 | **P1+P2 IMPLEMENTED, REQUIRED E2E PASS, SINGLE-PASS REVIEW PASS (security scrutiny satisfied), PUSH APPROVED by Adviser.** Adviser independently verified: scope = exactly 10 files (8 modified + 2 new test files); pubspec = pointycastle ^4.0.0 type-flip only (pure Dart — no native plugin, no registrant churn); password_hasher = PHC `$argon2id$v=19$m=19456,t=2,p=1$…` + legacy 64-hex verify retained forever + no-legacy-fallback for prefixed hashes (downgrade structurally closed); both login verify sites implement the exact verify-then-upgrade contract (matched → needsUpgrade → best-effort `tryUpgradePasswordHash` with `expectedHash` race-guard, never blocks login); gates re-run — analyze exit 0, format 0 changed, **222/222** (208 baseline + 14 new). Reviewer's six security questions all satisfied (constant-time tag compare; parameter bounds pre-invocation; best-effort proven live on closed DB; ~370 ms login within OWASP budget). Non-blocking observation recorded as backlog note: `hashPassword(password)` evaluated outside `tryUpgrade`'s try (login.dart:365,459) — theoretical only, disproven by golden vector + full run. Commits: `feat(security): work-factor password hashing with verify-then-upgrade (F6/C5)` (10 files; docs §C5 rides commit 1) → registrant chore SKIPS (pure Dart, no diffs) → `docs(plans): close cycle 9 and open cycle 10 plan`. Version bump: none; next tag carries 1.2.4 and unlocks the ^11 fss follow-up. |
| pending | agent-push: push main (2 commits — registrant chore skips), watch BOTH workflows → **Build APK green on the hardened tree** (pure Dart: expected red class would be Dart compile/test failures, no native class), Promote to Landing green — **the promoted APK is the device smoke-test artifact** (user logs in once on a device with a pre-upgrade offline account to see verify-then-upgrade work; non-gating advisory). On green: Adviser marks plan `done`, moves to `plans/done/`, opens cycle-11 audit (pre-ranked: F11 part 3 — bloc 9 + lints 6). On red: capture `gh run view --log-failed`, plan stays `active`, fix phase = scoped revert to salted-SHA-256 (lockout-safe by design — the old scheme stays verifiable forever). |

- Cycle-11 pre-ranked: **F11 part 3** (bloc 9 + lints 6 pair — independent, lower-risk constraint cycles). The **^11 fss follow-up** remains gated on the user's next release tag; **F4/F5/F12 remain CLOUD-BLOCKED** (10 cycles) — standing user escalation.
- This plan is `done` only when P1+P2 PASS review (after the e2e run; or the STOP-deferral is recorded and the plan closes via Adviser re-scope), the push is Adviser-approved and executed, and BOTH workflows are green.
