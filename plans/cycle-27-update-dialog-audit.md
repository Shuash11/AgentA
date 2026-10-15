# Cycle 27 — Update-dialog audit (the feature ALREADY EXISTS — verify, do not rebuild)

**status:** queued — after cycle 26
**created:** 2026-10-16 by Adviser (user request: "add a dialog to the app: whenever the GitHub tag version has changed, show the user a dialog like 'Like you want to update?' with Yes/No" + "a proper practice is a must" + "search about this")
**repo:** C:\projects\aiproject (AgentA) — branch main @ 950f793
**task level:** **Level 2 — Standard** (behavioral work in one repo, no API-shape/auth/schema changes; the e2e run is required at plan end because the phases touch behavior). Contract gate: NOT triggered — the feature consumes GitHub's public REST API (external, documented), not an API of ours.
**environment note:** skills read BY PATH from `.opencode/skills/<name>/SKILL.md` (research gates → `web-research`; Reviewer → `review-project`).

## Ground truth (verified 2026-10-16 — the feature is IMPLEMENTED and wired)
- **Engine:** `lib/services/update/version_check_service.dart` (post-first-frame init per plus_plugins #309; startup + resumed + 30-min periodic + connectivity-restored triggers; 5-min throttle; `kReleaseMode` gate — debug builds skip checks; silent failures; the cache NEVER drives UI), `lib/services/update/github_releases_source.dart` (`GET /repos/Shuash11/AgentA/releases/latest` via `AppConfig.githubLatestReleaseUrl`, 8s timeout, draft/prerelease guard, 403/429 rate-limit backoff via `retry-after`/`x-ratelimit-reset`, APK-asset URL detection), `lib/services/update/version_source.dart`, `lib/core/utils/semver.dart` (strict MAJOR.MINOR.PATCH, `v`-prefix stripping; the build number is recorded but never compared).
- **UI/state:** `lib/cubit/update/update_cubit.dart` (show rules: forced → always, non-dismissible; available → unless the persisted dismissal equals the version), `lib/presentation/shared/update_dialog_host.dart` (MaterialApp builder overlay, duplicate-dialog guard), `lib/presentation/shared/update_available_dialog.dart` ("New version available" / current → new / release notes / **Update** → `launchUrl` external on the APK asset URL with release-page fallback / **Later**), dismissal persistence via `SharedPreferencesAsync` (`update_dismissed_version`).
- **Wired** in `main.dart` (imports :25/:33 + init + host). **Deps present:** `package_info_plus`, `shared_preferences`, `url_launcher` (+ test-only fakes in dev_dependencies).
- **Why the user never saw it:** pubspec `1.2.5+1` vs latest release `v1.2.5` → EQUAL → correctly silent. It fires on the next release: the cycle-26 v1.3.0 will trigger this dialog on v1.2.5 installs — that IS the live demonstration.

## Adviser rulings (final unless overridden)
- **Do NOT rebuild.** The existing Update/Later dialog SATISFIES the Yes/No request (Later = No, persisted per exact version; any NEWER release re-prompts) and exceeds it (a forced tier via a `min-version:` marker in release notes, rate-limit backoff, offline-silent, non-blocking).
- Update action = open the APK download URL (fallback: the release page) in the external browser — proper practice for direct-APK distribution; deliberately NO in-app APK download/install surface.
- Dialog copy is proper English; the user's "Like you want to update?" was an example ("like"). Overridable with a one-line change if they insist.

## Phase 1 — Engine audit + gap fixes (EXPENSIVE — network logic/behavior)
- **Responsible:** middle-end. Audit `version_check_service` + `github_releases_source` + `semver` against the searches below and the user's spec; fix gaps found. Inventory the existing test files under `test/` for the update feature and extend where the audit finds holes (semver edge cases, backoff windows, dismissal buffering, 404/403/429 paths).
- Gates: `flutter analyze` exit 0; full suite green (record the count).
- **Verification:** EXPENSIVE (touches API-call behavior + state).

## Phase 2 — Dialog audit + theme alignment (EXPENSIVE — dialog state/behavior)
- **Responsible:** frontend. Audit the dialog/host against the new white theme (post-cycle-26) + accessibility; fix gaps. Verify: equal-version → silent; newer → shows once; Later persists; forced (injected fake) → non-dismissible.
- Gates: analyze 0; suite green.

## ORCHESTRATION RULE (binding)
ALL phases first, completely; NO mid-plan gates; then **e2e ONCE** (scenarios: fake newer version → dialog shows; Update launches external; Later persists and re-prompts only on a newer version; equal version → silent; offline → silent, no error UI) → **Reviewer ONCE** → Adviser push confirmation → bookkeeping push + CI watch.

## Push guidance
- Version bump: **none** if pure audit; **patch** if fixes land — decided by the Adviser at push confirmation, final.
- Commits: atomic per phase output; explicit staging; never root-wide `git add`; `.opencode/` excluded.

## Reviewer web searches (per the web-research skill, read from `.opencode/skills/web-research/SKILL.md`)
1. Android in-app update-prompt UX best practice (non-blocking, once-per-version dismissal).
2. GitHub REST `/releases/latest` response shape + unauthenticated rate limits (60 req/h/IP) — verify the implementation's handling.
3. Semantic-version comparison practice (strict core, build metadata excluded).

## Governance
| Date | Event |
|---|---|
| 2026-10-16 | Plan created `queued` (runs after cycle 26). The feature pre-exists — the cycle is an audit, not a build. |
