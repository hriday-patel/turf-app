# AI Prompt: Build a Turf Booking App (React Native + Python)

Copy everything below this line and give it to the AI.

---

## PROJECT OVERVIEW

Build a **turf/sports venue booking management app** using **React Native** (Expo) for the frontend and **Python** (FastAPI) for the backend, with **PostgreSQL** as the database.

The app has TWO user roles:

1. **Owner** — manages turfs, slots, bookings, pricing
2. **Player** — browses approved turfs, books slots via the app

Admin approval of turfs is handled via external scripts (not in-app).

---

## TECH STACK

- **Frontend**: React Native (Expo), React Navigation, Zustand (state management)
- **Backend**: Python FastAPI, SQLAlchemy ORM, Alembic migrations
- **Database**: PostgreSQL
- **Auth**: JWT-based (email + phone OTP)
- **Storage**: S3-compatible object storage for images

---

## COMPLETE DATABASE SCHEMA

### Tables

```sql
-- Owners (turf managers)
CREATE TABLE owners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL DEFAULT 'OWNER',
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  profile_image TEXT,
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

-- Players (customers)
CREATE TABLE players (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'PLAYER',
  profile_image TEXT,
  favorite_turfs TEXT[] NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

-- Turfs (venues)
CREATE TABLE turfs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES owners(id) ON DELETE CASCADE,
  turf_name TEXT NOT NULL,
  turf_type TEXT NOT NULL,            -- 'BOX_CRICKET' | 'GROUND_CRICKET'
  number_of_nets INT NOT NULL DEFAULT 1,
  city TEXT NOT NULL,
  address TEXT NOT NULL,
  location JSONB,                      -- {lat, lng}
  description TEXT,
  open_time TEXT NOT NULL,             -- "06:00" (24-hour format)
  close_time TEXT NOT NULL,            -- "23:00" or "02:00" (overnight)
  slot_duration_minutes INT NOT NULL,  -- 30, 60, 90, etc.
  days_open TEXT[] NOT NULL,           -- ['MON','TUE','WED','THU','FRI','SAT','SUN']
  pricing_rules JSONB NOT NULL,        -- see Pricing Structure below
  public_holidays TEXT[] NOT NULL DEFAULT '{}',  -- ['2026-01-26', ...]
  images JSONB NOT NULL DEFAULT '[]',
  is_approved BOOLEAN NOT NULL DEFAULT FALSE,
  verification_status TEXT NOT NULL DEFAULT 'PENDING',  -- PENDING|APPROVED|REJECTED
  rejection_reason TEXT,
  status TEXT NOT NULL DEFAULT 'OPEN',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

-- Slots (time slots for each net, each day)
CREATE TABLE slots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  turf_id UUID NOT NULL REFERENCES turfs(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  start_time TEXT NOT NULL,       -- "18:00"
  end_time TEXT NOT NULL,         -- "19:00"
  net_number INT NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'AVAILABLE',  -- AVAILABLE|RESERVED|BOOKED|BLOCKED
  reserved_until TIMESTAMPTZ,
  reserved_by UUID,
  price NUMERIC NOT NULL,
  price_type TEXT NOT NULL,       -- "WEEKDAY_MORNING", "WEEKEND_EVENING", etc.
  blocked_by UUID,
  block_reason TEXT,              -- see Block Reasons section
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX slots_unique_time ON slots (turf_id, date, start_time, net_number);

-- Bookings
CREATE TABLE bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES owners(id) ON DELETE CASCADE,
  turf_id UUID NOT NULL REFERENCES turfs(id) ON DELETE CASCADE,
  slot_id UUID NOT NULL REFERENCES slots(id) ON DELETE RESTRICT,
  booking_date DATE NOT NULL,
  start_time TEXT NOT NULL,
  end_time TEXT NOT NULL,
  turf_name TEXT NOT NULL,
  net_number INT NOT NULL DEFAULT 1,
  user_id UUID,                    -- NULL for phone/walk-in bookings
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL,
  booking_source TEXT NOT NULL,     -- APP|PHONE|WALK_IN
  payment_mode TEXT NOT NULL,       -- ONLINE|OFFLINE
  payment_status TEXT NOT NULL,     -- PAID|PENDING|PAY_AT_TURF
  amount NUMERIC NOT NULL,
  advance_amount NUMERIC NOT NULL DEFAULT 0,
  transaction_id TEXT,
  booking_status TEXT NOT NULL DEFAULT 'CONFIRMED',  -- CONFIRMED|CANCELLED
  cancelled_at TIMESTAMPTZ,
  cancelled_by TEXT,
  cancellation_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX bookings_slot_unique ON bookings (slot_id) WHERE booking_status = 'CONFIRMED';
CREATE INDEX bookings_owner_date_idx ON bookings (owner_id, booking_date);
CREATE INDEX slots_turf_date_idx ON slots (turf_id, date, start_time);
```

