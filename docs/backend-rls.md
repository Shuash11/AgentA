# Backend RLS + secrets model

## RLS (H11)

- Migration: `supabase/migrations/0001_rls.sql` — `auth.uid() = user_id`
  (chats) / `auth.uid() = id` (profiles) on all CRUD policies. Messages are
  gated through parent-chat ownership. Never trust a client-supplied `userId`.
- Apply: `supabase db push` (or run the file in the Supabase SQL editor).
- CI check (`build-apk.yml` → "Assert no .env asset + backend RLS
  guards") fails the build if the migration is missing or lacks
  `auth.uid()` policies.
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
  `password: <key>`.
- Password hashing (F6): offline passwords are **Argon2id**
  (`m=19456` KiB, `t=2`, `p=1`, v=19, 32-byte tag, 16-byte salt) via the
  pure-Dart `pointycastle` package, stored as a self-describing PHC string
  in `pending_signups.password`
  (`$argon2id$v=19$m=19456,t=2,p=1$<b64 salt>$<b64 tag>`; `password_salt`
  stays empty for new rows). Rows written before F6 (salted
  `SHA256(salt + pw)` hex + `password_salt`) keep verifying **forever**;
  after a successful legacy login the row is transparently re-hashed with
  Argon2id (verify-then-upgrade, best-effort — an upgrade failure never
  blocks the login; a prefixed hash never falls back to the legacy
  scheme). No schema change: the DB version stays 7, and the v7
  force-re-enroll applies only to pre-salt rows.

## Env / signing rotation (C1 + C4)

- Secrets reach the app via `--dart-define` only — CI passes the GitHub
  Actions secrets to the APK build; local dev passes the same keys on the
  `flutter run` command line (see `.env.example` for the key reference).
  There is no `.env` fallback: the removed fallback could only read Flutter
  assets, and `.env` is never bundled (C1). `.env` remains git-ignored; no
  `.env` asset is declared, so the CI guard still passes.
- Rotation: update the GitHub Actions secret value → next `main` push
  rebuilds the APK. No code change needed. Local dev: pass the updated
  value via `--dart-define`, restart.
- Release keystore: stored as CI secrets (`ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`)
  restored to `android/key.properties` at build time. Rotate by generating a
  new keystore, updating the four secrets, and registering the new SHA-1 as
  an Android OAuth client (see `docs/google-signin-setup.md`).
