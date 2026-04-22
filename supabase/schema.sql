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

-- Create storage buckets for images.
-- file_size_limit: 5 MB (5 * 1024 * 1024 = 5242880 bytes)
-- allowed_mime_types: only common image formats; blocks executables/PDFs/large videos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'turf-images',
  'turf-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-images',
  'profile-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

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

-- Storage policies for turf-images bucket
-- Read: public (anyone can view turf images on the app)
-- Write/Update/Delete: only the owner of the turf, and only inside their own
--   turf folder (path must be 'turfs/{turfId}/...' where the turf belongs to them).
create policy "turf_images_select" on storage.objects
  for select using (bucket_id = 'turf-images');

create policy "turf_images_insert" on storage.objects
  for insert with check (
    bucket_id = 'turf-images'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = 'turfs'
    and exists (
      select 1 from turfs t
      where t.id::text = (storage.foldername(name))[2]
        and t.owner_id = auth.uid()
    )
  );

create policy "turf_images_update" on storage.objects
  for update using (
    bucket_id = 'turf-images'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = 'turfs'
    and exists (
      select 1 from turfs t
      where t.id::text = (storage.foldername(name))[2]
        and t.owner_id = auth.uid()
    )
  );

create policy "turf_images_delete" on storage.objects
  for delete using (
    bucket_id = 'turf-images'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = 'turfs'
    and exists (
      select 1 from turfs t
      where t.id::text = (storage.foldername(name))[2]
        and t.owner_id = auth.uid()
    )
  );

-- Storage policies for profile-images bucket
-- Read: public. Write/Update/Delete: only inside the user's own folder
--   ('users/{auth.uid()}/...').
create policy "profile_images_select" on storage.objects
  for select using (bucket_id = 'profile-images');

