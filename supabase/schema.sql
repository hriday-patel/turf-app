-- =====================================================
-- TURF APP DATABASE SCHEMA
-- Complete rewrite with proper RLS and auth handling
-- Run this in Supabase SQL Editor
-- =====================================================

-- Enable extensions
create extension if not exists "pgcrypto";

-- =====================================================
-- STORAGE BUCKETS
-- =====================================================

-- Create storage buckets for images
insert into storage.buckets (id, name, public)
values ('turf-images', 'turf-images', true)
on conflict (id) do update set public = true;

insert into storage.buckets (id, name, public)
values ('profile-images', 'profile-images', true)
on conflict (id) do update set public = true;

-- Drop existing storage policies (if any)
drop policy if exists "turf_images_select" on storage.objects;
drop policy if exists "turf_images_insert" on storage.objects;
drop policy if exists "turf_images_update" on storage.objects;
drop policy if exists "turf_images_delete" on storage.objects;
drop policy if exists "profile_images_select" on storage.objects;
drop policy if exists "profile_images_insert" on storage.objects;
drop policy if exists "profile_images_update" on storage.objects;
drop policy if exists "profile_images_delete" on storage.objects;
drop policy if exists "Allow public read" on storage.objects;
drop policy if exists "Allow authenticated uploads" on storage.objects;
drop policy if exists "Allow authenticated updates" on storage.objects;
drop policy if exists "Allow authenticated deletes" on storage.objects;

-- Storage policies for turf-images bucket (public read, authenticated write)
create policy "turf_images_select" on storage.objects
  for select using (bucket_id = 'turf-images');

create policy "turf_images_insert" on storage.objects
  for insert with check (
    bucket_id = 'turf-images' 
    and auth.role() = 'authenticated'
  );

create policy "turf_images_update" on storage.objects
  for update using (
    bucket_id = 'turf-images' 
    and auth.role() = 'authenticated'
  );

create policy "turf_images_delete" on storage.objects
  for delete using (
    bucket_id = 'turf-images' 
    and auth.role() = 'authenticated'
  );

-- Storage policies for profile-images bucket
create policy "profile_images_select" on storage.objects
  for select using (bucket_id = 'profile-images');

create policy "profile_images_insert" on storage.objects
  for insert with check (
    bucket_id = 'profile-images' 
    and auth.role() = 'authenticated'
  );

create policy "profile_images_update" on storage.objects
  for update using (
    bucket_id = 'profile-images' 
    and auth.role() = 'authenticated'
  );

create policy "profile_images_delete" on storage.objects
  for delete using (
    bucket_id = 'profile-images' 
    and auth.role() = 'authenticated'
  );

-- =====================================================
-- TABLES
-- =====================================================