---

## CRITICAL BUSINESS LOGIC RULES

### 1. Slot Generation (Full 24-Hour)

When the owner views slots for a date, generate ALL 24 hours of slots (0:00 to 23:59) for EVERY net:

- Slots **within operating hours** and on an **open day** → status `AVAILABLE`
- Slots **outside operating hours** OR on a **closed day** → status `BLOCKED`, block_reason `'Closed'`
- Use **upsert with ON CONFLICT ignore** so existing slots (booked, reserved, manually blocked) are never overwritten
- Slot duration comes from turf config (e.g., 60 min = 24 slots per net per day)

### 2. Operating Hours — OVERNIGHT LOGIC (CRITICAL)

Turfs can have overnight hours like open_time=18:00, close_time=02:00. This means the turf is open from 6 PM to 2 AM.

**The math:**

```
openMinutes = parse(open_time) → e.g., 1080 (18:00)
closeMinutesRaw = parse(close_time) → e.g., 120 (02:00)

if closeMinutesRaw == 0:
    closeMinutes = 1440          # midnight = end of day
elif closeMinutesRaw == openMinutes:
    closeMinutes = openMinutes   # invalid config, treat as fully closed
elif closeMinutesRaw < openMinutes:
    closeMinutes = closeMinutesRaw + 1440   # OVERNIGHT WRAP
else:
    closeMinutes = closeMinutesRaw          # normal hours
```

**Is a slot within operating hours?**

```
if closeMinutes == openMinutes:
    return False  # invalid config
elif closeMinutes <= 1440:
    # Normal hours (e.g., 06:00-23:00)
    return slotStart >= openMinutes AND slotEnd <= closeMinutes
else:
    # Overnight hours (e.g., 18:00-02:00)
    # Day portion: slot is entirely between open time and midnight
    inDayPortion = slotStart >= openMinutes AND slotEnd <= 1440
    # Night portion: slot is entirely between midnight and close time
    inNightPortion = slotStart < (closeMinutes - 1440) AND slotEnd <= (closeMinutes - 1440)
    return inDayPortion OR inNightPortion
```

> **BUG TO AVOID**: Do NOT use `slotStart >= openMinutes AND slotEnd <= closeMinutes` for overnight hours. A slot at 01:00 (60 min) would fail `60 >= 1080`. You MUST split into day portion and night portion checks.

> **BUG TO AVOID**: When closeMinutesRaw is 0 (midnight), treat it as 1440 (end of day), NOT as overnight.

### 3. Time Periods (4 divisions)

All period-based logic MUST use these EXACT same boundaries everywhere:

```
Morning:   hours 6-11   (6:00 AM - 11:59 AM)
Afternoon: hours 12-17  (12:00 PM - 5:59 PM)
Evening:   hours 18-23  (6:00 PM - 11:59 PM)
Night:     hours 0-5    (12:00 AM - 5:59 AM)
```

> **BUG TO AVOID**: If you have TWO functions that classify slots into periods (e.g., one for grouping, one for toggle logic), they MUST use identical boundary logic. If one uses `hour >= 6 && hour < 12` and another uses `hour > 5 && hour <= 11`, edge cases will break.

### 4. Block Reasons Taxonomy

These block_reason values have specific semantic meaning:

- `'Closed'` — auto-blocked (outside operating hours or closed day)
- `'Outside operating hours'` — legacy auto-block (treat same as 'Closed')
- `'Period closed by owner'` — owner toggled a period OFF
- `'Blocked by owner'` — owner manually blocked a specific available slot
- `'Closed by owner'` — owner manually re-closed a slot they had opened
- `'Day opened by owner'` — **OVERRIDE MARKER** (see below)
- `NULL` — default, no block