create policy "profile_images_insert" on storage.objects
  for insert with check (
    bucket_id = 'profile-images'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "profile_images_update" on storage.objects
  for update using (
    bucket_id = 'profile-images'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "profile_images_delete" on storage.objects
  for delete using (
    bucket_id = 'profile-images'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
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
-- Note: players.email and players.phone already have UNIQUE constraints from
-- the table definition, which auto-create unique indexes. Extra indexes here
-- would just duplicate them. The lower(email) variant is kept because the
-- unique constraint is case-sensitive and login lookups are case-insensitive.
create unique index if not exists idx_players_email_lower_unique on players (lower(email));
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
  -- Identity check: only the logged-in user may create/update their own owner profile.
  if auth.uid() is null or auth.uid() <> user_id then
    raise exception 'Not authorized to create this profile';
  end if;

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
  -- Identity check: only the logged-in owner may sync their own auth methods.
  if auth.uid() is null or auth.uid() <> p_owner_id then
    raise exception 'Not authorized to sync this owner';
  end if;

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
  -- Identity check: only the logged-in user may create/update their own player profile.
  if auth.uid() is null or auth.uid() <> user_id then
    raise exception 'Not authorized to create this profile';
  end if;

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
-- Returns only an availability flag and a generic source label. The matching
-- user id is intentionally NOT returned to prevent user enumeration / id leaks.
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
    -- Do not leak owner id.
    return query select false, 'owners'::text, null::uuid;
    return;
  end if;

  if exists (
    select 1
    from players p
    where p.phone = normalized_phone
      and (p_exclude_user_id is null or p.id <> p_exclude_user_id)
  ) then
    -- Do not leak player id.
    return query select false, 'players'::text, null::uuid;
    return;
  end if;

  if exists (
    select 1
    from pending_auth_signups pas
    where btrim(pas.phone) <> ''
      and pas.phone = normalized_phone
      and (p_exclude_user_id is null or pas.user_id <> p_exclude_user_id)
  ) then
    -- Do not leak pending user id.
    return query select false, 'pending_auth_signups'::text, null::uuid;
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
  -- Identity check: only the logged-in user may write their own pending signup row.
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Not authorized to upsert this pending signup';
  end if;

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
  -- Identity check: only the logged-in user may read their own pending signup row.
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Not authorized to read this pending signup';
  end if;

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
  -- Identity check: only the logged-in user may finalize their own pending signup.
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Not authorized to finalize this pending signup';
  end if;

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
  v_owner_id uuid;
begin
  -- Auth required: only logged-in users may reserve, and only for themselves.
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_reserved_by is null or p_reserved_by <> auth.uid() then
    raise exception 'Cannot reserve a slot on behalf of another user';
  end if;

  select * into slot_record from slots where id = p_slot_id for update;
  if not found then
    return false;
  end if;

  -- Slot must belong to an approved turf to be reservable by the public.
  select owner_id into v_owner_id
  from turfs
  where id = slot_record.turf_id
    and (is_approved = true or owner_id = auth.uid());
  if v_owner_id is null then
    return false;
  end if;

  -- Slot date must not be in the past.
  if slot_record.date < current_date then
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
declare
  slot_record slots%rowtype;
begin
  -- Auth required.
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into slot_record from slots where id = p_slot_id for update;
  if not found then
    return;
  end if;

  -- Allow release if caller is the reserver, OR the owner of the turf.
  if not (
    slot_record.reserved_by = auth.uid()
    or exists (
      select 1 from turfs t
      where t.id = slot_record.turf_id and t.owner_id = auth.uid()
    )
  ) then
    raise exception 'Not authorized to release this slot';
  end if;

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
declare
  slot_record slots%rowtype;
begin
  -- Auth required.
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into slot_record from slots where id = p_slot_id for update;
  if not found then
    return;
  end if;

  -- Only the turf owner may directly mark a slot as BOOKED via this helper.
  -- (The full create_booking_atomic flow has its own checks for app users.)
  if not exists (
    select 1 from turfs t
    where t.id = slot_record.turf_id and t.owner_id = auth.uid()
  ) then
    raise exception 'Not authorized to book this slot';
  end if;

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
declare
  booking_record bookings%rowtype;
  v_owner_id uuid;
begin
  -- Auth required.
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into booking_record from bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Booking not found';
  end if;

  -- Sanity: the slot id passed in must match the one on the booking.
  if booking_record.slot_id <> p_slot_id then
    raise exception 'Slot id does not match booking';
  end if;

  -- Authorization: caller must be either
  --   (a) the turf owner of this booking, OR
  --   (b) the player who made the booking (booking.user_id)
  select t.owner_id into v_owner_id
  from turfs t where t.id = booking_record.turf_id;

  if not (
    auth.uid() = v_owner_id
    or (booking_record.user_id is not null and booking_record.user_id = auth.uid())
  ) then
    raise exception 'Not authorized to cancel this booking';
  end if;

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

-- ============================================================================
-- EXECUTE PERMISSIONS (Phase 1 audit fixes - BUG-08)
-- Lock down RPCs that previously could be called by anonymous users.
-- check_phone_availability stays callable by `anon` because the signup screen
-- needs to verify a phone before the user is logged in, but it now returns
-- only a boolean + generic source label (no user ids).
-- check_owner_exists is restricted to authenticated users only.
-- ============================================================================
revoke execute on function check_owner_exists(text, text) from anon, public;
grant execute on function check_owner_exists(text, text) to authenticated;

-- check_phone_availability: still allow anon (needed for signup), but explicitly grant.
grant execute on function check_phone_availability(text, uuid) to anon, authenticated;

-- ============================================================================
-- TRIGGER: bookings_immutable_columns_guard (BUG-09)
-- Prevent updates to columns that should never change after a booking is
-- created. Only operational fields (status, payment, cancellation, audit
-- columns) may change after insert.
-- ============================================================================
create or replace function bookings_immutable_columns_guard()
returns trigger
language plpgsql
as $$
begin
  if NEW.amount            is distinct from OLD.amount            then raise exception 'amount is immutable';            end if;
  if NEW.customer_phone    is distinct from OLD.customer_phone    then raise exception 'customer_phone is immutable';    end if;
  if NEW.customer_name     is distinct from OLD.customer_name     then raise exception 'customer_name is immutable';     end if;
  if NEW.user_id           is distinct from OLD.user_id           then raise exception 'user_id is immutable';           end if;
  if NEW.slot_id           is distinct from OLD.slot_id           then raise exception 'slot_id is immutable';           end if;
  if NEW.owner_id          is distinct from OLD.owner_id          then raise exception 'owner_id is immutable';          end if;
  if NEW.turf_id           is distinct from OLD.turf_id           then raise exception 'turf_id is immutable';           end if;
  if NEW.booking_date      is distinct from OLD.booking_date      then raise exception 'booking_date is immutable';      end if;
  if NEW.start_time        is distinct from OLD.start_time        then raise exception 'start_time is immutable';        end if;
  if NEW.end_time          is distinct from OLD.end_time          then raise exception 'end_time is immutable';          end if;
  if NEW.turf_name         is distinct from OLD.turf_name         then raise exception 'turf_name is immutable';         end if;
  if NEW.net_number        is distinct from OLD.net_number        then raise exception 'net_number is immutable';        end if;
  if NEW.booking_source    is distinct from OLD.booking_source    then raise exception 'booking_source is immutable';    end if;
  if NEW.payment_mode      is distinct from OLD.payment_mode      then raise exception 'payment_mode is immutable';      end if;
  if NEW.created_at        is distinct from OLD.created_at        then raise exception 'created_at is immutable';        end if;
  if NEW.created_by        is distinct from OLD.created_by        then raise exception 'created_by is immutable';        end if;
  return NEW;
end;
$$;

drop trigger if exists trg_bookings_immutable_columns_guard on bookings;
create trigger trg_bookings_immutable_columns_guard
before update on bookings
for each row
execute function bookings_immutable_columns_guard();

-- ============================================================================
-- TRIGGER: slots_no_release_with_active_booking (BUG-10)
-- Block any UPDATE that flips a slot back to AVAILABLE while a CONFIRMED
-- booking still exists for that slot. Use cancel_booking() instead.
-- ============================================================================
create or replace function slots_no_release_with_active_booking()
returns trigger
language plpgsql
as $$
begin
  if NEW.status = 'AVAILABLE'
     and OLD.status is distinct from 'AVAILABLE'
     and exists (
       select 1 from bookings b
       where b.slot_id = NEW.id
         and b.booking_status = 'CONFIRMED'
     )
  then
    raise exception 'Cannot release slot: a confirmed booking still exists. Cancel the booking first.';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_slots_no_release_with_active_booking on slots;
create trigger trg_slots_no_release_with_active_booking
before update on slots
for each row
execute function slots_no_release_with_active_booking();

-- ============================================================================
-- TRIGGERS: owners/players role exclusivity (EDGE-01)
-- A given auth user id may exist in only one of (owners, players).
-- ============================================================================
create or replace function owners_no_dup_in_players()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from players where id = NEW.id) then
    raise exception 'This user already has a player account; cannot also create an owner account';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_owners_no_dup_in_players on owners;
create trigger trg_owners_no_dup_in_players
before insert on owners
for each row
execute function owners_no_dup_in_players();

create or replace function players_no_dup_in_owners()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from owners where id = NEW.id) then
    raise exception 'This user already has an owner account; cannot also create a player account';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_players_no_dup_in_owners on players;
create trigger trg_players_no_dup_in_owners
before insert on players
for each row
execute function players_no_dup_in_owners();

