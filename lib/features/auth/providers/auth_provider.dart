import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/database_service.dart';
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
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  AuthStatus _authState = AuthStatus.initial;
  OwnerModel? _currentOwner;
  PlayerModel? _currentPlayer;
  String? _errorMessage;
  bool _isLoading = false;
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

  StreamSubscription<AuthState>? _authSubscription;

  AuthProvider() {
    _init();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Initialize auth state listener
  void _init() {
    _authSubscription =
        _authService.authStateChanges.listen((AuthState state) async {
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
    try {
      _authState = AuthStatus.loading;
      notifyListeners();

      // Try to load owner profile
      final ownerData = await _dbService.getOwner(uid);
      if (ownerData != null) {
        _currentOwner = OwnerModel.fromMap(ownerData);
        _currentPlayer = null;
        _authState = AuthStatus.authenticated;
        notifyListeners();
        return;
      }

      // Try to load player profile
      final playerData = await _dbService.getPlayer(uid);
      if (playerData != null) {
        _currentPlayer = PlayerModel.fromMap(playerData);
        _currentOwner = null;
        _authState = AuthStatus.authenticated;
        notifyListeners();
        return;
      }

      // No profile found - user is authenticated but not registered
      _authState = AuthStatus.unauthenticated;
      _currentOwner = null;
      _currentPlayer = null;
      notifyListeners();
    } catch (e) {
      _authState = AuthStatus.error;
      _errorMessage = 'Failed to load profile: ${e.toString()}';
      notifyListeners();
    }
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

  /// Validate password strength
  bool _isStrongPassword(String password) {
    if (password.length < 8) return false;
    if (!password.contains(RegExp(r'[A-Z]'))) return false;
    if (!password.contains(RegExp(r'[a-z]'))) return false;
    if (!password.contains(RegExp(r'[0-9]'))) return false;
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) return false;
    return true;
  }

  /// Sign up new user (Owner or Player)
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

      // Validate password
      if (!_isStrongPassword(password)) {
        throw 'Password must be at least 8 characters with uppercase, lowercase, number, and special character.';
      }

      // Create auth user first
      final uid = await _authService.signUpWithEmail(
        email: email,
        password: password,
      );

      // Create profile in database using RPC
      // If profile creation fails, we must clean up the orphaned auth user
      try {
        if (role == UserRole.owner) {
          await _dbService.createOwnerProfile(
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
            createdAt: DateTime.now(),
          );
          _currentPlayer = null;
        } else {
          await _dbService.createPlayerProfile(
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
            createdAt: DateTime.now(),
            favoriteTurfs: [],
          );
          _currentOwner = null;
        }
      } catch (profileError) {
        // Profile creation failed — sign out the orphaned auth user
        try {
          await _authService.signOut();
        } catch (_) {}
        rethrow;
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

      if (_currentOwner == null && _currentPlayer == null) {
        await signOut();
        throw 'Account not found. Please sign up.';
      }

      return true;
    } catch (e) {
      _authState = AuthStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Send OTP to phone number (for login only)
  Future<bool> sendPhoneOtp(String phone) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _phoneNumber = phone;
      notifyListeners();

      // Pre-check if owner exists (best-effort; RPC may not be deployed)
      // If the check fails we still try to send OTP
      try {
        final exists = await _dbService.ownerExists(phone: phone);
        if (!exists) {
          _isLoading = false;
          _errorMessage = 'Phone number not registered. Please sign up.';
          notifyListeners();
          return false;
        }
      } catch (e) {
        debugPrint('ownerExists check failed, proceeding with OTP: $e');
      }

      await _authService.sendPhoneOtp(phone: phone);

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

  /// Verify OTP and sign in
  Future<bool> verifyOTP(String smsCode) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      if (_phoneNumber == null || _phoneNumber!.isEmpty) {
        throw 'Phone number is missing';
      }

      final response = await _authService.verifyPhoneOtp(
        phone: _phoneNumber!,
        token: smsCode,
      );

      final uid = response.user?.id;
      if (uid == null) {
        throw 'Authentication failed.';
      }

      await _loadUserProfile(uid);

      if (_currentOwner == null) {
        await signOut();
        throw 'Phone number not registered. Please sign up.';
      }

      // Update auth methods
      await _dbService.updateOwner(uid, {
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

  /// Sign out
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      _currentOwner = null;
      _currentPlayer = null;
      _phoneNumber = null;
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

  /// Verify phone - alias for sendPhoneOtp (for UI compatibility)
  Future<bool> verifyPhone(String phone) async {
    return await sendPhoneOtp(phone);
  }

  /// Update email address
  Future<bool> updateEmail(String newEmail) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _authService.updateEmail(newEmail);

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

  /// Finalize email change only after verification completes.
  Future<bool> confirmEmailUpdate(String expectedEmail) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final normalizedEmail = expectedEmail.trim().toLowerCase();

      await _authService.refreshSession();
      final currentAuthEmail =
          _authService.currentUserEmail?.trim().toLowerCase();
      if (currentAuthEmail != normalizedEmail) {
        _isLoading = false;
        _errorMessage =
            'Verification pending. Please verify your new email and try again.';
        notifyListeners();
        return false;
      }

      if (_currentOwner != null) {
        await _dbService.updateOwner(_currentOwner!.uid, {
          'email': normalizedEmail,
        });
        await _loadUserProfile(_currentOwner!.uid);
      }

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

  /// Update password
  Future<bool> updatePassword(String newPassword) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _authService.updatePassword(newPassword);

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

  /// Get current email
  String? get currentEmail => _authService.currentUserEmail;

  /// Get current phone
  String? get currentPhone => _authService.currentUserPhone;

  /// Complete profile for player after phone OTP verification
  Future<bool> completeProfile({
    required String name,
    required String email,
    required UserRole role,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final uid = _authService.currentUserId;
      if (uid == null) {
        throw 'Not authenticated';
      }

      if (role == UserRole.player) {
        await _dbService.createPlayerProfile(
          id: uid,
          name: name,
          email: email,
          phone: _phoneNumber ?? '',
        );

        _currentPlayer = PlayerModel(
          uid: uid,
          name: name,
          email: email,
          phone: _phoneNumber ?? '',
          role: UserRole.player,
          createdAt: DateTime.now(),
          favoriteTurfs: [],
        );
      } else {
        await _dbService.createOwnerProfile(
          id: uid,
          name: name,
          email: email,
          phone: _phoneNumber ?? '',
        );

        _currentOwner = OwnerModel(
          uid: uid,
          name: name,
          email: email,
          phone: _phoneNumber ?? '',
          role: UserRole.owner,
          isVerified: false,
          createdAt: DateTime.now(),
        );
      }

      _authState = AuthStatus.authenticated;
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
}
