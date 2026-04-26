-- Migration: scheduled cleanup of abandoned signup auth.users rows
--
-- Phase Auth-Triage Iter 1 (AUTH-03):
-- Users who start signup, authenticate with Google + phone OTP (or email +
-- phone OTP), and then abandon the form leave a permanent row in
-- `auth.users` with no matching row in `owners`/`players`. Supabase's
-- built-in unconfirmed-user TTL does NOT touch these rows because the user
-- did confirm (phone or email), they just never finished the app's signup
-- form.
--
-- This migration:
--   1. Defines `public.purge_unverified_auth_users()` — a SECURITY DEFINER
--      function that deletes auth.users rows older than 24h with NO row in
--      `owners`, `players`, or `pending_auth_signups`.
--   2. Schedules it to run hourly via pg_cron.
--   3. Manually invokes it once at the end so existing orphans are cleaned
--      up immediately on deploy.
--
-- The 24-hour threshold matches AuthFlowRules.deferredSignupExpiry on the
-- client. The client-side `_handleExpiredPendingSignupSession` ALSO calls
-- `delete_my_account()` proactively, so this server-side job is the
-- safety net for users whose abandonment never reaches the client cleanup
-- (app force-killed by OS, network failure, etc.).
--
-- pg_cron must be enabled in the Supabase project (Database > Extensions).

create extension if not exists pg_cron;

create or replace function public.purge_unverified_auth_users()
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_deleted integer;
begin
  with purged as (
    delete from auth.users u
    where u.created_at < now() - interval '24 hours'
      and not exists (select 1 from public.owners               o  where o.id      = u.id)
      and not exists (select 1 from public.players              p  where p.id      = u.id)
      and not exists (select 1 from public.pending_auth_signups ps where ps.user_id = u.id)
    returning u.id
  )
  select count(*)::int into v_deleted from purged;

  return v_deleted;
end;
$$;

revoke all on function public.purge_unverified_auth_users() from public;
revoke all on function public.purge_unverified_auth_users() from anon, authenticated;

-- Schedule hourly. If a job with the same name already exists (re-running
-- this migration), unschedule it first so the schedule is idempotent.
do $$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid from cron.job where jobname = 'purge_unverified_auth_users';
  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;
end;
$$;

select cron.schedule(
  'purge_unverified_auth_users',
  '0 * * * *',
  $$select public.purge_unverified_auth_users();$$
);

-- One-shot cleanup of existing orphans on deploy.
select public.purge_unverified_auth_users();
