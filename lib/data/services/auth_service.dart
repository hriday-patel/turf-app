import 'package:supabase_flutter/supabase_flutter.dart';

/// Authentication Service
/// Handles all Supabase Auth operations
class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  // Current user getters
  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;
  bool get isLoggedIn => _client.auth.currentUser != null;
  Session? get currentSession => _client.auth.currentSession;

  // Auth state stream
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Sign up with email and password
  /// Returns the user ID on success
  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
    );

    if (response.user == null) {
      throw 'Sign up failed. Please try again.';
    }

    return response.user!.id;
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
      throw 'Invalid email or password.';
    }

    return response.user!.id;
  }

  /// Send OTP to phone number for login
  Future<void> sendPhoneOtp({required String phone}) async {
    await _client.auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: false,
    );
  }

  /// Verify phone OTP
  Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      type: OtpType.sms,
      phone: phone,
      token: token,
    );
  }

  /// Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  /// Refresh session
  Future<void> refreshSession() async {
    await _client.auth.refreshSession();
  }
}
