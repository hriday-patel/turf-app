-- Enforce login-method policy at the database layer.
-- Manual/password accounts must carry the `email` method. Google-only
-- accounts must not get `email` unless they truly have a password.

create or replace function normalize_profile_auth_methods(
  p_auth_methods text[],
  p_has_password boolean
) returns text[]
language plpgsql
immutable
as $$
declare
  normalized_methods text[];
begin
  select array_agg(distinct method order by method)
  into normalized_methods
  from (
    select lower(btrim(raw_method)) as method
    from unnest(coalesce(p_auth_methods, array[]::text[])) as raw(raw_method)
  ) cleaned
  where method <> ''
    and (method <> 'email' or coalesce(p_has_password, false));

  if coalesce(p_has_password, false) then
    select array_agg(distinct method order by method)
    into normalized_methods
    from unnest(
      coalesce(normalized_methods, array[]::text[]) || array['email']::text[]
    ) as raw(method)
    where btrim(method) <> '';
  end if;

  if normalized_methods is null or array_length(normalized_methods, 1) is null then
    normalized_methods := case
      when coalesce(p_has_password, false) then array['email']::text[]
      else array['otp']::text[]
    end;
  end if;

  return normalized_methods;
end;
$$;

update owners
set auth_methods = normalize_profile_auth_methods(auth_methods, has_password)
where auth_methods is distinct from normalize_profile_auth_methods(auth_methods, has_password);

update players
set auth_methods = normalize_profile_auth_methods(auth_methods, has_password)
where auth_methods is distinct from normalize_profile_auth_methods(auth_methods, has_password);

alter table owners
drop constraint if exists owners_auth_methods_password_policy;

alter table owners
add constraint owners_auth_methods_password_policy
check (
  (has_password and 'email' = any(auth_methods))
  or (not has_password and not ('email' = any(auth_methods)))
);

alter table players
drop constraint if exists players_auth_methods_password_policy;

alter table players
add constraint players_auth_methods_password_policy
check (
  (has_password and 'email' = any(auth_methods))
  or (not has_password and not ('email' = any(auth_methods)))
);

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

  normalized_methods := normalize_profile_auth_methods(
    user_auth_methods,
    coalesce(user_has_password, false)
  );

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

  normalized_methods := normalize_profile_auth_methods(
    user_auth_methods,
    coalesce(user_has_password, false)
  );

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