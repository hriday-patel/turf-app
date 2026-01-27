-- Enable extensions
create extension if not exists "pgcrypto";

-- Owners
create table if not exists owners (
  id uuid primary key,
  name text not null,
  email text not null unique,
  phone text not null unique,
  role text not null default 'OWNER',
  is_verified boolean not null default false,
  auth_methods text[] not null default array['email'],
  profile_image text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Players
create table if not exists players (
  id uuid primary key,
  name text not null,
  email text not null,
  phone text not null,
  role text not null default 'PLAYER',
  profile_image text,
  favorite_turfs text[] not null default array[]::text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Turfs
create table if not exists turfs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references owners(id) on delete cascade,
  turf_name text not null,
  turf_type text not null,
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
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Slots
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

-- Bookings
create table if not exists bookings (
  id uuid primary key default gen_random_uuid(),
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
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create unique index if not exists bookings_slot_unique
  on bookings (slot_id)
  where booking_status = 'CONFIRMED';

-- RLS
alter table owners enable row level security;
alter table players enable row level security;
alter table turfs enable row level security;
alter table slots enable row level security;
alter table bookings enable row level security;

-- Owners policies
create policy "owners_select_own" on owners
  for select using (auth.uid() = id);
create policy "owners_update_own" on owners
  for update using (auth.uid() = id);
create policy "owners_insert_own" on owners
  for insert with check (auth.uid() = id);

-- Players policies
create policy "players_select_own" on players
  for select using (auth.uid() = id);
create policy "players_update_own" on players
  for update using (auth.uid() = id);
create policy "players_insert_own" on players
  for insert with check (auth.uid() = id);

-- Turfs policies
create policy "turfs_select_owner" on turfs
  for select using (auth.uid() = owner_id);
create policy "turfs_insert_owner" on turfs
  for insert with check (auth.uid() = owner_id);
create policy "turfs_update_owner" on turfs
  for update using (auth.uid() = owner_id);

-- Slots policies (owners via turf)
create policy "slots_select_owner" on slots
  for select using (exists(select 1 from turfs t where t.id = slots.turf_id and t.owner_id = auth.uid()));
create policy "slots_insert_owner" on slots
  for insert with check (exists(select 1 from turfs t where t.id = slots.turf_id and t.owner_id = auth.uid()));
create policy "slots_update_owner" on slots
  for update using (exists(select 1 from turfs t where t.id = slots.turf_id and t.owner_id = auth.uid()));

-- Bookings policies (owners via turf)
create policy "bookings_select_owner" on bookings
  for select using (exists(select 1 from turfs t where t.id = bookings.turf_id and t.owner_id = auth.uid()));
create policy "bookings_insert_owner" on bookings
  for insert with check (exists(select 1 from turfs t where t.id = bookings.turf_id and t.owner_id = auth.uid()));
create policy "bookings_update_owner" on bookings
  for update using (exists(select 1 from turfs t where t.id = bookings.turf_id and t.owner_id = auth.uid()));

-- RPCs for atomic operations
create or replace function reserve_slot(
  slot_id uuid,
  reserved_by uuid,
  reservation_minutes int
) returns boolean
language plpgsql
security definer
as $$
declare
  slot_record slots%rowtype;
begin
  select * into slot_record from slots where id = slot_id for update;
  if not found then
    return false;
  end if;

  if slot_record.status = 'AVAILABLE' then
    update slots
      set status = 'RESERVED',
          reserved_by = reserved_by,
          reserved_until = now() + (reservation_minutes || ' minutes')::interval,
          updated_at = now()
      where id = slot_id;
    return true;
  end if;

  if slot_record.status = 'RESERVED' and slot_record.reserved_until is not null and slot_record.reserved_until < now() then
    update slots
      set status = 'RESERVED',
          reserved_by = reserved_by,
          reserved_until = now() + (reservation_minutes || ' minutes')::interval,
          updated_at = now()
      where id = slot_id;
    return true;
  end if;

  return false;
end;
$$;

create or replace function release_slot(slot_id uuid) returns void
language plpgsql
security definer
as $$
begin
  update slots
    set status = 'AVAILABLE',
        reserved_until = null,
        reserved_by = null,
        updated_at = now()
    where id = slot_id;
end;
$$;

create or replace function book_slot(slot_id uuid) returns void
language plpgsql
security definer
as $$
begin
  update slots
    set status = 'BOOKED',
        reserved_until = null,
        reserved_by = null,
        updated_at = now()
    where id = slot_id;
end;
$$;

create or replace function create_booking_atomic(
  slot_id uuid,
  booking_data jsonb
) returns uuid
language plpgsql
security definer
as $$
declare
  slot_record slots%rowtype;
  booking_id uuid;
begin
  select * into slot_record from slots where id = slot_id for update;
  if not found then
    raise exception 'Slot not found';
  end if;

  if slot_record.status not in ('AVAILABLE','RESERVED') then
    raise exception 'Slot not available';
  end if;

  if slot_record.status = 'RESERVED' and slot_record.reserved_until is not null and slot_record.reserved_until < now() then
    -- allow booking after reservation expiry
    null;
  end if;

  update slots
    set status = 'BOOKED',
        reserved_until = null,
        reserved_by = null,
        updated_at = now()
    where id = slot_id;

  insert into bookings (
    turf_id,
    slot_id,
    booking_date,
    start_time,
    end_time,
    turf_name,
    user_id,
    customer_name,
    customer_phone,
    booking_source,
    payment_mode,
    payment_status,
    amount,
    transaction_id,
    booking_status,
    created_at
  ) values (
    (booking_data->>'turf_id')::uuid,
    (booking_data->>'slot_id')::uuid,
    (booking_data->>'booking_date')::date,
    booking_data->>'start_time',
    booking_data->>'end_time',
    booking_data->>'turf_name',
    nullif(booking_data->>'user_id','')::uuid,
    booking_data->>'customer_name',
    booking_data->>'customer_phone',
    booking_data->>'booking_source',
    booking_data->>'payment_mode',
    booking_data->>'payment_status',
    (booking_data->>'amount')::numeric,
    booking_data->>'transaction_id',
    booking_data->>'booking_status',
    now()
  ) returning id into booking_id;

  return booking_id;
end;
$$;

create or replace function cancel_booking(
  booking_id uuid,
  slot_id uuid,
  cancelled_by text,
  cancel_reason text
) returns boolean
language plpgsql
security definer
as $$
begin
  update bookings
    set booking_status = 'CANCELLED',
        cancelled_at = now(),
        cancelled_by = cancelled_by,
        cancellation_reason = cancel_reason,
        updated_at = now()
    where id = booking_id;

  update slots
    set status = 'AVAILABLE',
        reserved_until = null,
        reserved_by = null,
        updated_at = now()
    where id = slot_id;

  return true;
end;
$$;
