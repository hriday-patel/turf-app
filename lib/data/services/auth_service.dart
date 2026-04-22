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
/// Handles all Supabase Auth operations
class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Per-phone client-side cooldown (mitigates SMS-bomb abuse via the UI).
  /// Keyed by normalized phone, value is the last request timestamp.
  static final Map<String, DateTime> _lastOtpRequestAt = {};

  // Current user getters
  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;
  bool get isLoggedIn => _client.auth.currentUser != null;
  Session? get currentSession => _client.auth.currentSession;

  // Auth state stream
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Throws an [AuthException] when the same phone hit the OTP endpoint
  /// less than [AuthConfig.otpResendCooldownSeconds] ago. Local-only
  /// throttle — Supabase still applies its own server-side rate limit.
  void _enforceOtpCooldown(String phone) {
    final last = _lastOtpRequestAt[phone];
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

  void _markOtpSent(String phone) {
    _lastOtpRequestAt[phone] = DateTime.now();
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
    if (!AuthFormUtils.isStrongPassword(password)) {
      throw AuthException(
        'Password must be at least 8 characters and include upper, lower, '
        'number, and special character.',
      );
    }

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

  /// Sign in with email and password
  /// Returns the user ID on success
  Future<String> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );

    if (response.user == null) {
      throw AuthException('Invalid email or password.');
    }

    return response.user!.id;
  }

  /// Re-authenticate the currently signed-in user with their password.
  /// Used as a defense-in-depth check before sensitive account changes
  /// (email/password update). Throws on failure.
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
  /// a passwordless signup/login. A per-phone cooldown is enforced.
  Future<void> sendPhoneOtp({
    required String phone,
    required bool shouldCreateUser,
  }) async {
    final normalized = AuthFormUtils.normalizeIndianPhone(phone);
    _enforceOtpCooldown(normalized);
    await _client.auth.signInWithOtp(
      phone: normalized,
      shouldCreateUser: shouldCreateUser,
    );
    _markOtpSent(normalized);
  }

  /// Verify phone OTP
  Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      type: OtpType.sms,
      phone: AuthFormUtils.normalizeIndianPhone(phone),
      token: token,
    );
  }

  /// Returns true on the platforms where Google OAuth is currently
  /// configured for this app. Update this list when you add iOS/desktop
  /// OAuth client IDs and verify the redirect URIs.
  bool get isGoogleSignInAvailable {
    if (kIsWeb) return true;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Start Google OAuth sign-in flow.
  ///
  /// Returns true when the external browser is launched successfully.
  /// Throws [AuthException] on platforms where OAuth is not yet configured
  /// (iOS / macOS / Linux / Windows) so the failure is loud, not silent.
  Future<bool> signInWithGoogle() async {
    if (!isGoogleSignInAvailable) {
      throw AuthException(
        'Google sign-in is not available on this platform yet.',
      );
    }
    final redirectTo =
        kIsWeb ? Uri.base.origin : AuthConfig.androidOAuthRedirect;

    return await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      queryParams: {
        'prompt': 'select_account', // Always show account picker
      },
    );
  }

  /// Send OTP for linking/updating current user's phone.
  Future<void> sendPhoneChangeOtp({required String phone}) async {
    final normalized = AuthFormUtils.normalizeIndianPhone(phone);
    _enforceOtpCooldown(normalized);
    await _client.auth.updateUser(
      UserAttributes(phone: normalized),
    );
    _markOtpSent(normalized);
  }

  /// Verify OTP for phone change flow.
  ///
  /// NOTE: callers are responsible for syncing the new phone into the
  /// `owners` / `players` table after this returns (Supabase Auth has
  /// updated, our app DB has not).
  Future<AuthResponse> verifyPhoneChangeOtp({
    required String phone,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      type: OtpType.phoneChange,
      phone: AuthFormUtils.normalizeIndianPhone(phone),
      token: token,
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
    } catch (_) {
      // signOut may throw because the server-side session is already
      // invalid. Local storage clear has already happened inside the SDK.
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim().toLowerCase());
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
    if (!AuthFormUtils.isStrongPassword(newPassword)) {
      throw AuthException(
        'Password must be at least 8 characters and include upper, lower, '
        'number, and special character.',
      );
    }
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
    if (!AuthFormUtils.isStrongPassword(newPassword)) {
      throw AuthException(
        'Password must be at least 8 characters and include upper, lower, '
        'number, and special character.',
      );
    }
    await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  /// Get current user email
  String? get currentUserEmail => _client.auth.currentUser?.email;

  /// Get current user phone
  String? get currentUserPhone => _client.auth.currentUser?.phone;
}
