-- Migration: unified pending signup auth flow with mandatory phone OTP
-- - Align player metadata with owner auth metadata
-- - Add pending_auth_signups for resumable signup flow
-- - Add global phone uniqueness RPC checks across owners/players/pending
-- - Add atomic finalize_pending_signup RPC

ALTER TABLE players
ADD COLUMN IF NOT EXISTS auth_methods TEXT[] NOT NULL DEFAULT ARRAY['email'];

ALTER TABLE players
ADD COLUMN IF NOT EXISTS has_password BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_players_has_password
ON players(has_password);

CREATE UNIQUE INDEX IF NOT EXISTS idx_players_email_lower_unique
ON players(lower(email));

CREATE UNIQUE INDEX IF NOT EXISTS idx_players_phone_unique
ON players(phone);

UPDATE players
SET has_password = true
WHERE has_password = false
  AND 'email' = ANY(auth_methods)
  AND NOT ('google' = ANY(auth_methods));

CREATE TABLE IF NOT EXISTS pending_auth_signups (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('OWNER', 'PLAYER')),
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  auth_method TEXT NOT NULL CHECK (auth_method IN ('email', 'google')),
  has_password BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pending_auth_signups_email
ON pending_auth_signups(lower(email));

CREATE INDEX IF NOT EXISTS idx_pending_auth_signups_phone
ON pending_auth_signups(phone)
WHERE btrim(phone) <> '';

ALTER TABLE pending_auth_signups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pending_auth_signups_insert_own" ON pending_auth_signups;
DROP POLICY IF EXISTS "pending_auth_signups_select_own" ON pending_auth_signups;
DROP POLICY IF EXISTS "pending_auth_signups_update_own" ON pending_auth_signups;
DROP POLICY IF EXISTS "pending_auth_signups_delete_own" ON pending_auth_signups;

