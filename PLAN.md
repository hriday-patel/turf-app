# Stable Unified Auth Flow With Mandatory Phone Verification

## Summary
- Replace the current owner-only deferred signup with one shared staged auth flow for both `owner` and `player`.
- Keep the existing route structure and provider pattern, but make signup/login deterministic: email/password and Google remain the primary entry methods, while phone OTP is mandatory only for account creation, phone linking, or recovery, not every login.
- Enforce one global phone number per account across the whole app. If a phone is already linked anywhere, block the flow before completion and show a modal popup, not just a toast.
- Do not auto-merge Google and manual accounts. If Google is used with an email already tied to another account identity, stop with a clear dialog and instruct the user to log in with the existing method first.

## Key Changes
- Backend/auth state:
  - Add a `pending_auth_signups` table keyed by `auth.users.id` to persist in-progress signup state across app restarts. Store `role`, `name`, `email`, `phone`, `auth_method`, `has_password`, and timestamps.
  - Add idempotent RPCs for:
    - `check_phone_availability(phone, exclude_user_id)` to check owners, players, and pending signups.
    - `upsert_pending_signup(...)` to save deferred owner/player signup state after email signup or Google OAuth succeeds.
    - `finalize_pending_signup(user_id, verified_phone)` to atomically re-check phone uniqueness, create the correct profile row, merge auth methods with `otp`, and clear the pending row.
    - `get_pending_signup(user_id)` so startup recovery can resume verification instead of dropping the session.
  - Make `players.phone` and `players.email` unique, and add `auth_methods text[]` plus `has_password boolean` to `players` so player auth metadata matches owner behavior.
  - Keep existing owner RPCs compatible, but route new profile creation through the same global phone guard used by players.

- Flutter provider/service flow:
  - Generalize the provider’s deferred owner-only state into a role-agnostic pending signup state that covers `owner/player + email/google`.
  - Manual signup for both roles becomes:
    - validate form
    - check phone availability
    - create auth user
    - save pending signup
    - send phone change OTP
    - verify OTP
    - finalize profile
    - navigate
  - Google signup/login for both roles becomes:
    - sign in with Google
    - if existing profile exists, continue normally
    - if no profile exists, create/load pending signup and require phone + OTP before access
    - if same email maps to another identity, stop and show a blocking dialog
  - On app startup, if a Supabase session exists but no profile exists, check `pending_auth_signups` and resume the verification flow instead of marking the user logged out.
  - Preserve forgot-password behavior. Keep owner phone-login as legacy behavior if already present, but do not expand phone-only login for players in this pass.

- UI/UX flow:
  - Keep `OwnerAuthScreen` and `PlayerAuthScreen`, but move OTP completion into the auth journey itself so new users do not land on dashboard/home with an incomplete profile.
  - Add one shared blocking popup for duplicate phone numbers with copy like: “This phone number is already linked to another account. Please use a different number or log in with that account.”
  - Manual player signup must include phone OTP before the player profile is created.
  - Owner dashboard phone-lock remains only as a fallback for legacy incomplete accounts; new signups should complete verification before navigation.

## Interfaces And Types
- `PlayerModel` should gain:
  - `List<String> authMethods`
  - `bool hasPassword`
- `DatabaseService` should gain:
  - global phone availability lookup
  - pending signup create/load/finalize methods
- `AuthProvider` should expose shared pending flow state, such as:
  - pending role
  - pending auth method
  - whether phone verification is required
  - whether a pending signup is being resumed after restart

## Test Plan
- Provider tests:
  - owner manual signup goes into pending state, verifies OTP, finalizes owner profile
  - player manual signup requires OTP before profile creation
  - Google signup without existing profile requires phone verification for both roles
  - existing verified account logs in without OTP on later email/password or Google login
  - duplicate phone is blocked both on pre-check and on finalize-time race
  - pending signup session survives restart and resumes correctly
  - conflicting Google email on different identity returns the expected blocking message
- DB/migration tests:
  - players unique email/phone constraints work
  - owner/player cross-role duplicate phone is rejected
  - `finalize_pending_signup` creates exactly one profile and clears pending state
- Widget tests:
  - player manual signup transitions into OTP step
  - duplicate phone shows modal popup
  - Google flow with missing phone shows phone-entry + OTP UI

## Assumptions And Defaults
- One auth account maps to one role profile at a time.
- Global phone uniqueness applies across owners, players, and pending signups.
- OTP is mandatory for signup and phone linking, not for every later login.
- Google/manual accounts are not auto-merged during sign-in.
- Supabase email confirmation behavior stays as currently configured; this change focuses on phone verification and account-finalization stability.