### 5. Manual Override System (CRITICAL)

Owners can open individual slots even when the period or day is closed. This uses an **override marker pattern**:

- When a slot is unblocked on a **closed day** (day not in `days_open`), store `block_reason = 'Day opened by owner'` on the now-AVAILABLE slot
- This marker tells the sync logic: "don't re-close this slot even though the day is closed"
- When the day becomes officially open (added to `days_open`), clear the override markers (set block_reason to NULL)

**The sync function must:**

1. First enforce `days_open`: block non-overridden AVAILABLE slots on closed days
2. On open days: clear override markers (no longer needed), unblock auto-closed slots now within operating hours
3. Enforce operating hours: block AVAILABLE slots outside hours on open days

> **BUG TO AVOID**: Never clear ALL override markers on every sync. Only clear markers for the specific turf+net being synced. If you wipe all markers globally, switching dates will destroy overrides on other dates.

> **BUG TO AVOID**: When checking if a slot should be preserved during period toggle changes, both `'Blocked by owner'` AND `'Closed by owner'` must be treated as manual blocks that should NOT be auto-unblocked by period toggles.

### 6. Toggle System (Owner UI)

The owner screen has these toggles per turf+net+date:

- **DAY OPEN/CLOSED** — master toggle for the entire day
- **Morning/Afternoon/Evening/Night** — individual period toggles

Rules:

- Toggling DAY OFF → sets all 4 periods OFF → blocks all non-booked/reserved slots
- Toggling DAY ON → sets all 4 periods ON → unblocks auto-closed slots within operating hours
- Toggling a single period OFF → blocks available slots in that period
- All periods OFF → DAY toggle auto-turns OFF
- Any period ON while DAY is OFF → DAY toggle auto-turns ON
- **Period toggles are independent per-net**: toggling Morning off on Net 1 must NOT affect Net 2
- Toggle states are keyed by `"turfId_netNumber_dateString"`

**Toggle state derivation from DB (on screen load):**

- For each period, check if ANY slot within operating hours is AVAILABLE
- If yes → period is OPEN. If no available slots in that period → period is CLOSED
- Derive DAY toggle from: any period open → day open

> **BUG TO AVOID**: When the user navigates away and back, do NOT blindly clear all toggle states. Each turf+net+date has its own state. If the user already interacted with toggles for the current key, don't overwrite from DB — the user's intent takes priority until they navigate to a different turf/net/date.

> **BUG TO AVOID**: Override markers (`_manuallyOpenedSlots`) must be rebuilt from DB on every load for the CURRENT turf+net, even if toggle states are preserved. Use scoped cleanup (only clear entries for current turf+net prefix), not global clear.

### 7. Slot Status Lifecycle

```
AVAILABLE → RESERVED (user starts booking → 10-min reservation)
RESERVED → BOOKED (payment confirmed or advance >= total)
RESERVED → AVAILABLE (reservation expires or cancelled)
AVAILABLE → BLOCKED (owner blocks, period toggle, or auto-close)
BLOCKED → AVAILABLE (owner unblocks, period toggle opens, or sync)
BOOKED → AVAILABLE (booking cancelled via atomic RPC)
```

**Booking creates MUST be atomic** (single transaction):

1. Lock the slot row with `SELECT ... FOR UPDATE`
2. Verify slot is AVAILABLE or RESERVED
3. Determine slot status: if `advance_amount >= total_amount` → BOOKED, else → RESERVED
4. Update slot status
5. Insert booking row
6. Return booking ID

**Booking cancellation MUST be atomic**:

1. Update booking status to CANCELLED
2. Release slot back to AVAILABLE

> **BUG TO AVOID**: After cancelling a booking, update ALL relevant local state lists (bookings, todaysBookings, pendingPayments). Don't just rely on a stream refresh — the user sees stale data until the next stream event.

> **BUG TO AVOID**: Never clamp or auto-expire reservations client-side. The server RPC handles reservation expiry. Client should treat RESERVED slots as unavailable and refresh from server.

### 8. Pricing System