CREATE POLICY "pending_auth_signups_insert_own" ON pending_auth_signups
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "pending_auth_signups_select_own" ON pending_auth_signups
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "pending_auth_signups_update_own" ON pending_auth_signups
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "pending_auth_signups_delete_own" ON pending_auth_signups
  FOR DELETE USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION create_owner_profile(
  user_id UUID,
  user_name TEXT,
  user_email TEXT,
  user_phone TEXT,
  user_has_password BOOLEAN DEFAULT false,
  user_auth_methods TEXT[] DEFAULT ARRAY['email']::TEXT[]
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_methods TEXT[];
  normalized_phone TEXT;
  normalized_email TEXT;
BEGIN
  normalized_phone := btrim(coalesce(user_phone, ''));
  normalized_email := lower(btrim(coalesce(user_email, '')));

  IF normalized_phone = '' THEN
    RAISE EXCEPTION 'Phone number is required';
  END IF;

  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Email is required';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM players p
    WHERE p.id <> user_id
      AND lower(p.email) = normalized_email
  ) THEN
    RAISE EXCEPTION 'Email already linked to another account';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM players p
    WHERE p.id <> user_id
      AND p.phone = normalized_phone
  ) THEN
    RAISE EXCEPTION 'Phone number already linked to another account';
  END IF;

  SELECT array_agg(DISTINCT m ORDER BY m)
  INTO normalized_methods
  FROM unnest(
    coalesce(user_auth_methods, ARRAY['email']::TEXT[]) || ARRAY['email']::TEXT[]
  ) AS m
  WHERE btrim(m) <> '';

  IF normalized_methods IS NULL OR array_length(normalized_methods, 1) IS NULL THEN
    normalized_methods := ARRAY['email']::TEXT[];
  END IF;

  INSERT INTO owners (
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
  VALUES (
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
  ON CONFLICT (id)
  DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    auth_methods = EXCLUDED.auth_methods,
    has_password = EXCLUDED.has_password,
    updated_at = now();

  RETURN true;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Email or phone already registered';
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to create profile: %', SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION create_player_profile(
  user_id UUID,
  user_name TEXT,
  user_email TEXT,
  user_phone TEXT,
  user_has_password BOOLEAN DEFAULT false,
  user_auth_methods TEXT[] DEFAULT ARRAY['email']::TEXT[]
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_methods TEXT[];
  normalized_phone TEXT;
  normalized_email TEXT;
BEGIN
  normalized_phone := btrim(coalesce(user_phone, ''));
  normalized_email := lower(btrim(coalesce(user_email, '')));

  IF normalized_phone = '' THEN
    RAISE EXCEPTION 'Phone number is required';
  END IF;

  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Email is required';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM owners o
    WHERE o.id <> user_id
      AND lower(o.email) = normalized_email
  ) THEN
    RAISE EXCEPTION 'Email already linked to another account';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM owners o
    WHERE o.id <> user_id
      AND o.phone = normalized_phone
  ) THEN
    RAISE EXCEPTION 'Phone number already linked to another account';
  END IF;

  SELECT array_agg(DISTINCT m ORDER BY m)
  INTO normalized_methods
  FROM unnest(
    coalesce(user_auth_methods, ARRAY['email']::TEXT[]) || ARRAY['email']::TEXT[]
  ) AS m
  WHERE btrim(m) <> '';

  IF normalized_methods IS NULL OR array_length(normalized_methods, 1) IS NULL THEN
    normalized_methods := ARRAY['email']::TEXT[];
  END IF;

  INSERT INTO players (
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
  VALUES (
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
  ON CONFLICT (id)
  DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    auth_methods = EXCLUDED.auth_methods,
    has_password = EXCLUDED.has_password,
    updated_at = now();

  RETURN true;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Email or phone already registered';
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to create profile: %', SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION check_phone_availability(
  p_phone TEXT,
  p_exclude_user_id UUID DEFAULT NULL
) RETURNS TABLE (
  is_available BOOLEAN,
  conflict_source TEXT,
  conflict_user_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_phone TEXT;
BEGIN
  normalized_phone := btrim(coalesce(p_phone, ''));

  IF normalized_phone = '' THEN
    RETURN QUERY SELECT false, 'invalid_phone'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM owners o
    WHERE o.phone = normalized_phone
      AND (p_exclude_user_id IS NULL OR o.id <> p_exclude_user_id)
  ) THEN
    RETURN QUERY
    SELECT false, 'owners'::TEXT, o.id
    FROM owners o
    WHERE o.phone = normalized_phone
      AND (p_exclude_user_id IS NULL OR o.id <> p_exclude_user_id)
    LIMIT 1;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM players p
    WHERE p.phone = normalized_phone
      AND (p_exclude_user_id IS NULL OR p.id <> p_exclude_user_id)
  ) THEN
    RETURN QUERY
    SELECT false, 'players'::TEXT, p.id
    FROM players p
    WHERE p.phone = normalized_phone
      AND (p_exclude_user_id IS NULL OR p.id <> p_exclude_user_id)
    LIMIT 1;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pending_auth_signups pas
    WHERE btrim(pas.phone) <> ''
      AND pas.phone = normalized_phone
      AND (p_exclude_user_id IS NULL OR pas.user_id <> p_exclude_user_id)
  ) THEN
    RETURN QUERY
    SELECT false, 'pending_auth_signups'::TEXT, pas.user_id
    FROM pending_auth_signups pas
    WHERE btrim(pas.phone) <> ''
      AND pas.phone = normalized_phone
      AND (p_exclude_user_id IS NULL OR pas.user_id <> p_exclude_user_id)
    LIMIT 1;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, NULL::TEXT, NULL::UUID;
END;
$$;

