-- Migration: auth + player MVP hardening
-- - Fix owner has_password rollout safely for text[] auth_methods
-- - Align create_owner_profile RPC with app parameters
-- - Add atomic owner OTP sync RPC
-- - Enable player read access for approved turf slots and own bookings
-- - Harden create_booking_atomic authorization checks

ALTER TABLE owners
ADD COLUMN IF NOT EXISTS has_password BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_owners_has_password
ON owners(has_password);

UPDATE owners
SET has_password = true
WHERE has_password = false
  AND 'email' = ANY(auth_methods)
  AND NOT ('google' = ANY(auth_methods));

CREATE OR REPLACE FUNCTION create_owner_profile(
  user_id uuid,
  user_name text,
  user_email text,
  user_phone text,
  user_has_password boolean DEFAULT false,
  user_auth_methods text[] DEFAULT ARRAY['email']::text[]
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_methods text[];
BEGIN
  IF user_phone IS NULL OR btrim(user_phone) = '' THEN
    RAISE EXCEPTION 'Phone number is required';
  END IF;

  SELECT array_agg(DISTINCT m ORDER BY m)
  INTO normalized_methods
  FROM unnest(
    coalesce(user_auth_methods, ARRAY['email']::text[]) || ARRAY['email']::text[]
  ) AS m
  WHERE btrim(m) <> '';

  IF normalized_methods IS NULL OR array_length(normalized_methods, 1) IS NULL THEN
    normalized_methods := ARRAY['email']::text[];
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
    lower(user_email),
    btrim(user_phone),
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

CREATE OR REPLACE FUNCTION sync_owner_after_otp(
  p_owner_id uuid,
  p_verified_phone text,
  p_add_method text DEFAULT 'otp'
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_methods text[];
  merged_methods text[];
  add_method text;
BEGIN
  IF p_owner_id IS NULL THEN
    RAISE EXCEPTION 'Owner id is required';
  END IF;

  IF p_verified_phone IS NULL OR btrim(p_verified_phone) = '' THEN
    RAISE EXCEPTION 'Verified phone is required';
  END IF;

  add_method := coalesce(NULLIF(btrim(p_add_method), ''), 'otp');

  SELECT auth_methods
  INTO current_methods
  FROM owners
  WHERE id = p_owner_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Owner profile not found';
  END IF;

  SELECT array_agg(DISTINCT m ORDER BY m)
  INTO merged_methods
  FROM unnest(coalesce(current_methods, ARRAY[]::text[]) || ARRAY[add_method]::text[]) AS m
  WHERE btrim(m) <> '';

  UPDATE owners
  SET phone = btrim(p_verified_phone),
      auth_methods = coalesce(merged_methods, ARRAY[add_method]::text[]),
      updated_at = now()
  WHERE id = p_owner_id;

  RETURN true;
END;
$$;

DROP POLICY IF EXISTS "slots_select_public_approved_turfs" ON slots;
CREATE POLICY "slots_select_public_approved_turfs"
ON slots
FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM turfs t
    WHERE t.id = slots.turf_id
      AND t.is_approved = true
  )
);

DROP POLICY IF EXISTS "bookings_select_player" ON bookings;
CREATE POLICY "bookings_select_player"
ON bookings
FOR SELECT
USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION create_booking_atomic(
  p_slot_id uuid,
  p_booking_data jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
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
BEGIN
  v_actor := auth.uid();
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  v_turf_id := (p_booking_data->>'turf_id')::uuid;
  IF v_turf_id IS NULL THEN
    RAISE EXCEPTION 'Turf id is required';
  END IF;

  SELECT owner_id INTO v_owner_id
  FROM turfs
  WHERE id = v_turf_id;

  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Turf not found';
  END IF;

  v_source := upper(coalesce(p_booking_data->>'booking_source', 'APP'));
  v_user_id := nullif(p_booking_data->>'user_id', '')::uuid;

  IF v_source = 'APP' THEN
    IF v_user_id IS DISTINCT FROM v_actor THEN
      RAISE EXCEPTION 'Invalid app booking user context';
    END IF;
  ELSE
    IF v_actor <> v_owner_id THEN
      RAISE EXCEPTION 'Only turf owners can create manual bookings';
    END IF;
  END IF;

  SELECT * INTO slot_record
  FROM slots
  WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Slot not found';
  END IF;

  IF slot_record.turf_id <> v_turf_id THEN
    RAISE EXCEPTION 'Slot does not belong to turf';
  END IF;

  IF slot_record.status = 'RESERVED'
     AND slot_record.reserved_until IS NOT NULL
     AND slot_record.reserved_until > now()
     AND slot_record.reserved_by IS NOT NULL
     AND slot_record.reserved_by <> v_actor THEN
    RAISE EXCEPTION 'Slot currently reserved by another user';
  END IF;

  IF slot_record.status NOT IN ('AVAILABLE', 'RESERVED') THEN
    RAISE EXCEPTION 'Slot not available';
  END IF;

  v_advance_amount := coalesce((p_booking_data->>'advance_amount')::numeric, 0);
  v_total_amount := coalesce((p_booking_data->>'amount')::numeric, 0);

  IF v_total_amount > 0 AND v_advance_amount >= v_total_amount THEN
    v_slot_status := 'BOOKED';
  ELSE
    v_slot_status := 'RESERVED';
  END IF;

  UPDATE slots
    SET status = v_slot_status,
        reserved_until = NULL,
        reserved_by = NULL,
        updated_at = now()
    WHERE id = p_slot_id;

  INSERT INTO bookings (
    owner_id, turf_id, slot_id, booking_date, start_time, end_time,
    turf_name, net_number, user_id, customer_name, customer_phone, booking_source,
    payment_mode, payment_status, amount, advance_amount, transaction_id, booking_status, created_at
  ) VALUES (
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
  )
  RETURNING id INTO booking_id;

  RETURN booking_id;
END;
$$;
