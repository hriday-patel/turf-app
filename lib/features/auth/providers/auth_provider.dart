import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../../data/services/supabase_auth_service.dart';
import '../../../data/services/supabase_service.dart';
import '../../../data/services/supabase_backend_service.dart';
import '../../../data/models/owner_model.dart';
import '../../../data/models/player_model.dart';
import '../../../core/constants/enums.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

/// Authentication Provider
/// Manages user authentication state and operations
class AuthProvider extends ChangeNotifier {
  final SupabaseAuthService _authService = SupabaseAuthService();
  final SupabaseService _supabaseService = SupabaseService();
  final SupabaseBackendService _backendService = SupabaseBackendService();

  AuthStatus _authState = AuthStatus.initial;
  OwnerModel? _currentOwner;
  PlayerModel? _currentPlayer;
  String? _errorMessage;
  bool _isProfileLoading = false;
  bool _isLoading = false;

  // Phone Auth State
  String? _phoneNumber;

  // Getters
  AuthStatus get authState => _authState;
  OwnerModel? get currentOwner => _currentOwner;
  PlayerModel? get currentPlayer => _currentPlayer;
  String? get errorMessage => _errorMessage;
  String? get phoneNumber => _phoneNumber;
  bool get isAuthenticated => _authState == AuthStatus.authenticated;
  bool get isLoading => _authState == AuthStatus.loading || _isLoading;
  String? get currentUserId => _authService.currentUserId;

  UserRole? get currentUserRole {
    if (_currentOwner != null) return UserRole.owner;
    if (_currentPlayer != null) return UserRole.player;
    return null;
  }

  AuthProvider() {
    _init();
  }

  bool _isStrongPassword(String password) {
    final hasMinLength = password.length >= 8;
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    return hasMinLength && hasUpper && hasLower && hasNumber && hasSpecial;
  }

  /// Initialize auth state listener
  void _init() {
    _authService.authStateChanges.listen((supa.AuthState state) async {
      final user = state.session?.user;
      if (user != null) {
        await _loadUserProfile(user.id);
      } else {
        _authState = AuthStatus.unauthenticated;
        _currentOwner = null;
        _currentPlayer = null;
        notifyListeners();
      }
    });
  }

  /// Load user profile (Owner or Player)
  Future<void> _loadUserProfile(String uid) async {
    if (_isProfileLoading) return;

    try {
      _isProfileLoading = true;
      _authState = AuthStatus.loading;
      notifyListeners();

      final ownerData = await _supabaseService.getOwner(uid);
      if (ownerData != null) {
        _currentOwner = OwnerModel.fromMap(ownerData);
        _currentPlayer = null;
        _authState = AuthStatus.authenticated;
      } else {
        final playerData = await supa.Supabase.instance.client
            .from('players')
            .select('*')
            .eq('id', uid)
            .maybeSingle();

        if (playerData != null) {
          _currentPlayer = PlayerModel.fromMap(playerData);
          _currentOwner = null;
          _authState = AuthStatus.authenticated;
        } else {
          _authState = AuthStatus.unauthenticated;
          _currentOwner = null;
          _currentPlayer = null;
        }
      }
    } catch (e) {
      _authState = AuthStatus.error;
      _errorMessage = 'Failed to load profile: ${e.toString()}';
    } finally {
      _isProfileLoading = false;
    }
    notifyListeners();
  }

