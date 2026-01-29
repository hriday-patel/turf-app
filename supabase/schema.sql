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
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Players table
create table if not exists players (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null,
  phone text not null,
  role text not null default 'PLAYER',
  profile_image text,
  favorite_turfs text[] not null default array[]::text[],
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz
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
  on slots (turf_id, date, start_time);

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
  user_id uuid,
  customer_name text not null,
  customer_phone text not null,
  booking_source text not null,
  payment_mode text not null,
  payment_status text not null,
  amount numeric not null,
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

create index if not exists bookings_owner_date_idx on bookings (owner_id, booking_date);
create index if not exists slots_turf_date_idx on slots (turf_id, date, start_time);
create index if not exists turfs_owner_idx on turfs (owner_id, created_at desc);

-- =====================================================
-- ROW LEVEL SECURITY
-- =====================================================

alter table owners enable row level security;
alter table players enable row level security;
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
drop policy if exists "turfs_select_owner" on turfs;
drop policy if exists "turfs_insert_owner" on turfs;
drop policy if exists "turfs_update_owner" on turfs;
drop policy if exists "turfs_select_public" on turfs;
drop policy if exists "slots_select_owner" on slots;
drop policy if exists "slots_insert_owner" on slots;
drop policy if exists "slots_update_owner" on slots;
drop policy if exists "bookings_select_owner" on bookings;
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
  user_phone text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into owners (id, name, email, phone, role, is_verified, auth_methods, created_at)
  values (user_id, user_name, lower(user_email), user_phone, 'OWNER', false, array['email'], now());
  return true;
exception
  when unique_violation then
    raise exception 'Email or phone already registered';
  when others then
    raise exception 'Failed to create profile: %', sqlerrm;
end;
$$;

-- Create player profile (called after auth signup)
create or replace function create_player_profile(
  user_id uuid,
  user_name text,
  user_email text,
  user_phone text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into players (id, name, email, phone, role, created_at)
  values (user_id, user_name, lower(user_email), user_phone, 'PLAYER', now());
  return true;
exception
  when unique_violation then
    raise exception 'Email or phone already registered';
  when others then
    raise exception 'Failed to create profile: %', sqlerrm;
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
begin
  select * into slot_record from slots where id = p_slot_id for update;
  if not found then
    raise exception 'Slot not found';
  end if;

  if slot_record.status not in ('AVAILABLE', 'RESERVED') then
    raise exception 'Slot not available';
  end if;

  update slots
    set status = 'BOOKED',
        reserved_until = null,
        reserved_by = null,
        updated_at = now()
    where id = p_slot_id;

  insert into bookings (
    owner_id, turf_id, slot_id, booking_date, start_time, end_time,
    turf_name, user_id, customer_name, customer_phone, booking_source,
    payment_mode, payment_status, amount, transaction_id, booking_status, created_at
  ) values (
    (select owner_id from turfs where id = (p_booking_data->>'turf_id')::uuid),
    (p_booking_data->>'turf_id')::uuid,
    p_slot_id,
    (p_booking_data->>'booking_date')::date,
    p_booking_data->>'start_time',
    p_booking_data->>'end_time',
    p_booking_data->>'turf_name',
    nullif(p_booking_data->>'user_id', '')::uuid,
    p_booking_data->>'customer_name',
    p_booking_data->>'customer_phone',
    p_booking_data->>'booking_source',
    p_booking_data->>'payment_mode',
    p_booking_data->>'payment_status',
    (p_booking_data->>'amount')::numeric,
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
