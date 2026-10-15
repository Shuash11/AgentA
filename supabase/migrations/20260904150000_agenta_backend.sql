-- F4/F5 drift remedy: the base schema as recorded in the live project's
-- migration history (supabase_migrations.schema_migrations, project
-- pmeygoyubqiaqvsuyjzm, version 20260904150000 "agenta_backend",
-- applied 2026-09-04). Captured read-only on 2026-10-16 so the migration
-- history is version-controlled and `supabase db push` accepts the
-- repo's 0001/0002 migrations. This is the base schema the app already
-- runs - declared here, not applied anew.
-- Statements below are verbatim from the recorded `statements` column
-- (array elements separated by ";" plus a blank line; no other edits).

-- AgentA backend: mirrors the Firestore layout (users -> chats -> messages).

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text default 'User',
  recovery_code text default '',
  created_at timestamptz not null default now()
);

create table if not exists public.chats (
  id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null default '',
  last_message text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.messages (
  id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  chat_id text not null references public.chats (id) on delete cascade,
  text text not null default '',
  is_user boolean not null default false,
  timestamp timestamptz not null default now()
);

create index if not exists messages_chat_id_timestamp_idx
  on public.messages (chat_id, timestamp);

alter table public.profiles enable row level security;

alter table public.chats enable row level security;

alter table public.messages enable row level security;

drop policy if exists "profiles_owner" on public.profiles;

create policy "profiles_owner" on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "chats_owner" on public.chats;

create policy "chats_owner" on public.chats
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "messages_owner" on public.messages;

create policy "messages_owner" on public.messages
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
