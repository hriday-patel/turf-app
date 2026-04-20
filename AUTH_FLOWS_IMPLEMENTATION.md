# Authentication Flows - Current Implementation

## Project: FieldPass Business (Turf App)

**Last Updated**: April 21, 2026
**Status**: Implemented in app code and analyzer-clean

---

## 1. Overview

The app uses a role-based authentication system with separate entry flows for:

- Owner
- Player

Supported sign-in methods in the current codebase:

- Email and password
- Google OAuth
- Phone OTP (owner phone login and verification gates)

Important behavior:

- New signups are first saved as pending signups.
- Profile creation is finalized only after phone OTP verification.
- Existing sessions are restored on app start and routed by role.

---

## 2. Core Components

### 2.1 Auth state and orchestration

- `lib/features/auth/providers/auth_provider.dart`
  - Central source of truth for auth state (`AuthStatus`)
  - Handles signup/login, OTP state machine, deferred signup, profile loading, role checks

### 2.2 Supabase auth operations

- `lib/data/services/auth_service.dart`
  - Email signup/login
  - Google OAuth start
  - OTP send/verify for SMS and phone-change flow
  - Password/email update and sign out

### 2.3 Database/RPC integration

- `lib/data/services/database_service.dart`
  - Owner/player profile creation and lookup
  - Global phone availability checks
  - Pending signup upsert/get/finalize
  - Owner OTP sync (`sync_owner_after_otp`)

### 2.4 Shared auth UI utilities

- `lib/features/auth/utils/auth_form_utils.dart`
  - Shared validation and normalization
  - Email, password, OTP, phone validators and formatters

- `lib/features/auth/widgets/pending_signup_verification_dialog.dart`
  - Shared OTP verification modal for pending owner/player signups

---

## 3. App Startup and Session Routing

### Splash flow

- `lib/features/auth/screens/splash_screen.dart`

Routing logic on startup:

1. Check existing auth session via `authProvider.checkAuthState()`.
2. If authenticated with owner profile -> route to owner dashboard.
3. If authenticated with player profile -> route to player home.
4. If authenticated but pending signup exists:
   - pending owner -> route to owner auth screen
   - pending player -> route to player auth screen
5. Otherwise -> route to login selection.

---

## 4. Owner Flows

### 4.1 Owner email/password login

Entry screen: `lib/features/auth/screens/owner_auth_screen.dart`

Flow:

1. User chooses Owner -> Login -> Email.
2. `authProvider.signIn(email, password)`.
3. Provider ensures account is owner role, signs out if role mismatch.
4. On success, app continues to owner dashboard readiness checks.

### 4.2 Owner phone OTP login (existing owner)

Entry screen: `lib/features/auth/screens/owner_auth_screen.dart`

Flow:

1. User chooses Owner -> Login -> Phone.
2. Send OTP: `authProvider.verifyPhone(phone)`.
3. Provider verifies owner exists by phone.
4. Verify OTP: `authProvider.verifyOTP(code)`.
5. Provider loads owner profile and syncs OTP auth method.

### 4.3 Owner manual signup (deferred + OTP)

Entry screen: `lib/features/auth/screens/owner_auth_screen.dart`

Flow:

1. User fills name/email/phone/password.
2. `authProvider.signUp(..., role: owner)`:
   - creates Supabase auth user
   - saves pending signup via RPC
   - stores deferred signup state in provider
3. Shared pending signup OTP dialog is shown.
4. OTP verify finalizes pending signup via RPC.
5. Owner profile is loaded and user can proceed.

### 4.4 Owner Google flow

Entry screen: `lib/features/auth/screens/owner_auth_screen.dart`

Flow:

1. User taps Google (login or signup path).
2. `authProvider.signInOwnerWithGoogle()`.
3. Provider behavior:
   - existing owner profile -> continue (and ensure `google` auth method)
   - no profile -> create pending signup and require OTP finalization
   - cross-role conflict -> blocks with clear message

### 4.5 Owner dashboard phone verification lock

Screen: `lib/features/owner/screens/owner_dashboard_screen.dart`

Behavior:

- If owner phone is unverified or pending, dashboard shows verification lock overlay.
- Owner must send/verify OTP to unlock full access.
- Supports resend/edit number.
- Allows "Back to Login" or "Cancel Signup" with confirmation.

### 4.6 Owner forgot password by OTP

Screen: `lib/features/auth/screens/owner_auth_screen.dart`

Flow:

1. Enter email.
2. Provider resolves registered phone.
3. Send OTP and verify OTP.
4. Set new password.
5. Provider sets `has_password=true` and ensures `email` auth method.

---

## 5. Player Flows

### 5.1 Player email/password login

Entry screen: `lib/features/auth/screens/player_auth_screen.dart`

