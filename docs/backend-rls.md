# Backend RLS + secrets model

## RLS (H11)

- Migration: `supabase/migrations/0001_rls.sql` — `auth.uid() = user_id`
  (chats) / `auth.uid() = id` (profiles) on all CRUD policies. Messages are
  gated through parent-chat ownership. Never trust a client-supplied `userId`.
- Apply: `supabase db push` (or run the file in the Supabase SQL editor).
- CI check (`build-apk.yml` → "Assert backend RLS + guards") fails the build
  if the migration is missing or lacks `auth.uid()` policies.
- Direct table access in `SupabaseChatService` / `UserRepository` /
  `SecurityService` is safe only behind these policies.

## Recovery codes (H8)

- Raw code shown once at creation (`RegisterPage` dialog).
- Stored form is `SHA256(NORMALIZED_CODE)` in `profiles.recovery_code` and
  the local `pending_signups.recovery_code` column.
- Verification target is RPC `verify_recovery_code(p_code_hash)` (SECURITY
  DEFINER, compares against `auth.uid()` row). Client stub
  `UserRepository.verifyRecoveryCodeViaRpc` currently hashes + compares for
  the single authenticated row — switch its body to `_db.rpc(...)` once the
  function above is deployed. No full-table fetch, no raw-code selects.

## Local DB encryption note (C5)

- `agenta.db` lives in the app-private directory (scoped storage, H7 — no
  shared-external permissions). Upgrade path to SQLCipher:
  add `sqflite_sqlcipher`, generate a random 256-bit key in
  `flutter_secure_storage` (keystore-backed), open the DB with
  `password: <key>`. Until then, passwords are salted
  `SHA256(salt + pw)` with a per-user `password_salt`, and legacy unsalted
  rows are wiped (force re-enroll) on migrate to v7.

## Env / signing rotation (C1 + C4)

- Secrets reach the app via `--dart-define` (CI) with `.env` as a local-dev
  fallback only. `.env` is git-ignored and never a Flutter asset.
- Rotation: update the GitHub Actions secret value → next `main` push
  rebuilds the APK. No code change needed. Local dev: edit `.env`, restart.
- Release keystore: stored as CI secrets (`ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`)
  restored to `android/key.properties` at build time. Rotate by generating a
  new keystore, updating the four secrets, and registering the new SHA-1 as
  an Android OAuth client (see `docs/google-signin-setup.md`).
