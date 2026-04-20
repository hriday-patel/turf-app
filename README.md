# Turf Booking App

Production-focused Flutter app for turf owners and players, built on Supabase.

## Stack

- Frontend: Flutter + Provider
- Backend/Data: Supabase (Auth + Postgres + RLS)
- Serverless utilities: Node serverless handlers in api/
- Media storage: Supabase Storage via direct upload + API proxy

## Local Setup

1. Install dependencies

```bash
flutter pub get
npm install
```

2. Configure runtime values

Use .env.example as reference. For Flutter, pass values as dart-defines:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=SUPABASE_ANON_KEY \
  --dart-define=STORAGE_BUCKET=STORAGE_BUCKET
```

For Android release builds, use the PowerShell helper to ensure required
Supabase runtime config is embedded into the AAB:

```powershell
./scripts/build_android_release.ps1 -SupabaseUrl "SUPABASE_URL" -SupabaseAnonKey "SUPABASE_ANON_KEY" -StorageBucket "STORAGE_BUCKET"
```

3. Configure serverless environment (hosting platform of your choice)

- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY
- STORAGE_BUCKET
- WHATSAPP_API_KEY
- WHATSAPP_PHONE_ID

Optional runtime define for app calls to your serverless APIs:

```bash
--dart-define=API_BASE_URL=https://<your-api-domain>/api
```

## Supabase Migration Steps

Run schema and migrations in Supabase SQL Editor (in order):

1. supabase/schema.sql (baseline)
2. supabase/migrations/add_number_of_nets_and_status.sql
3. supabase/migrations/20260130_add_advance_amount.sql
4. supabase/migrations/20260316_add_renovation_net_numbers.sql
5. supabase/migrations/20260321_add_owner_has_password.sql
6. supabase/migrations/20260330_auth_player_hardening.sql

## Core Flows

### Owner

- Email/password signup with deferred owner profile completion after OTP
- Google owner auth with progressive password unlock support
- OTP verification gates dashboard access for missing/invalid phone state
- Turf creation/editing with multi-net slot generation and pricing sync
- Atomic booking create/cancel via Postgres RPCs

### Player (MVP)

- Phone OTP auth entry + profile completion
- Browse approved turfs
- View slots by date
- Book available slot (app booking)
- View own bookings

## Current Status

### Done

- Secure Supabase config loading via dart-defines (removed hardcoded credentials)
- Added .env.example placeholder template
- Added owner OTP atomic sync RPC integration
- Added migration for auth + player access policy hardening
- Added Player Home MVP screen and routing
- Added player bookings query and slot viewing capability via RLS policy
- Storage serverless bucket selection now environment-driven

### Partially Done

- WhatsApp Cloud API webhook persistence is still minimal (logs + ack only)
- Full booking lifecycle tests are focused but not exhaustive integration tests

### Pending

- Full payment gateway integration for player online payments
- Advanced player discovery filters and location search
- End-to-end CI pipeline for migration + app smoke validation

## SECURITY_NOTES

- Never commit real credentials. Use placeholders from .env.example.
- Rotate SUPABASE_SERVICE_ROLE_KEY and WHATSAPP_API_KEY periodically.
- Keep WHATSAPP_API_KEY and SUPABASE_SERVICE_ROLE_KEY server-side only.
- If any real key was previously committed, rotate it in the provider console and invalidate old tokens.

## Validation Commands

```bash
flutter analyze
flutter test
flutter build web --release --dart-define=SUPABASE_URL=SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=SUPABASE_ANON_KEY --dart-define=STORAGE_BUCKET=STORAGE_BUCKET
```