Flow:

1. User chooses Player -> Login.
2. `authProvider.signInPlayer(email, password)`.
3. Provider ensures account is player role, signs out on mismatch.
4. On success -> player home.

### 5.2 Player Google flow

Entry screen: `lib/features/auth/screens/player_auth_screen.dart`

Flow:

1. User taps Google.
2. `authProvider.signInPlayerWithGoogle()`.
3. Provider behavior:
   - existing player profile -> continue (and ensure `google` auth method)
   - no profile -> pending signup created and OTP required
   - cross-role conflict -> blocked

### 5.3 Player manual signup (deferred + OTP)

Entry screen: `lib/features/auth/screens/player_auth_screen.dart`

Flow:

1. User fills signup form and submits.
2. `authProvider.signUp(..., role: player)`.
3. Shared pending signup OTP dialog is shown.
4. OTP verification finalizes pending signup and creates player profile.
5. On success -> player home.

### 5.4 Player phone OTP note

Current implementation does **not** expose a standalone player phone-login tab.

- `sendPlayerOtp()` is currently used only for pending player signup verification context.

---

## 6. OTP Flow Mapping (Provider State Machine)

Provider enum: `_OtpFlow`

- `ownerLogin`
  - send: `signInWithOtp(shouldCreateUser: false)`
  - verify: `verifyOTP(type: sms)`

- `playerLogin`
  - send: `signInWithOtp(shouldCreateUser: true)`
  - verify: `verifyOTP(type: sms)`
  - used in constrained paths only

- `ownerPhoneVerification`
  - send: `updateUser(phone)`
  - verify: `verifyOTP(type: phoneChange)`

- `deferredSignup`
  - send: `updateUser(phone)`
  - verify: `verifyOTP(type: phoneChange)`
  - then finalize pending signup via RPC

- `forgotPassword`
  - send: `signInWithOtp`
  - verify: `verifyOTP(type: sms)`

---

## 7. Data Model and Auth Metadata

### Owner model

- `lib/data/models/owner_model.dart`
- Key auth fields:
  - `authMethods`
  - `hasPassword`
  - `phone`

### Player model

- `lib/data/models/player_model.dart`
- Key auth fields:
  - `authMethods`
  - `hasPassword`
  - `phone`

### Deferred signup TTL

- `lib/core/utils/auth_flow_rules.dart`
- Pending signup expires after 30 minutes (`deferredSignupTtl`).

---

## 8. Required Supabase Functions / RPC Contracts

The current implementation depends on the following RPC functions:

- `check_owner_exists`
- `create_owner_profile`
- `create_player_profile`
- `check_phone_availability`
- `upsert_pending_signup`
- `get_pending_signup`
- `finalize_pending_signup`
- `sync_owner_after_otp`

If any of these are missing/misaligned, signup/verification behavior can fail or partially complete.

---

## 9. Validation and Security Behaviors

Shared auth validation now lives in `auth_form_utils.dart`:

- Email format validation
- Indian phone input validation and normalization to E.164-style `+91xxxxxxxxxx`
- OTP format validation (6 digits)
- Password strength validation

Additional protections:

- Global phone conflict checks before OTP send and before finalize
- Role mismatch protection on login
- Blocking dialog messages for cross-account conflicts
- Fallback error mapping for auth/provider/network failures

---

## 10. Known Implementation Notes

1. OTP provider path in current code is Supabase Auth OTP APIs.
2. MSG91 is not wired as a primary OTP backend in this code path yet.
3. Owner dashboard contains a separate in-dashboard verification lock for unverified phone access.

---

## 11. Quick Test Matrix

### Owner

- Email login success/failure and role mismatch handling
- Phone OTP login success/failure
- Manual signup -> pending dialog -> OTP -> finalize
- Google signin/signup -> pending handling where profile missing
- Dashboard phone lock verify + resend + cancel/back behavior
- Forgot password OTP -> set new password

### Player

- Email login success/failure and role mismatch handling
- Manual signup -> pending dialog -> OTP -> finalize
- Google signin/signup -> pending handling where profile missing
- Resume pending signup on relaunch

---

## 12. File Index

- `lib/features/auth/providers/auth_provider.dart`
- `lib/data/services/auth_service.dart`
- `lib/data/services/database_service.dart`
- `lib/features/auth/screens/splash_screen.dart`
- `lib/features/auth/screens/owner_auth_screen.dart`
- `lib/features/auth/screens/player_auth_screen.dart`
- `lib/features/auth/widgets/pending_signup_verification_dialog.dart`
- `lib/features/auth/utils/auth_form_utils.dart`
- `lib/features/owner/screens/owner_dashboard_screen.dart`
- `lib/core/utils/auth_flow_rules.dart`