-- Owners table
create table if not exists owners (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null unique,
  phone text not null unique,
  role text not null default 'OWNER',
  is_verified boolean not null default false,
  auth_methods text[] not null default array['email'],
  profile_image text,
  has_password boolean not null default false,
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Players table
create table if not exists players (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null unique,
  phone text not null unique,
  role text not null default 'PLAYER',
  auth_methods text[] not null default array['email'],
  has_password boolean not null default false,
  profile_image text,
  favorite_turfs text[] not null default array[]::text[],
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Pending auth signups (resumable staged signup flow)
create table if not exists pending_auth_signups (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null,
  name text not null,
  email text not null,
  phone text not null default '',
  auth_method text not null,
  has_password boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (role in ('OWNER', 'PLAYER')),
  check (auth_method in ('email', 'google'))
);

-- Turfs table
create table if not exists turfs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references owners(id) on delete cascade,
  turf_name text not null,
  turf_type text not null,
  number_of_nets int not null default 1,
  city text not null,
  address text not null,
  location jsonb,
  description text,
  open_time text not null,
  close_time text not null,
  slot_duration_minutes int not null,
  days_open text[] not null,
  pricing_rules jsonb not null,
  public_holidays text[] not null default array[]::text[],
  images jsonb not null default '[]'::jsonb,
  is_approved boolean not null default false,
  verification_status text not null default 'PENDING',
  rejection_reason text,
  status text not null default 'OPEN',
  renovation_net_numbers int[] not null default array[]::int[],
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Slots table
create table if not exists slots (
  id uuid primary key default gen_random_uuid(),
  turf_id uuid not null references turfs(id) on delete cascade,
  date date not null,
  start_time text not null,
  end_time text not null,
  net_number int not null default 1,
  status text not null default 'AVAILABLE',
  reserved_until timestamptz,
  reserved_by uuid,
  price numeric not null,
  price_type text not null,
  blocked_by uuid,
  block_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create unique index if not exists slots_unique_time
  on slots (turf_id, date, start_time, net_number);

-- Bookings table
create table if not exists bookings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references owners(id) on delete cascade,
  turf_id uuid not null references turfs(id) on delete cascade,
  slot_id uuid not null references slots(id) on delete restrict,
  booking_date date not null,
  start_time text not null,
  end_time text not null,
  turf_name text not null,
  net_number int not null default 1,
  user_id uuid,
  customer_name text not null,
  customer_phone text not null,
  booking_source text not null,
  payment_mode text not null,
  payment_status text not null,
  amount numeric not null,
  advance_amount numeric not null default 0,
  transaction_id text,
  booking_status text not null default 'CONFIRMED',
  cancelled_at timestamptz,
  cancelled_by text,
  cancellation_reason text,
  created_by text,
  updated_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create unique index if not exists bookings_slot_unique
  on bookings (slot_id)
  where booking_status = 'CONFIRMED';

create index if not exists idx_owners_has_password on owners (has_password);
create index if not exists idx_players_has_password on players (has_password);
create unique index if not exists idx_players_email_lower_unique on players (lower(email));
create unique index if not exists idx_players_phone_unique on players (phone);
create index if not exists idx_pending_auth_signups_email on pending_auth_signups (lower(email));
create index if not exists idx_pending_auth_signups_phone on pending_auth_signups (phone)
  where btrim(phone) <> '';
create index if not exists bookings_owner_date_idx on bookings (owner_id, booking_date);
create index if not exists slots_turf_date_idx on slots (turf_id, date, start_time);
create index if not exists turfs_owner_idx on turfs (owner_id, created_at desc);

-- =====================================================
-- ROW LEVEL SECURITY
-- =====================================================

alter table owners enable row level security;
alter table players enable row level security;
alter table pending_auth_signups enable row level security;
alter table turfs enable row level security;
alter table slots enable row level security;
alter table bookings enable row level security;

-- Drop existing policies
drop policy if exists "owners_select_own" on owners;
drop policy if exists "owners_update_own" on owners;
drop policy if exists "owners_insert_own" on owners;
drop policy if exists "owners_select_all" on owners;
drop policy if exists "players_select_own" on players;
drop policy if exists "players_update_own" on players;
drop policy if exists "players_insert_own" on players;
drop policy if exists "pending_auth_signups_insert_own" on pending_auth_signups;
drop policy if exists "pending_auth_signups_select_own" on pending_auth_signups;
drop policy if exists "pending_auth_signups_update_own" on pending_auth_signups;
drop policy if exists "pending_auth_signups_delete_own" on pending_auth_signups;
drop policy if exists "turfs_select_owner" on turfs;
drop policy if exists "turfs_insert_owner" on turfs;
drop policy if exists "turfs_update_owner" on turfs;
drop policy if exists "turfs_select_public" on turfs;
drop policy if exists "slots_select_owner" on slots;
drop policy if exists "slots_select_public_approved_turfs" on slots;
drop policy if exists "slots_insert_owner" on slots;
drop policy if exists "slots_update_owner" on slots;
drop policy if exists "bookings_select_owner" on bookings;
drop policy if exists "bookings_select_player" on bookings;
drop policy if exists "bookings_insert_owner" on bookings;
drop policy if exists "bookings_update_owner" on bookings;

-- OWNERS POLICIES
create policy "owners_insert_own" on owners
  for insert with check (auth.uid() = id);

create policy "owners_select_own" on owners
  for select using (auth.uid() = id);

create policy "owners_update_own" on owners
  for update using (auth.uid() = id);

-- PLAYERS POLICIES
create policy "players_insert_own" on players
  for insert with check (auth.uid() = id);

create policy "players_select_own" on players
  for select using (auth.uid() = id);

create policy "players_update_own" on players
  for update using (auth.uid() = id);

-- PENDING SIGNUPS POLICIES
create policy "pending_auth_signups_insert_own" on pending_auth_signups
  for insert with check (auth.uid() = user_id);

create policy "pending_auth_signups_select_own" on pending_auth_signups
  for select using (auth.uid() = user_id);

create policy "pending_auth_signups_update_own" on pending_auth_signups
  for update using (auth.uid() = user_id);

create policy "pending_auth_signups_delete_own" on pending_auth_signups
  for delete using (auth.uid() = user_id);

-- TURFS POLICIES
create policy "turfs_select_owner" on turfs
  for select using (auth.uid() = owner_id);

create policy "turfs_insert_owner" on turfs
  for insert with check (auth.uid() = owner_id);

create policy "turfs_update_owner" on turfs
  for update using (auth.uid() = owner_id);

create policy "turfs_select_public" on turfs
  for select using (is_approved = true);

-- SLOTS POLICIES
create policy "slots_select_owner" on slots
  for select using (
    exists(select 1 from turfs t where t.id = slots.turf_id and t.owner_id = auth.uid())
  );

create policy "slots_select_public_approved_turfs" on slots
  for select using (
    exists(select 1 from turfs t where t.id = slots.turf_id and t.is_approved = true)
  );

create policy "slots_insert_owner" on slots
  for insert with check (
    exists(select 1 from turfs t where t.id = slots.turf_id and t.owner_id = auth.uid())
  );

create policy "slots_update_owner" on slots
  for update using (
    exists(select 1 from turfs t where t.id = slots.turf_id and t.owner_id = auth.uid())
  );

-- BOOKINGS POLICIES
create policy "bookings_select_owner" on bookings
  for select using (
    exists(select 1 from turfs t where t.id = bookings.turf_id and t.owner_id = auth.uid())
  );

create policy "bookings_select_player" on bookings
  for select using (user_id = auth.uid());

create policy "bookings_insert_owner" on bookings
  for insert with check (
    exists(select 1 from turfs t where t.id = bookings.turf_id and t.owner_id = auth.uid())
  );

create policy "bookings_update_owner" on bookings
  for update using (
    exists(select 1 from turfs t where t.id = bookings.turf_id and t.owner_id = auth.uid())
  );

-- =====================================================
-- RPC FUNCTIONS (security definer = bypass RLS)
-- =====================================================

-- Create owner profile (called after auth signup)
create or replace function create_owner_profile(
  user_id uuid,
  user_name text,
  user_email text,
  user_phone text,
  user_has_password boolean default false,
  user_auth_methods text[] default array['email']::text[]
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_methods text[];
  normalized_phone text;
  normalized_email text;
begin
  normalized_phone := btrim(coalesce(user_phone, ''));
  normalized_email := lower(btrim(coalesce(user_email, '')));

  if normalized_phone = '' then
    raise exception 'Phone number is required';
  end if;

  if normalized_email = '' then
    raise exception 'Email is required';
  end if;

  if exists (
    select 1
    from players p
    where p.id <> user_id
      and lower(p.email) = normalized_email
  ) then
    raise exception 'Email already linked to another account';
  end if;

  if exists (
    select 1
    from players p
    where p.id <> user_id
      and p.phone = normalized_phone
  ) then
    raise exception 'Phone number already linked to another account';
  end if;

  select array_agg(distinct m order by m)
  into normalized_methods
  from unnest(
    coalesce(user_auth_methods, array['email']::text[]) || array['email']::text[]
  ) as m
  where btrim(m) <> '';

  if normalized_methods is null or array_length(normalized_methods, 1) is null then
    normalized_methods := array['email']::text[];
  end if;

  insert into owners (
    id,
    name,
    email,
    phone,
    role,
    is_verified,
    auth_methods,
    has_password,
    created_at,
    updated_at
  )
  values (
    user_id,
    user_name,
    normalized_email,
    normalized_phone,
    'OWNER',
    false,
    normalized_methods,
    coalesce(user_has_password, false),
    now(),
    now()
  )
  on conflict (id)
  do update set
    name = excluded.name,
    email = excluded.email,
    phone = excluded.phone,
    auth_methods = excluded.auth_methods,
    has_password = excluded.has_password,
    updated_at = now();

  return true;
exception
  when unique_violation then
    raise exception 'Email or phone already registered';
  when others then
    raise exception 'Failed to create profile: %', sqlerrm;
end;
$$;

-- Sync owner auth method + verified phone atomically after OTP verification
create or replace function sync_owner_after_otp(
  p_owner_id uuid,
  p_verified_phone text,
  p_add_method text default 'otp'
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_methods text[];
  merged_methods text[];
  add_method text;
begin
  if p_owner_id is null then
    raise exception 'Owner id is required';
  end if;

  if p_verified_phone is null or btrim(p_verified_phone) = '' then
    raise exception 'Verified phone is required';
  end if;

  add_method := coalesce(nullif(btrim(p_add_method), ''), 'otp');

  select auth_methods
  into current_methods
  from owners
  where id = p_owner_id
  for update;

  if not found then
    raise exception 'Owner profile not found';
  end if;

  select array_agg(distinct m order by m)
  into merged_methods
  from unnest(coalesce(current_methods, array[]::text[]) || array[add_method]::text[]) as m
  where btrim(m) <> '';

  update owners
    set phone = btrim(p_verified_phone),
        auth_methods = coalesce(merged_methods, array[add_method]::text[]),
        updated_at = now()
  where id = p_owner_id;

  return true;
end;
$$;

-- Create player profile (called after auth signup)
create or replace function create_player_profile(
  user_id uuid,
  user_name text,
  user_email text,
  user_phone text,
  user_has_password boolean default false,
  user_auth_methods text[] default array['email']::text[]
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_methods text[];
  normalized_phone text;
  normalized_email text;
begin
  normalized_phone := btrim(coalesce(user_phone, ''));
  normalized_email := lower(btrim(coalesce(user_email, '')));

  if normalized_phone = '' then
    raise exception 'Phone number is required';
  end if;

  if normalized_email = '' then
    raise exception 'Email is required';
  end if;

  if exists (
    select 1
    from owners o
    where o.id <> user_id
      and lower(o.email) = normalized_email
  ) then
    raise exception 'Email already linked to another account';
  end if;

  if exists (
    select 1
    from owners o
    where o.id <> user_id
      and o.phone = normalized_phone
  ) then
    raise exception 'Phone number already linked to another account';
  end if;

  select array_agg(distinct m order by m)
  into normalized_methods
  from unnest(
    coalesce(user_auth_methods, array['email']::text[]) || array['email']::text[]
  ) as m
  where btrim(m) <> '';

  if normalized_methods is null or array_length(normalized_methods, 1) is null then
    normalized_methods := array['email']::text[];
  end if;

  insert into players (
    id,
    name,
    email,
    phone,
    role,
    auth_methods,
    has_password,
    created_at,
    updated_at
  )
  values (
    user_id,
    user_name,
    normalized_email,
    normalized_phone,
    'PLAYER',
    normalized_methods,
    coalesce(user_has_password, false),
    now(),
    now()
  )
  on conflict (id)
  do update set
    name = excluded.name,
    email = excluded.email,
    phone = excluded.phone,
    auth_methods = excluded.auth_methods,
    has_password = excluded.has_password,
    updated_at = now();

  return true;
exception
  when unique_violation then
    raise exception 'Email or phone already registered';
  when others then
    raise exception 'Failed to create profile: %', sqlerrm;
end;
$$;

-- Check phone availability globally across owners, players and pending signups.
create or replace function check_phone_availability(
  p_phone text,
  p_exclude_user_id uuid default null
) returns table (
  is_available boolean,
  conflict_source text,
  conflict_user_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_phone text;
begin
  normalized_phone := btrim(coalesce(p_phone, ''));

  if normalized_phone = '' then
    return query select false, 'invalid_phone'::text, null::uuid;
    return;
  end if;

  if exists (
    select 1
    from owners o
    where o.phone = normalized_phone
      and (p_exclude_user_id is null or o.id <> p_exclude_user_id)
  ) then
    return query
    select false, 'owners'::text, o.id
    from owners o
    where o.phone = normalized_phone
      and (p_exclude_user_id is null or o.id <> p_exclude_user_id)
    limit 1;
    return;
  end if;

  if exists (
    select 1
    from players p
    where p.phone = normalized_phone
      and (p_exclude_user_id is null or p.id <> p_exclude_user_id)
  ) then
    return query
    select false, 'players'::text, p.id
    from players p
    where p.phone = normalized_phone
      and (p_exclude_user_id is null or p.id <> p_exclude_user_id)
    limit 1;
    return;
  end if;

  if exists (
    select 1
    from pending_auth_signups pas
    where btrim(pas.phone) <> ''
      and pas.phone = normalized_phone
      and (p_exclude_user_id is null or pas.user_id <> p_exclude_user_id)
  ) then
    return query
    select false, 'pending_auth_signups'::text, pas.user_id
    from pending_auth_signups pas
    where btrim(pas.phone) <> ''
      and pas.phone = normalized_phone
      and (p_exclude_user_id is null or pas.user_id <> p_exclude_user_id)
    limit 1;
    return;
  end if;

  return query select true, null::text, null::uuid;
end;
$$;

-- Upsert pending signup to support resumable staged auth flow.
create or replace function upsert_pending_signup(
  p_user_id uuid,
  p_role text,
  p_name text,
  p_email text,
  p_phone text default '',
  p_auth_method text default 'email',
  p_has_password boolean default false
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_role text;
  normalized_name text;
  normalized_email text;
  normalized_phone text;
  normalized_method text;
  availability record;
begin
  normalized_role := upper(btrim(coalesce(p_role, '')));
  normalized_name := btrim(coalesce(p_name, ''));
  normalized_email := lower(btrim(coalesce(p_email, '')));
  normalized_phone := btrim(coalesce(p_phone, ''));
  normalized_method := lower(coalesce(nullif(btrim(p_auth_method), ''), 'email'));

  if p_user_id is null then
    raise exception 'User id is required';
  end if;

  if normalized_role not in ('OWNER', 'PLAYER') then
    raise exception 'Role must be OWNER or PLAYER';
  end if;

  if normalized_name = '' then
    raise exception 'Name is required';
  end if;

  if normalized_email = '' then
    raise exception 'Email is required';
  end if;

  if normalized_method not in ('email', 'google') then
    raise exception 'Auth method must be email or google';
  end if;

  if normalized_phone <> '' then
    select * into availability
    from check_phone_availability(normalized_phone, p_user_id);

    if availability.is_available is not true then
      raise exception 'This phone number is already linked to another account.';
    end if;
  end if;

  insert into pending_auth_signups (
    user_id,
    role,
    name,
    email,
    phone,
    auth_method,
    has_password,
    created_at,
    updated_at
  )
  values (
    p_user_id,
    normalized_role,
    normalized_name,
    normalized_email,
    normalized_phone,
    normalized_method,
    coalesce(p_has_password, false),
    now(),
    now()
  )
  on conflict (user_id)
  do update set
    role = excluded.role,
    name = excluded.name,
    email = excluded.email,
    phone = excluded.phone,
    auth_method = excluded.auth_method,
    has_password = excluded.has_password,
    updated_at = now();

  return true;
end;
$$;

-- Get pending signup for startup/session recovery.
create or replace function get_pending_signup(
  p_user_id uuid
) returns table (
  user_id uuid,
  role text,
  name text,
  email text,
  phone text,
  auth_method text,
  has_password boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    pas.user_id,
    pas.role,
    pas.name,
    pas.email,
    pas.phone,
    pas.auth_method,
    pas.has_password,
    pas.created_at,
    pas.updated_at
  from pending_auth_signups pas
  where pas.user_id = p_user_id
  limit 1;
end;
$$;

-- Finalize pending signup atomically after OTP verification.
create or replace function finalize_pending_signup(
  p_user_id uuid,
  p_verified_phone text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  pending_record pending_auth_signups%rowtype;
  availability record;
  resolved_phone text;
  resolved_methods text[];
begin
  select * into pending_record
  from pending_auth_signups
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'Pending signup not found';
  end if;

  resolved_phone := btrim(
    coalesce(
      nullif(p_verified_phone, ''),
      nullif(pending_record.phone, '')
    )
  );

  if resolved_phone = '' then
    raise exception 'Verified phone is required';
  end if;

  select * into availability
  from check_phone_availability(resolved_phone, p_user_id);

  if availability.is_available is not true then
    raise exception 'This phone number is already linked to another account.';
  end if;

  select array_agg(distinct m order by m)
  into resolved_methods
  from unnest(array[pending_record.auth_method, 'otp']::text[]) as m
  where btrim(m) <> '';

  if pending_record.role = 'OWNER' then
    perform create_owner_profile(
      pending_record.user_id,
      pending_record.name,
      pending_record.email,
      resolved_phone,
      pending_record.has_password,
      resolved_methods
    );
  elsif pending_record.role = 'PLAYER' then
    perform create_player_profile(
      pending_record.user_id,
      pending_record.name,
      pending_record.email,
      resolved_phone,
      pending_record.has_password,
      resolved_methods
    );
  else
    raise exception 'Unsupported pending signup role';
  end if;

  delete from pending_auth_signups
  where user_id = p_user_id;

  return jsonb_build_object(
    'role', lower(pending_record.role),
    'phone', resolved_phone
  );
end;
$$;

-- Check if owner exists by email or phone
create or replace function check_owner_exists(
  check_email text default null,
  check_phone text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if check_email is not null then
    if exists(select 1 from owners where email = lower(check_email)) then
      return true;
    end if;
  end if;
  
  if check_phone is not null then
    if exists(select 1 from owners where phone = check_phone) then
      return true;
    end if;
  end if;
  
  return false;
end;
$$;

-- Reserve a slot
create or replace function reserve_slot(
  p_slot_id uuid,
  p_reserved_by uuid,
  p_reservation_minutes int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  slot_record slots%rowtype;
begin
  select * into slot_record from slots where id = p_slot_id for update;
  if not found then
    return false;
  end if;

  if slot_record.status = 'AVAILABLE' then
    update slots
      set status = 'RESERVED',
          reserved_by = p_reserved_by,
          reserved_until = now() + (p_reservation_minutes || ' minutes')::interval,
          updated_at = now()
      where id = p_slot_id;
    return true;
  end if;

  if slot_record.status = 'RESERVED' and slot_record.reserved_until < now() then
    update slots
      set status = 'RESERVED',
          reserved_by = p_reserved_by,
          reserved_until = now() + (p_reservation_minutes || ' minutes')::interval,
          updated_at = now()
      where id = p_slot_id;
    return true;
  end if;

  return false;
end;
$$;

-- Release a slot
create or replace function release_slot(p_slot_id uuid) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update slots
    set status = 'AVAILABLE',
        reserved_until = null,
        reserved_by = null,
        updated_at = now()
    where id = p_slot_id;
end;
$$;

-- Book a slot
create or replace function book_slot(p_slot_id uuid) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update slots
    set status = 'BOOKED',
        reserved_until = null,
        reserved_by = null,
        updated_at = now()
    where id = p_slot_id;
end;
$$;

-- Create booking atomically
create or replace function create_booking_atomic(
  p_slot_id uuid,
  p_booking_data jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  slot_record slots%rowtype;
  booking_id uuid;
  v_slot_status text;
  v_advance_amount numeric;
  v_total_amount numeric;
  v_actor uuid;
  v_source text;
  v_user_id uuid;
  v_turf_id uuid;
  v_owner_id uuid;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  v_turf_id := (p_booking_data->>'turf_id')::uuid;
  if v_turf_id is null then
    raise exception 'Turf id is required';
  end if;

  select owner_id into v_owner_id
  from turfs
  where id = v_turf_id;

  if v_owner_id is null then
    raise exception 'Turf not found';
  end if;

  v_source := upper(coalesce(p_booking_data->>'booking_source', 'APP'));
  v_user_id := nullif(p_booking_data->>'user_id', '')::uuid;

  if v_source = 'APP' then
    if v_user_id is distinct from v_actor then
      raise exception 'Invalid app booking user context';
    end if;
  else
    if v_actor <> v_owner_id then
      raise exception 'Only turf owners can create manual bookings';
    end if;
  end if;

  select * into slot_record from slots where id = p_slot_id for update;
  if not found then
    raise exception 'Slot not found';
  end if;

  if slot_record.turf_id <> v_turf_id then
    raise exception 'Slot does not belong to turf';
  end if;

  if slot_record.status = 'RESERVED'
     and slot_record.reserved_until is not null
     and slot_record.reserved_until > now()
     and slot_record.reserved_by is not null
     and slot_record.reserved_by <> v_actor then
    raise exception 'Slot currently reserved by another user';
  end if;

  if slot_record.status not in ('AVAILABLE', 'RESERVED') then
    raise exception 'Slot not available';
  end if;

  v_advance_amount := coalesce((p_booking_data->>'advance_amount')::numeric, 0);
  v_total_amount := coalesce((p_booking_data->>'amount')::numeric, 0);

  if v_total_amount > 0 and v_advance_amount >= v_total_amount then
    v_slot_status := 'BOOKED';
  else
    v_slot_status := 'RESERVED';
  end if;

  update slots
    set status = v_slot_status,
        reserved_until = null,
        reserved_by = null,
        updated_at = now()
    where id = p_slot_id;

  insert into bookings (
    owner_id, turf_id, slot_id, booking_date, start_time, end_time,
    turf_name, net_number, user_id, customer_name, customer_phone, booking_source,
    payment_mode, payment_status, amount, advance_amount, transaction_id, booking_status, created_at
  ) values (
    v_owner_id,
    v_turf_id,
    p_slot_id,
    (p_booking_data->>'booking_date')::date,
    p_booking_data->>'start_time',
    p_booking_data->>'end_time',
    p_booking_data->>'turf_name',
    coalesce((p_booking_data->>'net_number')::int, 1),
    v_user_id,
    p_booking_data->>'customer_name',
    p_booking_data->>'customer_phone',
    v_source,
    p_booking_data->>'payment_mode',
    p_booking_data->>'payment_status',
    (p_booking_data->>'amount')::numeric,
    coalesce((p_booking_data->>'advance_amount')::numeric, 0),
    p_booking_data->>'transaction_id',
    coalesce(p_booking_data->>'booking_status', 'CONFIRMED'),
    now()
  ) returning id into booking_id;

  return booking_id;
end;
$$;

-- Cancel booking
create or replace function cancel_booking(
  p_booking_id uuid,
  p_slot_id uuid,
  p_cancelled_by text,
  p_cancel_reason text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update bookings
    set booking_status = 'CANCELLED',
        cancelled_at = now(),
        cancelled_by = p_cancelled_by,
        cancellation_reason = p_cancel_reason,
        updated_at = now()
    where id = p_booking_id;

  update slots
    set status = 'AVAILABLE',
        reserved_until = null,
        reserved_by = null,
        updated_at = now()
    where id = p_slot_id;

  return true;
end;
$$;