  /// Check initial auth state (for splash screen)
  Future<bool> checkAuthState() async {
    try {
      _authState = AuthStatus.loading;
      notifyListeners();

      final user = _authService.currentUser;

      if (user != null) {
        await _loadUserProfile(user.id);
        return _authState == AuthStatus.authenticated;
      } else {
        _authState = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _authState = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Sign up new user
  Future<bool> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
  }) async {
    try {
      _authState = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      if (!_isStrongPassword(password)) {
        throw 'Password must be at least 8 characters and include upper, lower, number, and special character.';
      }

      if (role == UserRole.owner) {
        final existsByEmail = await _backendService.ownerExists(
          email: email.trim().toLowerCase(),
        );
        if (existsByEmail) {
          throw 'Email already registered. Please sign in instead.';
        }

        final existsByPhone = await _backendService.ownerExists(
          phone: phone.trim(),
        );
        if (existsByPhone) {
          throw 'Phone already registered. Please sign in instead.';
        }
      }

      final uid = await _authService.signUpWithEmail(
        email: email,
        password: password,
      );

      final now = DateTime.now();
      if (role == UserRole.owner) {
        await _backendService.createOwnerProfile(
          id: uid,
          name: name,
          email: email,
          phone: phone,
        );
        _currentOwner = OwnerModel(
          uid: uid,
          name: name,
          email: email,
          phone: phone,
          role: UserRole.owner,
          isVerified: false,
          createdAt: now,
        );
        _currentPlayer = null;
      } else {
        await _backendService.createPlayerProfile(
          id: uid,
          name: name,
          email: email,
          phone: phone,
        );
        _currentPlayer = PlayerModel(
          uid: uid,
          name: name,
          email: email,
          phone: phone,
          role: UserRole.player,
          createdAt: now,
          favoriteTurfs: [],
        );
        _currentOwner = null;
      }

      _authState = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _authState = AuthStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Verify phone number to send OTP (LOGIN ONLY)
  Future<bool> verifyPhone(String phone) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _phoneNumber = phone;
      notifyListeners();

      final exists = await _backendService.ownerExists(phone: phone);
      if (!exists) {
        _isLoading = false;
        _errorMessage = 'Phone number not registered. Please sign up.';
        notifyListeners();
        return false;
      }

      await _authService.sendPhoneOtp(phone: phone);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Verify OTP and sign in
  Future<bool> verifyOTP(String smsCode) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final phone = _phoneNumber ?? '';
      if (phone.isEmpty) throw 'Phone number is missing';

      final response = await _authService.verifyPhoneOtp(
        phone: phone,
        token: smsCode,
      );

      final uid = response.user?.id;
      if (uid == null) throw 'Authentication failed.';

      await _loadUserProfile(uid);

      if (_currentOwner == null) {
        await signOut();
        throw 'Phone number not registered. Please sign up.';
      }

      await _supabaseService.updateOwner(uid, {
        'auth_methods': ['email', 'otp'],
      });

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Complete profile setup
  Future<bool> completeProfile({
    required String name,
    required String email,
    required UserRole role,
  }) async {
    try {
      if (currentUserId == null) throw 'User not authenticated';

      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final phone = _phoneNumber ?? '';

      if (role == UserRole.owner) {
        await supa.Supabase.instance.client.from('owners').upsert({
          'id': currentUserId!,
          'name': name,
          'email': email,
          'phone': phone,
          'role': 'OWNER',
          'is_verified': false,
          'auth_methods': ['otp'],
          'updated_at': DateTime.now().toIso8601String(),
        });
      } else {
        await supa.Supabase.instance.client.from('players').upsert({
          'id': currentUserId!,
          'name': name,
          'email': email,
          'phone': phone,
          'role': 'PLAYER',
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      await _loadUserProfile(currentUserId!);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Sign in existing user (Email/Password)
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    try {
      _authState = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      final uid = await _authService.signInWithEmail(
        email: email,
        password: password,
      );

      await _loadUserProfile(uid);

      if (_currentOwner == null) {
        await signOut();
        throw 'Access denied. Not an Owner account.';
      }

      return true;
    } catch (e) {
      _authState = AuthStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      _currentOwner = null;
      _currentPlayer = null;
      _authState = AuthStatus.unauthenticated;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to sign out: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Send password reset email
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    if (_authState == AuthStatus.error) {
      _authState = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  /// Refresh user profile
  Future<void> refreshProfile() async {
    if (_authService.currentUserId != null) {
      await _loadUserProfile(_authService.currentUserId!);
    }
  }
}
