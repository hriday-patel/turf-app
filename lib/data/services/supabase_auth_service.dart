import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Supabase Authentication Service
class SupabaseAuthService {
  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  supa.User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;
  bool get isLoggedIn => _client.auth.currentUser != null;
  Stream<supa.AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw 'Sign up failed. Please try again.';
    }
    return user.id;
  }

  Future<String> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw 'Invalid email or password.';
    }
    return user.id;
  }

  Future<void> sendPhoneOtp({
    required String phone,
  }) async {
    await _client.auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: false,
    );
  }

  Future<supa.AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      type: supa.OtpType.sms,
      phone: phone,
      token: token,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  Future<bool> isEmailRegistered(String email) async {
    try {
      final response = await _client
          .from('owners')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      return response != null;
    } catch (_) {
      return false;
    }
  }
}