```json
{
  "nets": [
    {
      "net_number": 1,
      "net_name": "Net 1",
      "weekday": {
        "morning":   { "label": "Morning",   "start_time": "06:00", "end_time": "12:00", "price": 800 },
        "afternoon": { "label": "Afternoon", "start_time": "12:00", "end_time": "18:00", "price": 800 },
        "evening":   { "label": "Evening",   "start_time": "18:00", "end_time": "00:00", "price": 1200 },
        "night":     { "label": "Night",     "start_time": "00:00", "end_time": "06:00", "price": 1000 }
      },
      "weekend": { ... same structure, different prices ... },
      "holiday": { ... same structure, different prices ... }
    },
    { "net_number": 2, ... }
  ]
}
```

- Price is determined by **slot start hour only** (not end hour). A slot 11:30-12:30 uses morning price.
- Day type: weekday (Mon-Fri), weekend (Sat-Sun), holiday (date in public_holidays list)
- Each net can have independent pricing
- `price_type` stored on slot: `"WEEKDAY_EVENING"`, `"HOLIDAY_NIGHT"`, etc.

**Price sync on every slot view:**

- For AVAILABLE and BLOCKED slots, recalculate price from current pricing rules
- If price or price_type changed, update the slot in DB
- Do NOT change prices on BOOKED or RESERVED slots (preserves booking amount)

### 9. Advance Amount Clamping

When creating a booking, clamp `advance_amount` to not exceed `total_amount`:

```python
clamped_advance = min(advance_amount, total_amount) if advance_amount > total_amount else advance_amount
```

> **BUG TO AVOID**: If a user enters advance=1500 for a slot priced at 1000, the advance must be clamped to 1000. Without clamping, the "balance due" display goes negative.

### 10. Concurrency Guards

- **Slot block/unblock**: Use a per-slot lock (e.g., a Set of slot IDs currently being operated on). If slot X is being blocked, reject a concurrent unblock on slot X.
- **Slot generation**: Use a per-turf+date lock. If generation is in progress for turf A on date X, skip duplicate generation requests.
- **Optimistic UI updates**: Update local state immediately for instant feedback, then persist to DB. On error, reload from DB to revert.

> **BUG TO AVOID**: Rapid date switching causes multiple async load chains. Use a generation counter: each `loadSlots()` call increments a counter, and the async callback checks if its counter matches the current value before applying results. Stale responses from earlier requests must be discarded.

### 11. Multi-Net Consistency

