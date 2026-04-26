import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/auth_config.dart';
import '../../features/auth/utils/auth_form_utils.dart';

/// Result of an email signup attempt.
///
/// When [needsEmailConfirmation] is true, [userId] is non-null but there is
/// no active session yet — the user must click the confirmation link in the
/// email before any RLS-protected calls (e.g. profile creation) will work.
class EmailSignUpResult {
  final String userId;
  final bool needsEmailConfirmation;

  const EmailSignUpResult({
    required this.userId,
    required this.needsEmailConfirmation,
  });
}

/// Authentication Service
///
/// Single chokepoint for every Supabase Auth operation in the app.
///
/// Hardening layers in this file:
///   * `_lastOtpRequestAt`         — per-process, per-phone client-side OTP
///                                  cooldown with LRU cap. Real defense
///                                  lives server-side; this just stops UI
///                                  loops and accidental spam from this
///                                  device. (Phase 4 Iter 9 AS-01)
///   * `_assertStrongPassword`     — single source of truth for the
///                                  password-strength rule. Used by signup
///                                  and both update-password paths.
///                                  (Phase 4 Iter 9 AS-07)
///   * `reauthenticateWithPassword` — mandatory before `updateEmail` /
///                                  `updatePassword` to defend against
///                                  session-hijack account takeover.
///   * `deleteAccount`             — calls the SECURITY DEFINER RPC
///                                  `delete_my_account` so cascade-delete
///                                  of owners/turfs/slots/bookings is
///                                  atomic with auth.users removal.
class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Per-(intent, phone) client-side cooldown timestamps.
  ///
  /// Phase 4 Iter 9 AS-01: this map is per-process and capped to
  /// [_otpCooldownMaxEntries] entries to bound memory; the oldest entry
  /// is evicted when the cap is hit. Restarts reset it. The real defense
  /// against SMS bombing is the Supabase project's server-side rate limit.
  ///
  /// Phase 4 Iter 9 AS-06: keyed by `'$intent:$phone'` so a phone-change
  /// OTP and a login OTP for the same number do not throttle each other.
  static final Map<String, DateTime> _lastOtpRequestAt = {};
  static const int _otpCooldownMaxEntries = 100;

  // Current user getters
  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;
  String? get currentUserEmail => _client.auth.currentUser?.email;
  String? get currentUserPhone => _client.auth.currentUser?.phone;
  bool get isLoggedIn => _client.auth.currentUser != null;
  Session? get currentSession => _client.auth.currentSession;

  // Auth state stream
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Phase 4 Iter 9 AS-07: shared password-strength check. Single message
  /// keeps signup, update, and reset-flow updates in lock-step.
  void _assertStrongPassword(String password) {
    if (!AuthFormUtils.isStrongPassword(password)) {
      throw AuthException(
        'Password must be at least 8 characters and include upper, lower, '
        'number, and special character.',
      );
    }
  }

  /// Throws an [AuthException] when the same `(intent, phone)` hit the OTP
  /// endpoint less than [AuthConfig.otpResendCooldownSeconds] ago.
  /// Local-only throttle — Supabase still applies its own server-side
  /// rate limit.
  void _enforceOtpCooldown(String intent, String phone) {
    final key = '$intent:$phone';
    final last = _lastOtpRequestAt[key];
    if (last == null) return;
    final elapsed = DateTime.now().difference(last).inSeconds;
    final cooldown = AuthConfig.otpResendCooldownSeconds;
    if (elapsed < cooldown) {
      final wait = cooldown - elapsed;
      throw AuthException(
        'Please wait $wait seconds before requesting another OTP.',
      );
    }
  }

  void _markOtpSent(String intent, String phone) {
    final key = '$intent:$phone';
    // Phase 4 Iter 9 AS-01: bound memory — evict the oldest entry when at
    // cap. Map preserves insertion order, so the first key is the oldest.
    if (!_lastOtpRequestAt.containsKey(key) &&
        _lastOtpRequestAt.length >= _otpCooldownMaxEntries) {
      _lastOtpRequestAt.remove(_lastOtpRequestAt.keys.first);
    }
    _lastOtpRequestAt[key] = DateTime.now();
  }

  /// Sign up with email and password.
  ///
  /// Returns an [EmailSignUpResult] indicating whether email confirmation is
  /// pending. When it is, callers MUST NOT immediately try to write to
  /// RLS-protected tables — there is no `auth.uid()` until the user confirms.
  Future<EmailSignUpResult> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    _assertStrongPassword(password);

    final response = await _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
    );

    if (response.user == null) {
      throw AuthException('Sign up failed. Please try again.');
    }

    // If Supabase project requires email confirmation, signUp succeeds but
    // session is null until the user clicks the confirmation link.
    final needsConfirmation = response.session == null;

    return EmailSignUpResult(
      userId: response.user!.id,
      needsEmailConfirmation: needsConfirmation,
    );
  }

  /// Sign in with email and password.
  ///
  /// Phase 4 Iter 9 AS-02: wraps Supabase errors and surfaces a single
  /// generic message so the UI cannot be used to enumerate which emails
  /// are registered (Supabase's own error text varies between
  /// 'Invalid login credentials' and 'Email not confirmed' — the second
  /// confirms account existence).
  /// Returns the user ID on success.
  Future<String> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (response.user == null) {
        throw AuthException('Invalid email or password.');
      }
      return response.user!.id;
    } on AuthException catch (e) {
      // Preserve "email not confirmed" UX (the user genuinely needs to act
      // on it) but collapse all other failure modes to a single message.
      final raw = e.message.toLowerCase();
      if (raw.contains('not confirmed') ||
          raw.contains('email_not_confirmed')) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint('signInWithEmail failed: ${e.message}');
      }
      throw AuthException('Invalid email or password.');
    }
  }

  /// Re-authenticate the currently signed-in user with their password.
  /// Used as a defense-in-depth check before sensitive account changes
  /// (email/password update). Throws on failure.
  ///
  /// Phase 4 Iter 9 AS-03 note: a successful `signInWithPassword` here
  /// silently rotates the access/refresh-token pair. If the subsequent
  /// sensitive update (e.g. `updateEmail`) fails, the user keeps the new
  /// session anyway — this is acceptable (they already proved identity)
  /// but means a retry of the same flow will not need to re-prompt.
  Future<void> reauthenticateWithPassword({
    required String currentPassword,
  }) async {
    final email = currentUserEmail;
    if (email == null || email.isEmpty) {
      throw AuthException(
        'Cannot verify identity: no email on the current account.',
      );
    }
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    if (response.user == null) {
      throw AuthException('Current password is incorrect.');
    }
  }

  /// Send OTP to phone number for login.
  ///
  /// [shouldCreateUser] is intentionally **required** (no default). Pass
  /// `false` for pure login flows, `true` only when the screen is explicitly
  /// a passwordless signup/login. A per-(intent, phone) cooldown is enforced.
  Future<void> sendPhoneOtp({
    required String phone,
    required bool shouldCreateUser,
  }) async {
    final normalized = AuthFormUtils.normalizeIndianPhone(phone);
    _enforceOtpCooldown('login', normalized);
    await _client.auth.signInWithOtp(
      phone: normalized,
      shouldCreateUser: shouldCreateUser,
    );
    _markOtpSent('login', normalized);
  }

  /// Verify phone OTP.
  /// Phase 4 Iter 9 AS-09: trim the token — users frequently paste OTPs
  /// with trailing whitespace from SMS apps.
  Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      type: OtpType.sms,
      phone: AuthFormUtils.normalizeIndianPhone(phone),
      token: token.trim(),
    );
  }

  /// Returns true on the platforms where Google OAuth is currently
  /// configured for this app. Update this list when you add iOS/desktop
  /// OAuth client IDs and verify the redirect URIs.
  bool get isGoogleSignInAvailable {
    if (kIsWeb) return true;
    try {
      // Phase Auth-Triage Iter 2 (AUTH-04): iOS now supported. iOS
      // Info.plist registers the `com.fieldpass.business` URL scheme under
      // CFBundleURLTypes so the OAuth deep-link reopens the app, and
      // supabase_flutter handles the PKCE code exchange via its built-in
      // app_links listener.
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Start Google OAuth sign-in flow.
  ///
  /// **Returns true only when the external browser was launched
  /// successfully — NOT when the user has finished authenticating.**
  /// (Phase 4 Iter 9 AS-04.) The actual sign-in completes asynchronously
  /// when the OAuth redirect lands back in the app via the deep-link
  /// handler; callers should observe [authStateChanges] for the real
  /// `signedIn` event.
  ///
  /// Throws [AuthException] on platforms where OAuth is not yet configured
  /// (iOS / macOS / Linux / Windows) so the failure is loud, not silent.
  Future<bool> signInWithGoogle() async {
    if (!isGoogleSignInAvailable) {
      throw AuthException(
        'Google sign-in is not available on this platform yet.',
      );
    }
    String redirectTo;
    if (kIsWeb) {
      redirectTo = Uri.base.origin;
    } else if (Platform.isIOS) {
      redirectTo = AuthConfig.iosOAuthRedirect;
    } else {
      redirectTo = AuthConfig.androidOAuthRedirect;
    }

    return await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      queryParams: {
        'prompt': 'select_account', // Always show account picker
      },
    );
  }

  /// Send OTP for linking/updating current user's phone.
  /// Phase 4 Iter 9 AS-06: scoped under the 'change' intent so it does
  /// not share a cooldown bucket with the 'login' OTP for the same phone.
  Future<void> sendPhoneChangeOtp({required String phone}) async {
    final normalized = AuthFormUtils.normalizeIndianPhone(phone);
    _enforceOtpCooldown('change', normalized);
    await _client.auth.updateUser(
      UserAttributes(phone: normalized),
    );
    _markOtpSent('change', normalized);
  }

  /// Verify OTP for phone change flow.
  ///
  /// NOTE: callers are responsible for syncing the new phone into the
  /// `owners` / `players` table after this returns (Supabase Auth has
  /// updated, our app DB has not).
  /// Phase 4 Iter 9 AS-09: trim the token.
  Future<AuthResponse> verifyPhoneChangeOtp({
    required String phone,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      type: OtpType.phoneChange,
      phone: AuthFormUtils.normalizeIndianPhone(phone),
      token: token.trim(),
    );
  }

  /// Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Permanently delete the currently authenticated user's account.
  ///
  /// Calls the `public.delete_my_account()` SECURITY DEFINER RPC which
  /// removes the caller's `auth.users` row. All app-side data (owners,
  /// turfs, slots, bookings, pending_auth_signups) cascades automatically.
  /// After the RPC returns, the local session is signed out so the app
  /// transitions to the unauthenticated state.
  ///
  /// Required for Google Play compliance (in-app account deletion).
  Future<void> deleteAccount() async {
    await _client.rpc('delete_my_account');
    // The auth.users row is gone; clear local session storage too.
    try {
      await _client.auth.signOut();
    } catch (e) {
      // signOut typically throws because the server-side session is
      // already invalid (the row we deleted owned it). Local storage
      // clear has already happened inside the SDK. Phase 4 Iter 9 AS-05:
      // surface in debug builds so a genuine network failure isn't hidden.
      if (kDebugMode) {
        debugPrint('deleteAccount: signOut after RPC threw: $e');
      }
    }
  }

  /// Send password reset email.
  /// Phase 4 Iter 9 AS-08: explicit `redirectTo` so the deep-link handler
  /// catches the recovery token regardless of the Supabase project's
  /// default Site URL.
  Future<void> sendPasswordResetEmail(String email) async {
    await _client.auth.resetPasswordForEmail(
      email.trim().toLowerCase(),
      redirectTo: AuthConfig.passwordResetRedirect,
    );
  }

  /// Refresh session
  Future<void> refreshSession() async {
    await _client.auth.refreshSession();
  }

  /// Update user email. Requires the user's [currentPassword] for re-auth
  /// to defend against session-hijack account takeover.
  Future<void> updateEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    await reauthenticateWithPassword(currentPassword: currentPassword);
    await _client.auth.updateUser(
      UserAttributes(email: newEmail.trim().toLowerCase()),
    );
  }

  /// Update user password. Requires the user's [currentPassword] for re-auth.
  /// Also enforces password strength here as defense-in-depth.
  Future<void> updatePassword({
    required String newPassword,
    required String currentPassword,
  }) async {
    _assertStrongPassword(newPassword);
    await reauthenticateWithPassword(currentPassword: currentPassword);
    await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  /// Update password WITHOUT re-authentication.
  ///
  /// Intended ONLY for flows where identity has already been proven via
  /// another channel (e.g. forgot-password OTP verification, or the
  /// "set password for Google user" flow which is OTP-gated).
  /// Callers MUST ensure such verification just happened. Still enforces
  /// password strength.
  Future<void> updatePasswordAfterReauth({
    required String newPassword,
  }) async {
    _assertStrongPassword(newPassword);
    await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  // (currentUserEmail / currentUserPhone moved to the top of the class
  //  alongside the other current-user getters — Phase 4 Iter 9 AS-11.)
}