CREATE OR REPLACE FUNCTION upsert_pending_signup(
  p_user_id UUID,
  p_role TEXT,
  p_name TEXT,
  p_email TEXT,
  p_phone TEXT DEFAULT '',
  p_auth_method TEXT DEFAULT 'email',
  p_has_password BOOLEAN DEFAULT false
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_role TEXT;
  normalized_name TEXT;
  normalized_email TEXT;
  normalized_phone TEXT;
  normalized_method TEXT;
  availability RECORD;
BEGIN
  normalized_role := upper(btrim(coalesce(p_role, '')));
  normalized_name := btrim(coalesce(p_name, ''));
  normalized_email := lower(btrim(coalesce(p_email, '')));
  normalized_phone := btrim(coalesce(p_phone, ''));
  normalized_method := lower(coalesce(nullif(btrim(p_auth_method), ''), 'email'));

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User id is required';
  END IF;

  IF normalized_role NOT IN ('OWNER', 'PLAYER') THEN
    RAISE EXCEPTION 'Role must be OWNER or PLAYER';
  END IF;

  IF normalized_name = '' THEN
    RAISE EXCEPTION 'Name is required';
  END IF;

  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Email is required';
  END IF;

  IF normalized_method NOT IN ('email', 'google') THEN
    RAISE EXCEPTION 'Auth method must be email or google';
  END IF;

  IF normalized_phone <> '' THEN
    SELECT * INTO availability
    FROM check_phone_availability(normalized_phone, p_user_id);

    IF availability.is_available IS NOT TRUE THEN
      RAISE EXCEPTION 'This phone number is already linked to another account.';
    END IF;
  END IF;

  INSERT INTO pending_auth_signups (
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
  VALUES (
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
  ON CONFLICT (user_id)
  DO UPDATE SET
    role = EXCLUDED.role,
    name = EXCLUDED.name,
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    auth_method = EXCLUDED.auth_method,
    has_password = EXCLUDED.has_password,
    updated_at = now();

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION get_pending_signup(
  p_user_id UUID
) RETURNS TABLE (
  user_id UUID,
  role TEXT,
  name TEXT,
  email TEXT,
  phone TEXT,
  auth_method TEXT,
  has_password BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    pas.user_id,
    pas.role,
    pas.name,
    pas.email,
    pas.phone,
    pas.auth_method,
    pas.has_password,
    pas.created_at,
    pas.updated_at
  FROM pending_auth_signups pas
  WHERE pas.user_id = p_user_id
  LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION finalize_pending_signup(
  p_user_id UUID,
  p_verified_phone TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pending_record pending_auth_signups%ROWTYPE;
  availability RECORD;
  resolved_phone TEXT;
  resolved_methods TEXT[];
BEGIN
  SELECT * INTO pending_record
  FROM pending_auth_signups
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pending signup not found';
  END IF;

  resolved_phone := btrim(
    coalesce(
      nullif(p_verified_phone, ''),
      nullif(pending_record.phone, '')
    )
  );

  IF resolved_phone = '' THEN
    RAISE EXCEPTION 'Verified phone is required';
  END IF;

  SELECT * INTO availability
  FROM check_phone_availability(resolved_phone, p_user_id);

  IF availability.is_available IS NOT TRUE THEN
    RAISE EXCEPTION 'This phone number is already linked to another account.';
  END IF;

  SELECT array_agg(DISTINCT m ORDER BY m)
  INTO resolved_methods
  FROM unnest(ARRAY[pending_record.auth_method, 'otp']::TEXT[]) AS m
  WHERE btrim(m) <> '';

  IF pending_record.role = 'OWNER' THEN
    PERFORM create_owner_profile(
      pending_record.user_id,
      pending_record.name,
      pending_record.email,
      resolved_phone,
      pending_record.has_password,
      resolved_methods
    );
  ELSIF pending_record.role = 'PLAYER' THEN
    PERFORM create_player_profile(
      pending_record.user_id,
      pending_record.name,
      pending_record.email,
      resolved_phone,
      pending_record.has_password,
      resolved_methods
    );
  ELSE
    RAISE EXCEPTION 'Unsupported pending signup role';
  END IF;

  DELETE FROM pending_auth_signups
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'role', lower(pending_record.role),
    'phone', resolved_phone
  );
END;
$$;
