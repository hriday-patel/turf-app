-- Migration: self-service account deletion (Google Play compliance, Nov 2023+)
--
-- Provides a single RPC `delete_my_account()` callable by any authenticated
-- user that deletes their own auth.users row. Existing FK chains
-- (auth.users -> owners/players/pending_auth_signups -> turfs -> slots/bookings)
-- are all `on delete cascade`, so the user's full data footprint disappears
-- in one transaction.
--
-- SECURITY DEFINER is required because the auth schema is not writable by
-- the `authenticated` role. The function explicitly resolves the calling
-- user via auth.uid() so it can ONLY ever delete the caller's own row.
-- search_path is pinned to prevent search_path-based privilege-escalation
-- via shadowed function names.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();

  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = '42501';
  end if;

  -- Cascades delete owners/players/pending_auth_signups (and by extension
  -- turfs, slots, bookings) thanks to the existing on-delete-cascade FKs.
  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

comment on function public.delete_my_account() is
  'Self-service account deletion. Deletes the caller''s auth.users row and cascades through all owned data. Required by Google Play policy.';
