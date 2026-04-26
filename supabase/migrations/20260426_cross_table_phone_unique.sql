-- Phase 8 Iter 4 AUTH-08 (B1): defense-in-depth cross-table phone uniqueness.
--
-- The `check_phone_availability` RPC already enforces "one verified phone =
-- one account" across owners + players + pending_auth_signups for every
-- app-driven signup path. This migration adds matching DB-level triggers
-- so a direct INSERT/UPDATE (admin SQL, future code path, supabase studio
-- edit, etc.) can never produce a phone collision across the two role
-- tables. Within-table uniqueness is already covered by the existing
-- `phone NOT NULL UNIQUE` column constraints.

create or replace function enforce_owner_phone_not_in_players()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.phone is not null
     and btrim(new.phone) <> ''
     and exists (
       select 1
         from players p
        where p.phone = new.phone
          and p.id <> new.id
     )
  then
    raise exception
      'This phone number is already linked to another account.'
      using errcode = '23505';
  end if;
  return new;
end;
$$;

create or replace function enforce_player_phone_not_in_owners()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.phone is not null
     and btrim(new.phone) <> ''
     and exists (
       select 1
         from owners o
        where o.phone = new.phone
          and o.id <> new.id
     )
  then
    raise exception
      'This phone number is already linked to another account.'
      using errcode = '23505';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_owner_phone_cross_unique on owners;
create trigger trg_owner_phone_cross_unique
  before insert or update of phone on owners
  for each row
  execute function enforce_owner_phone_not_in_players();

drop trigger if exists trg_player_phone_cross_unique on players;
create trigger trg_player_phone_cross_unique
  before insert or update of phone on players
  for each row
  execute function enforce_player_phone_not_in_owners();
