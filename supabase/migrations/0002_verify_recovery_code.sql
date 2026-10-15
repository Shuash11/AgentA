-- H8: server-side recovery-code verification — the target documented at
-- 0001_rls.sql:68-81 (docs/backend-rls.md §H8). SECURITY DEFINER with
-- search_path pinned; compares only the auth.uid() row's stored SHA-256
-- hash and returns boolean — the hash never ships to the client.
-- Additive: the client stub keeps working until a follow-up cycle
-- switches UserRepository.verifyRecoveryCodeViaRpc to _db.rpc(...).
-- Apply with: supabase db push

create or replace function public.verify_recovery_code(p_code_hash text)
returns boolean language plpgsql security definer
set search_path = public as $$
begin
  return exists (select 1 from public.profiles p
    where p.id = auth.uid() and p.recovery_code = p_code_hash);
end $$;
