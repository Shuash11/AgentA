-- H11: Row Level Security — never trust client-supplied userId.
-- All policies bind to auth.uid(). Apply with: supabase db push
-- CI asserts this file exists (see .github/workflows/build-apk.yml).

alter table if exists public.profiles enable row level security;
alter table if exists public.chats enable row level security;
alter table if exists public.messages enable row level security;

-- profiles: owners only (id = auth.uid())
drop policy if exists profiles_owner_select on public.profiles;
create policy profiles_owner_select on public.profiles
  for select using (auth.uid() = id);
drop policy if exists profiles_owner_insert on public.profiles;
create policy profiles_owner_insert on public.profiles
  for insert with check (auth.uid() = id);
drop policy if exists profiles_owner_update on public.profiles;
create policy profiles_owner_update on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists profiles_owner_delete on public.profiles;
create policy profiles_owner_delete on public.profiles
  for delete using (auth.uid() = id);

-- chats: owners only (user_id = auth.uid())
drop policy if exists chats_owner_select on public.chats;
create policy chats_owner_select on public.chats
  for select using (auth.uid() = user_id);
drop policy if exists chats_owner_insert on public.chats;
create policy chats_owner_insert on public.chats
  for insert with check (auth.uid() = user_id);
drop policy if exists chats_owner_update on public.chats;
create policy chats_owner_update on public.chats
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists chats_owner_delete on public.chats;
create policy chats_owner_delete on public.chats
  for delete using (auth.uid() = user_id);

-- messages: via parent chat ownership (chat.user_id = auth.uid()).
-- Assumes messages.chat_id / messages.user_id references chats(id).
-- Adjust the USING clause to the real FK if the schema differs.
drop policy if exists messages_owner_select on public.messages;
create policy messages_owner_select on public.messages
  for select using (
    exists (select 1 from public.chats c
      where c.id = messages.chat_id and c.user_id = auth.uid())
  );
drop policy if exists messages_owner_insert on public.messages;
create policy messages_owner_insert on public.messages
  for insert with check (
    exists (select 1 from public.chats c
      where c.id = messages.chat_id and c.user_id = auth.uid())
  );
drop policy if exists messages_owner_update on public.messages;
create policy messages_owner_update on public.messages
  for update using (
    exists (select 1 from public.chats c
      where c.id = messages.chat_id and c.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.chats c
      where c.id = messages.chat_id and c.user_id = auth.uid())
  );
drop policy if exists messages_owner_delete on public.messages;
create policy messages_owner_delete on public.messages
  for delete using (
    exists (select 1 from public.chats c
      where c.id = messages.chat_id and c.user_id = auth.uid())
  );

-- H8 target: server-side recovery-code verification (deploy alongside RLS).
-- Stores only the SHA-256 hash in profiles.recovery_code; the raw code is
-- shown once at creation and never returned by any select policy above
-- for other users. Implement as SECURITY DEFINER so the hash comparison
-- never ships the stored value to the client:
--
-- create or replace function public.verify_recovery_code(p_code_hash text)
-- returns boolean language plpgsql security definer as $$
-- begin
--   return exists (select 1 from public.profiles p
--     where p.id = auth.uid() and p.recovery_code = p_code_hash);
-- end $$;
-- Until deployed, clients compare hashes for the single authenticated row
-- (see UserRepository.verifyRecoveryCodeViaRpc).
