-- Add advance_amount column to bookings table
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS advance_amount numeric NOT NULL DEFAULT 0;

-- Add net_number column to bookings table for multi-net support
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS net_number int NOT NULL DEFAULT 1;

-- Add net_number column to slots table for multi-net support
ALTER TABLE slots 
ADD COLUMN IF NOT EXISTS net_number int NOT NULL DEFAULT 1;

-- Update unique index for slots to include net_number
DROP INDEX IF EXISTS slots_unique_time;
CREATE UNIQUE INDEX slots_unique_time
  ON slots (turf_id, date, start_time, net_number);

-- Update create_booking_atomic to support advance_amount and partial booking status
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
BEGIN
  SELECT * INTO slot_record FROM slots WHERE id = p_slot_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Slot not found';
  END IF;

  IF slot_record.status NOT IN ('AVAILABLE', 'RESERVED') THEN
    RAISE EXCEPTION 'Slot not available';
  END IF;

  -- Determine slot status based on payment
  -- Any advance amount (partial or full) = RESERVED (Partial/yellow)
  -- No advance (pay at turf) = BOOKED
  -- Only when owner manually marks as paid, slot becomes BOOKED
  v_advance_amount := COALESCE((p_booking_data->>'advance_amount')::numeric, 0);
  
  IF v_advance_amount > 0 THEN
    -- Has advance payment (any amount) - mark as reserved (Partial)
    v_slot_status := 'RESERVED';
  ELSE
    -- No advance payment (pay at turf) - mark as booked
    v_slot_status := 'BOOKED';
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
    (SELECT owner_id FROM turfs WHERE id = (p_booking_data->>'turf_id')::uuid),
    (p_booking_data->>'turf_id')::uuid,
    p_slot_id,
    (p_booking_data->>'booking_date')::date,
    p_booking_data->>'start_time',
    p_booking_data->>'end_time',
    p_booking_data->>'turf_name',
    COALESCE((p_booking_data->>'net_number')::int, 1),
    NULLIF(p_booking_data->>'user_id', '')::uuid,
    p_booking_data->>'customer_name',
    p_booking_data->>'customer_phone',
    p_booking_data->>'booking_source',
    p_booking_data->>'payment_mode',
    p_booking_data->>'payment_status',
    (p_booking_data->>'amount')::numeric,
    COALESCE((p_booking_data->>'advance_amount')::numeric, 0),
    p_booking_data->>'transaction_id',
    COALESCE(p_booking_data->>'booking_status', 'CONFIRMED'),
    now()
  ) RETURNING id INTO booking_id;

  RETURN booking_id;
END;
$$;
