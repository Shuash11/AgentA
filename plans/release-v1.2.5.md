# Release v1.2.5 — the second release cut of the loop

**status:** active
**created:** 2026-10-15
**created by:** Adviser (the user's directive: "if everything is fixed and clean trigger the version bump and report to me with the evidence that is done")
**repo:** C:\projects\aiproject (AgentA) — branch main @ f9c52c4
**predecessors:** plans/done/cycle-1..24 (all closed, CI green); v1.2.4 LIVE (tag bc1479c, release verified)

## THE RELEASE CONDITION RULING: MET (fresh evidence, 2026-10-15)

| Check | Result |
|---|---|
| `flutter analyze` (flutter_lints 6) | **"No issues found!" exit 0** — fresh run |
| `flutter test` | **241/241 "All tests passed!" exit 0** — fresh run |
| `dart format --output=none --set-exit-if-changed lib test` | **exit 0, "0 changed"** — fresh run |
| `git status` (app scope) | **only plans bookkeeping** (the approved cycle-24 bookkeeping + the cycle-25 plan file) — zero app-code changes pending |
| `flutter pub outdated` | **only the held edge_ai 2.x line** — fss left the queue (11.2.0 current); the voluntary queue is empty |
| **CI state (`gh run list`)** | the last 6 runs **ALL success** — the most recent: Build APK (cycle-22 fss push) + Promote, 2026-10-15T09:43/09:58; every Build+Promote pair since v1.2.4 green |
| **Duplicate-semver precondition** | **no v1.2.5 tag exists** (`git tag -l` verified); latest tag v1.2.3-era chain → v1.2.4; no v1.2.5 release |
| **Shipped-since-v1.2.4 (all green on main)** | cycle 22: fss 11.2.0 + the `checkUpgradeStatus()` loss-detection hook (run 38675897935, 225/225); cycle 23: the F29 AI output-hygiene guard fixing the user-reported chat template leak (run 38715001577, 241/241) |
| **Bug A factor** | the app-side is verified CORRECT (the provider config EXACT-MATCHES; no app fix needed); the GCP SHA-1 registration does NOT gate the release (GCP-side, user action) |

## THE RELEASE SEQUENCE (binding, per docs/versioning.md §2)

**Version: `1.2.4+1` → `1.2.5+1`** — patch bump; the build number restarts per the doc's §2 rule ("build number can restart per release"; +b is metadata, never compared).

- **Commit A:** `docs(plans): close cycle 23 and open cycle 24 plan` — stage `plans/` exactly as uncommitted: the tracked deletion of `plans/cycle-23-ai-output-hygiene.md`, the new `plans/done/cycle-23-...md`, the cycle-24 plan file **with its recorded findings/rulings**, and the untracked `plans/cycle-25-f5-rpc-deploy.md`. Never root-wide `git add -A`/`git add .`
- **Commit B:** `chore(release): bump version to 1.2.5+1` — `pubspec.yaml:4` + `docs/versioning.md` (tags list adds v1.2.5; current version 1.2.5+1).
- **Push main** → CI watch: Build APK green (241/241) + Promote green.
- **`git tag -a v1.2.5 -m "Release 1.2.5"`** → **`git push origin v1.2.5`** → CI watch on the tag build.
- **Tag-build preconditions (verified):** no v1.2.5 tag; the tag-guard passes (semver-part-only: v1.2.5 vs 1.2.5+1); the duplicate-semver guard passes (no prior v1.2.5 release); 241/241 on the runner; the APK builds; **the GitHub release is created**; the artifact uploads; **Promote to Landing promotes the tag APK**.

**Exclusions (binding):** all `.opencode/` churn including the tracked `D .opencode/tasks.json` deletion; `analysis_options.yaml` is committed state (no local diff — if one appears, stop and report); nothing else rides the commits.

**Version bump decision: `1.2.5+1` carries the release** — the second bump of the loop's history (the release exception to the per-push "none" convention, per docs/versioning.md §2). Final; the push agent must not re-decide.

## THE GATES

- The bump + bookkeeping = **CHEAP** — the Reviewer gate applies (bump + doc-line exactness); **no e2e** — the tag build's 241/241 runner run is the definitive verification (the cycle-21 release precedent).

## THE USER-FACING EVIDENCE REPORT SPEC (the "done" report — assembled at release completion)

1. The condition ruling + the evidence table (analyze/tests/format/git/CI with run ids).
2. The shipped-since-v1.2.4 inventory: **fss 11.2.0 + the `checkUpgradeStatus()` loss-detection hook** (cycle 22) and **the F29 AI output-hygiene guard fixing the user-reported chat template leak** (cycle 23).
3. The release artifacts: tag `v1.2.5`, the GitHub release URL, `AgentA-v1.2.5.apk` + size.
4. The runs watched: main Build + main Promote + tag Build + tag Promote — ids and conclusions.
5. The version numbers: **1.2.4+1 → 1.2.5+1**.
6. The standing user actions: the GCP SHA-1 registration (`11afea0ce4aece4e4f65b00aee30e073746a6d1b` for `com.agenta.AgentA`), the stale-APK reinstall (fresh from the release), the Supabase-access/desktop-direction items.

## Post-release CI watch

- **TWO Build APK runs + TWO Promote runs expected** (main + tag), ALL green; the tag run must show the tag-assert ✓, the duplicate-semver guard ✓, 241/241 on the runner, the APK built, **the GitHub release created**, the artifact uploaded, and Promote promoting the tag APK.
- **Failure class if red:** version-mismatch at the tag-assert (bump/tag disagree — fix before anything else) or standard gates; **the tag is never re-pushed or force-moved**.
- On all green: assemble the evidence report per the spec → the release is SHIPPED; this plan closes (done) and the cycle-23 audit opens (**pre-rank: the ^11 fss follow-up is schedulable — the design is recorded from cycle 9; F5's RPC deploy is pending-next and does not gate the release**).

## Backlog governance

| Date | Event |
|---|---|
| 2026-10-14 | The user directed the release cut; the condition ruled MET on fresh evidence; this release plan created `active`. |
| 2026-10-15 | **RELEASE-PUSH GATE: APPROVED by Adviser.** Adviser independently verified: pubspec.yaml = the version line ONLY (`1.2.4+1` → `1.2.5+1`); docs/versioning.md = the tags/current-version line only (v1.2.5 added to the 8-tag list); **no v1.2.5 tag exists** (duplicate-semver precondition holds); the commit-A bookkeeping state matches the plan (cycle-23 deletion + done/ + cycle-24 findings + cycle-25 file + this release plan file rides untracked — staged with commit A); gates re-run — analyze exit 0, format 0 changed, 241/241. Reviewer's tag-guard semantic re-derivation accepted (semver-part-only comparison → v1.2.5 + 1.2.5+1 passes; build number never compared per docs/versioning.md §1). **FORMAL BUMP STATEMENT (the second release bump of the loop's history): the release carries 1.2.4+1 → 1.2.5+1; the tag v1.2.5 carries it to users; the build number restarts (+1) and is metadata-only per docs/versioning.md §2.** |
| pending | agent-push RELEASE SEQUENCE (verbatim): (1) commit A: `docs(plans): close cycle 23 and open cycle 24 plan` — stage `plans/` exactly as uncommitted (cycle-23 deletion + done/ + the cycle-24 findings/rulings file + the cycle-25 file + **this release plan file, untracked**); (2) commit B: `chore(release): bump version to 1.2.5+1` — pubspec.yaml + docs/versioning.md; (3) `git push origin main` → CI watch: Build APK on main green (241/241) + Promote green; (4) `git tag -a v1.2.5 -m "Release 1.2.5"`; (5) `git push origin v1.2.5` → CI watch: **Build APK on the tag** — tag-assert ✓ (1.2.5 == 1.2.5+1 semver-part), duplicate-semver guard ✓ (no prior v1.2.5 release), 241/241 on the runner, APK built, **the GitHub release created**, artifact uploaded; Promote promotes the tag APK. Failure class if red: version-mismatch at the tag-assert (bump/tag disagree) or standard gates → plan stays `active`, fix before anything else; **the tag is never re-pushed or force-moved**. On all green: assemble the user-facing evidence report per the ratified spec → the release is SHIPPED; Adviser closes this plan, opens the cycle-23-successor audit (**pre-rank: the ^11 fss follow-up — schedulable, the design recorded from cycle 9; F5's RPC deploy pending-next, does not gate**); the user decisions (Supabase-access scope, desktop direction) stay standing. |

- **Post-release queue:** the ^11 fss follow-up (schedulable — the design recorded from cycle 9), F5's RPC deploy (pending-next, does not gate), F26/F27/F28 (routine), F18 (deferred-with-trigger + the Ubuntu 26 watch), B2 parked, F4/F5/F12 cloud-blocked pending Supabase access.
- This plan is `done` only when both commits + the tag are pushed, BOTH workflows are green on both pushes, the GitHub release exists, and the evidence report is delivered to the user.