- Each net is independent: its own slots, own prices, own toggle states
- Period toggles apply to the CURRENTLY SELECTED net only
- When switching nets, reload toggle states for the new net
- When owner selects a multi-net turf, load slots immediately (don't wait for net selection — default to Net 1)

> **BUG TO AVOID**: When switching turfs in a sidebar, always call loadSlots() regardless of whether the sidebar stays open. Otherwise, multi-net turfs show stale/no data until the user explicitly selects a net.

---

## COMPLETE FEATURE LIST

### Owner Features

1. **Auth**: Email signup/login, phone OTP
2. **Turf Management**: Add turf (name, type, city, address, location, images), edit turf, view verification status
3. **Turf Configuration**: Set open/close times, slot duration, days open, number of nets, pricing rules (per net, per day type, per period), public holidays
4. **Slot Management Screen**: View all 24-hour slots in a grid grouped by period (Night, Morning, Afternoon, Evening), with inline period toggles and DAY toggle
5. **Slot Actions**: Tap a slot to see contextual actions:
   - Available → "Create Booking" or "Close Slot"
   - Blocked/Period-closed → "Open This Slot" (manual override)
   - Manually opened → "Close This Slot"
   - Reserved → "Mark Payment Received", "Cancel Booking", "View Payment Details"
   - Booked → "Cancel Booking", "View Payment Details"
6. **Manual Booking**: Create bookings for phone/walk-in customers (name, phone, amount, advance, source)
7. **Booking Dialog**: In-grid booking creation with editable price, advance amount, booking source, WhatsApp confirmation
8. **Dashboard**: Today's bookings count, pending payments, total bookings
9. **Booking History**: View all bookings with filters
10. **WhatsApp Integration**: Send booking confirmations and receipts via WhatsApp

### Player Features

1. **Auth**: Phone OTP login
2. **Browse Turfs**: View approved turfs, filter by city
3. **View Slots**: See available slots for a turf on a date
4. **Book Slot**: Reserve → Pay → Confirm flow with 10-min reservation window
5. **My Bookings**: View active and past bookings
6. **Cancel Booking**: Cancel with reason

### Slot Grid UI (Owner)

- Sorted slots displayed in 4 sections: Night (12AM-6AM), Morning (6AM-12PM), Afternoon (12PM-6PM), Evening (6PM-12AM)
- Night appears FIRST (top of page) because overnight turfs often have early-morning slots
- Color coding: Green=Available, Orange=Reserved/Pending, Red=Booked, Grey=Closed
- Lock icon on closed slots, unlock icon on manually opened slots
- Past slots (before current time today) shown with reduced opacity
- Each period section header has an inline OPEN/CLOSED toggle

---

## SPECIFIC BUGS TO PREVENT

These are real bugs found through extensive testing. Implement defenses against each:

### B1: Overnight Hours Calculation

**Wrong**: `slotStart >= openMinutes && slotEnd <= closeMinutes` when closeMinutes > 1440
**Right**: Split into day portion (open to midnight) and night portion (midnight to close-1440)

### B2: Midnight Handling

**Wrong**: `closeMinutesRaw = 0` treated as overnight (0 < anything)
**Right**: `closeMinutesRaw == 0` → set to 1440 (end of day)

### B3: openTime == closeTime

**Wrong**: Not handled (causes all slots to be available or infinite loop)
**Right**: Treat as fully closed (no operating hours)

### B4: Period Toggle Independence

**Wrong**: \_applyPeriodChanges iterates ALL slots (all nets)
**Right**: ONLY iterate slots for the currently selected net

### B5: Manual Override Lost on Navigation

**Wrong**: `manuallyOpenedSlots.clear()` on every `updateToggleStatesFromSlots()`
**Right**: Only clear entries for current turf+net prefix, rebuild from DB

### B6: Toggle State Guard Blocks Override Rebuild

**Wrong**: Check `if toggleStates.has(key) return` BEFORE rebuilding overrides from DB
**Right**: Rebuild overrides FIRST (always), THEN check toggle guard

### B7: Race Condition on Rapid Date Switch

**Wrong**: Two async loadSlots chains race; stale one might finish last
**Right**: Use generation counter; discard stale responses

### B8: 'Closed by owner' Not Treated as Manual Block

**Wrong**: Only checking `block_reason == 'Blocked by owner'` as manual
**Right**: Also include `'Closed by owner'` as a manual block that period toggles should respect

### B9: Booking Cancel Stale UI

**Wrong**: Only relying on server/stream to update lists after cancel
**Right**: Immediately remove from ALL local lists (bookings, todaysBookings, pendingPayments)

### B10: Advance > Amount Not Clamped

**Wrong**: advance_amount=1500, amount=1000 → balance = -500
**Right**: `clamped_advance = min(advance, amount)`

### B11: Client-Side Reservation Expiry

**Wrong**: `isAvailable = status == AVAILABLE || (RESERVED && expired)`
**Right**: Only server handles expiry. Client: `isAvailable = status == AVAILABLE`

### B12: Multi-Net Turf Selection Skips Loading

**Wrong**: If sidebar stays open (multi-net), slots aren't loaded until net selected
**Right**: Always call loadSlots on turf selection, default to Net 1

### B13: Slot Price Mutation on Booking

**Wrong**: Modifying the slot model's price in-place when owner edits booking amount
**Right**: Use a separate variable for booking amount; only update slot price in DB after successful booking

### B14: batchCreateSlots Without Conflict Handling

**Wrong**: INSERT fails on duplicate (turf_id, date, start_time, net_number)
**Right**: Use UPSERT with ON CONFLICT DO NOTHING (ignoreDuplicates) to preserve existing booked/reserved slots

### B15: numberOfNets Validation

**Wrong**: Generating slots when `number_of_nets <= 0`
**Right**: Validate before generation; return error if <= 0

---

## API ENDPOINTS TO IMPLEMENT

### Auth

- `POST /auth/signup/owner` — create owner account
- `POST /auth/signup/player` — create player account
- `POST /auth/login` — email/password login
- `POST /auth/otp/send` — send phone OTP
- `POST /auth/otp/verify` — verify OTP

### Turfs

- `GET /turfs/owner` — list owner's turfs
- `POST /turfs` — create turf
- `PUT /turfs/{id}` — update turf
- `GET /turfs/approved` — list approved turfs (for players)
- `GET /turfs/{id}` — get turf details

### Slots

- `POST /slots/generate` — generate 24-hour slots for a turf+date
- `GET /slots/{turf_id}/{date}` — get all slots for a turf+date
- `POST /slots/{id}/block` — block a slot
- `POST /slots/{id}/unblock` — unblock a slot (with optional override_marker)
- `POST /slots/{id}/reserve` — reserve a slot (10-min window)
- `POST /slots/{id}/release` — release reservation

### Bookings

- `POST /bookings` — create booking (atomic: lock slot + insert booking)
- `POST /bookings/{id}/cancel` — cancel booking (atomic: update booking + release slot)
- `GET /bookings/owner` — owner's bookings
- `GET /bookings/today` — today's bookings
- `GET /bookings/pending-payments` — pending payment bookings
- `POST /bookings/{id}/mark-paid` — mark payment received
- `GET /bookings/by-slot/{slot_id}` — get booking by slot

---

## PROJECT STRUCTURE

```
/
├── mobile/                     # React Native (Expo)
│   ├── app/                    # Expo Router screens
│   │   ├── (auth)/             # Auth screens
│   │   ├── (owner)/            # Owner tabs
│   │   │   ├── dashboard/
│   │   │   ├── slots/          # Slot management screen
│   │   │   ├── bookings/
│   │   │   └── settings/
│   │   └── (player)/           # Player tabs
│   ├── components/
│   ├── hooks/
│   ├── stores/                 # Zustand stores
│   │   ├── authStore.ts
│   │   ├── turfStore.ts
│   │   ├── slotStore.ts        # THE MOST COMPLEX STORE
│   │   └── bookingStore.ts
│   ├── services/
│   │   └── api.ts              # API client
│   ├── utils/
│   │   ├── priceCalculator.ts
│   │   ├── timeUtils.ts        # Operating hours logic
│   │   └── constants.ts
│   └── types/
│       └── index.ts            # TypeScript interfaces
│
├── backend/                    # Python FastAPI
│   ├── main.py
│   ├── config.py
│   ├── models/                 # SQLAlchemy models
│   ├── schemas/                # Pydantic schemas
│   ├── routes/
│   │   ├── auth.py
│   │   ├── turfs.py
│   │   ├── slots.py
│   │   └── bookings.py
│   ├── services/
│   │   ├── slot_service.py     # Slot generation + sync logic
│   │   ├── booking_service.py  # Atomic booking operations
│   │   └── price_service.py
│   └── utils/
│       └── time_utils.py       # Operating hours calculations
│
├── migrations/                 # Alembic
└── docker-compose.yml
```

---

## IMPLEMENTATION PRIORITIES

Build in this order:

1. **Database + migrations** — all tables, indexes, constraints
2. **Auth** — signup, login, JWT
3. **Turf CRUD** — create, read, update with image upload
4. **Slot generation engine** — the most complex piece. Get overnight hours RIGHT.
5. **Slot management API** — block, unblock, sync operating hours, sync prices
6. **Slot management UI** — the grid with toggles, override system
7. **Booking flow** — atomic create + cancel
8. **Booking UI** — dialog, manual booking screen
9. **Dashboard + history**
10. **Player features**

---

## TESTING SCENARIOS TO VERIFY

After building, manually verify these:

1. **Overnight turf** (open 18:00, close 02:00): Slots 18:00-01:00 should be AVAILABLE, slots 02:00-17:00 should be BLOCKED
2. **Midnight close** (open 06:00, close 00:00): All slots 06:00-23:00 AVAILABLE, 00:00-05:00 BLOCKED
3. **Same open/close** (open 10:00, close 10:00): ALL slots BLOCKED
4. **Closed day**: If today is MON and MON not in days_open → all slots BLOCKED
5. **Override on closed day**: Block all → manually open 1 slot → navigate away → come back → that slot should still be open (override marker preserved)
6. **Period toggle**: Close Morning on Net 1 → verify Net 2 morning is unaffected
7. **Rapid date switch**: Tap date 1, immediately tap date 2 → should show date 2 data, not date 1
8. **Book → Cancel → Verify**: Create booking → cancel → slot returns to AVAILABLE, booking removed from all lists
9. **Advance clamping**: Enter advance > total → advance should be clamped to total
10. **Multi-net turf selection**: Select multi-net turf → should immediately load Net 1 slots
