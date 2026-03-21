import 'dart:async';
import 'package:flutter/foundation.dart';
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
  bool _isOwnerPhoneVerificationFlow = false;

  // Temporary signup state (deferred account creation until OTP verified)
  String? _tempSignupName;
  String? _tempSignupEmail;
  String? _tempSignupPhone;
  String? _tempSignupUid;
  String _tempSignupMethod = 'email';
  bool _tempSignupHasPassword = true;
  bool _isInDeferredSignupFlow = false;

  // Getters
  AuthStatus get authState => _authState;
  OwnerModel? get currentOwner => _currentOwner;
  PlayerModel? get currentPlayer => _currentPlayer;
  String? get errorMessage => _errorMessage;
  String? get phoneNumber => _phoneNumber;
  bool get isAuthenticated => _authState == AuthStatus.authenticated;
  bool get isLoading => _authState == AuthStatus.loading || _isLoading;
  String? get currentUserId => _authService.currentUserId;
  bool get isInDeferredSignupFlow => _isInDeferredSignupFlow;
  String get deferredSignupPhone => _tempSignupPhone ?? '';
  String get deferredSignupMethod => _tempSignupMethod;
  bool get isOwnerPhoneVerified {
    final owner = _currentOwner;
    if (owner == null) return false;
    final phone = owner.phone.trim();
    return phone.isNotEmpty && !phone.startsWith('pending_');
  }

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

      // During deferred signup, keep session authenticated even before profile exists.
      if (_isInDeferredSignupFlow && _tempSignupUid == uid) {
        _authState = AuthStatus.authenticated;
        _currentOwner = null;
        _currentPlayer = null;
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

  String _friendlyAuthError(
    Object error, {
    required String fallback,
  }) {
    if (error is AuthApiException) {
      final mapped = _mapAuthApiCode(error.code);
      if (mapped != null) return mapped;
      return _mapAuthMessage(error.message, fallback: fallback);
    }

    if (error is AuthException) {
      return _mapAuthMessage(error.message, fallback: fallback);
    }

    if (error is String) {
      return _mapAuthMessage(error, fallback: fallback);
    }

    return _mapAuthMessage(error.toString(), fallback: fallback);
  }

  String? _mapAuthApiCode(String? code) {
    final normalized = code?.trim().toLowerCase();
    switch (normalized) {
      case 'invalid_credentials':
        return 'Invalid email or password.';
      case 'user_already_exists':
        return 'Account already exists. Please log in instead.';
      case 'email_not_confirmed':
        return 'Please verify your email before logging in.';
      case 'weak_password':
        return 'Password is too weak. Use a stronger password.';
      case 'email_address_invalid':
        return 'Please enter a valid email address.';
      case 'otp_expired':
        return 'OTP expired. Please request a new OTP.';
      case 'otp_disabled':
        return 'OTP login is currently unavailable. Try again later.';
      case 'sms_send_failed':
      case 'sms_provider_disabled':
        return 'Phone OTP is not configured yet. Please use email login for now.';
      case 'too_many_requests':
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
      case 'over_sms_send_rate_limit':
        return 'Too many attempts. Please wait and try again.';
      default:
        return null;
    }
  }

  String _mapAuthMessage(
    String? rawMessage, {
    required String fallback,
  }) {
    final message = (rawMessage ?? '').trim();
    final lower = message.toLowerCase();

    if (message == 'Account not found. Please sign up.' ||
        message == 'Phone number not registered. Please sign up.' ||
        message ==
            'Password must be at least 8 characters with uppercase, lowercase, number, and special character.' ||
        message == 'Please verify your new email and try again.') {
      return message;
    }

    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid credentials')) {
      return 'Invalid email or password.';
    }

    if (lower.contains('user already registered') ||
        lower.contains('already exists') ||
        lower.contains('already registered')) {
      return 'Account already exists. Please log in instead.';
    }

    if (lower.contains('email not confirmed')) {
      return 'Please verify your email before logging in.';
    }

    if (lower.contains('password')) {
      return 'Password is invalid. Please try again.';
    }

    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('timeout')) {
      return 'Network issue. Please check your connection and try again.';
    }

    if (lower.contains('provider') && lower.contains('not enabled')) {
      return 'Google login is not configured yet. Please contact support.';
    }

    if (lower.contains('sms') &&
        (lower.contains('not configured') || lower.contains('provider'))) {
      return 'Phone OTP is not configured yet. Please use email login for now.';
    }

    if (lower.contains('redirect') && lower.contains('uri')) {
      return 'Google login redirect is not configured correctly.';
    }

    if (kDebugMode && message.isNotEmpty) {
      debugPrint('Auth error: $message');
    }

    return fallback;
  }

  /// Sign up new user (Owner or Player)
  /// For Owners: Creates auth account but defers DB profile creation until OTP verified
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

      // For Owners: Defer database profile creation until OTP verified
      if (role == UserRole.owner) {
        _tempSignupName = name;
        _tempSignupEmail = email;
        _tempSignupPhone = phone;
        _tempSignupUid = uid;
        _tempSignupMethod = 'email';
        _tempSignupHasPassword = true;
        _isInDeferredSignupFlow = true;

        _authState = AuthStatus.authenticated;
        notifyListeners();
        return true;
      }

      // For Players: Create profile immediately
      try {
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
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not create account. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  List<String> _mergeAuthMethods({
    required List<String> existing,
    required String add,
  }) {
    final merged = <String>{
      ...existing.where((m) => m.trim().isNotEmpty),
      add,
    };
    return merged.toList()..sort();
  }

  Future<String?> _waitForCurrentUserId({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final startedAt = DateTime.now();
    while (DateTime.now().difference(startedAt) < timeout) {
      final uid = _authService.currentUserId;
      if (uid != null && uid.isNotEmpty) {
        return uid;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  Future<void> _ensureOwnerAuthMethods(Set<String> requiredMethods) async {
    if (_currentOwner == null) return;
    final owner = _currentOwner!;
    final methods = <String>{...owner.authMethods, ...requiredMethods};
    if (methods.length == owner.authMethods.length) return;

    await _dbService.updateOwner(owner.uid, {
      'auth_methods': methods.toList()..sort(),
    });
    await _loadUserProfile(owner.uid);
  }

  String _normalizedEmail(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  String _resolveOwnerName({String? emailFallback}) {
    final fromOwner = _currentOwner?.name.trim();
    if (fromOwner != null && fromOwner.isNotEmpty) {
      return fromOwner;
    }

    final fromTemp = _tempSignupName?.trim();
    if (fromTemp != null && fromTemp.isNotEmpty) {
      return fromTemp;
    }

    final metadata = _authService.currentUser?.userMetadata;
    final fromMeta =
        ((metadata?['full_name'] ?? metadata?['name']) as String?)?.trim();
    if (fromMeta != null && fromMeta.isNotEmpty) {
      return fromMeta;
    }

    final normalizedEmail = _normalizedEmail(
      emailFallback ?? _tempSignupEmail ?? _authService.currentUserEmail,
    );
    if (normalizedEmail.contains('@')) {
      final prefix = normalizedEmail.split('@').first.trim();
      if (prefix.isNotEmpty) {
        return prefix;
      }
    }

    return 'Owner';
  }

  Future<bool> _recoverMissingOwnerProfile({
    required String uid,
    String? preferredPhone,
    bool allowCreate = true,
  }) async {
    try {
      await _loadUserProfile(uid);
      if (_currentOwner != null) {
        return true;
      }

      if (_currentPlayer != null) {
        _errorMessage = 'This account is not an owner account.';
        notifyListeners();
        return false;
      }

      final email =
          _normalizedEmail(_tempSignupEmail ?? _authService.currentUserEmail);
      if (email.isEmpty) {
        _errorMessage = 'Owner email not found. Please complete sign in again.';
        notifyListeners();
        return false;
      }

      final existingByEmail = await _dbService.getOwnerByEmail(email);
      if (existingByEmail != null) {
        final existingId = existingByEmail['id']?.toString();
        if (existingId != uid) {
          _errorMessage =
              'Email is already linked to another owner account. Please use the original login method.';
          notifyListeners();
          return false;
        }

        _currentOwner = OwnerModel.fromMap(existingByEmail);
        _currentPlayer = null;
        _authState = AuthStatus.authenticated;
        notifyListeners();
        return true;
      }

      final resolvedPhone = (preferredPhone ??
              _tempSignupPhone ??
              _phoneNumber ??
              _authService.currentUserPhone ??
              '')
          .trim();

      if (resolvedPhone.isNotEmpty) {
        final existingByPhone = await _dbService.getOwnerByPhone(resolvedPhone);
        if (existingByPhone != null) {
          final existingPhoneOwnerId = existingByPhone['id']?.toString();
          if (existingPhoneOwnerId != uid) {
            _errorMessage =
                'This phone number is already registered with another account.';
            notifyListeners();
            return false;
          }
        }
      }

      if (!allowCreate) {
        _errorMessage = 'Owner profile not found.';
        notifyListeners();
        return false;
      }

      final ownerName = _resolveOwnerName(emailFallback: email);
      final phoneForCreate = resolvedPhone.isEmpty
          ? 'pending_${uid.substring(0, 8)}'
          : resolvedPhone;

      await _dbService.createOwnerProfile(
        id: uid,
        name: ownerName,
        email: email,
        phone: phoneForCreate,
        hasPassword: _tempSignupHasPassword,
      );

      final methods = <String>{
        if (_tempSignupMethod.trim().isNotEmpty) _tempSignupMethod.trim(),
        if (resolvedPhone.isNotEmpty) 'otp',
      };
      if (methods.isNotEmpty) {
        await _dbService.updateOwner(uid, {
          'auth_methods': methods.toList()..sort(),
        });
      }

      await _loadUserProfile(uid);

      if (_currentOwner == null) {
        _errorMessage =
            'Could not load owner profile after saving. Please try again.';
        notifyListeners();
        return false;
      }

      return true;
    } catch (e) {
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not sync owner profile. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> ensureOwnerReadyForDashboard({
    bool allowDeferredSignup = true,
  }) async {
    final uid = _authService.currentUserId;
    if (uid == null || uid.isEmpty) {
      _errorMessage = 'Session expired. Please login again.';
      notifyListeners();
      return false;
    }

    if (_isInDeferredSignupFlow) {
      return allowDeferredSignup;
    }

    final recovered = await _recoverMissingOwnerProfile(
      uid: uid,
      preferredPhone: _phoneNumber,
      allowCreate: true,
    );
    if (!recovered || _currentOwner == null) {
      return false;
    }

    return true;
  }

  /// Owner-only Google OAuth login/signup.
  ///
  /// Missing owner profile auto-enters deferred signup flow.
  Future<bool> signInOwnerWithGoogle({
    required bool allowCreate,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final launched = await _authService.signInWithGoogle();
      if (!launched) {
        throw 'Google login could not be launched.';
      }

      final uid = await _waitForCurrentUserId();
      if (uid == null) {
        throw 'Google sign-in was not completed. Please try again.';
      }

      final email = _authService.currentUserEmail?.trim().toLowerCase();
      if (email == null || email.isEmpty) {
        throw 'Google account email is missing. Please use another account.';
      }

      await _loadUserProfile(uid);

      if (_currentPlayer != null) {
        throw 'This account is not an owner account.';
      }

      if (_currentOwner != null) {
        await _ensureOwnerAuthMethods({'google'});

        final updatedName =
            _authService.currentUser?.userMetadata?['full_name'] as String? ??
                _authService.currentUser?.userMetadata?['name'] as String?;
        if (updatedName != null && updatedName.trim().isNotEmpty) {
          await _dbService.updateOwner(_currentOwner!.uid, {
            'name': updatedName.trim(),
            'email': email,
          });
          await _loadUserProfile(_currentOwner!.uid);
        }

        _isLoading = false;
        notifyListeners();
        return true;
      }

      final ownerByEmail = await _dbService.getOwnerByEmail(email);
      if (ownerByEmail != null) {
        final existingOwnerId = ownerByEmail['id'] as String?;
        if (existingOwnerId == uid) {
          final resolvedName =
              _authService.currentUser?.userMetadata?['full_name'] as String? ??
                  _authService.currentUser?.userMetadata?['name'] as String? ??
                  email.split('@').first;
          await _dbService.updateOwner(uid, {
            'name': resolvedName.trim(),
            'email': email,
          });
          await _loadUserProfile(uid);
          await _ensureOwnerAuthMethods({'google'});
          _isLoading = false;
          notifyListeners();
          return true;
        }

        // Supabase should normally auto-link identities for the same email.
        // If IDs differ, keep session safe and ask user to use existing method.
        throw 'Account already exists with email login. Please log in with email once, then try Google again.';
      }

      if (!allowCreate && kDebugMode) {
        debugPrint('Google login: owner not found, entering deferred signup.');
      }

      // Defer owner profile creation until phone OTP verification succeeds.
      final resolvedName =
          _authService.currentUser?.userMetadata?['full_name'] as String? ??
              _authService.currentUser?.userMetadata?['name'] as String? ??
              email.split('@').first;

      _tempSignupName = resolvedName.trim();
      _tempSignupEmail = email;
      _tempSignupPhone = '';
      _tempSignupUid = uid;
      _tempSignupMethod = 'google';
      _tempSignupHasPassword = false;
      _isInDeferredSignupFlow = true;

      _authState = AuthStatus.authenticated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _authState = AuthStatus.error;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not sign in with Google. Please try again.',
      );
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
        if (_currentPlayer != null) {
          throw 'This account is not an owner account.';
        }
        throw 'Owner account not found. Please sign up.';
      }

      return true;
    } catch (e) {
      _authState = AuthStatus.error;

      final baseMessage = _friendlyAuthError(
        e,
        fallback: 'Could not sign in. Please try again.',
      );

      final normalizedEmail = email.trim().toLowerCase();
      final ownerByEmail = await _dbService.getOwnerByEmail(normalizedEmail);
      final ownerMethods = ownerByEmail?['auth_methods'];
      final authMethods = ownerMethods is List
          ? List<String>.from(ownerMethods.map((m) => m.toString()))
          : const <String>[];

      if (baseMessage == 'Invalid email or password.' &&
          authMethods.contains('google') &&
          !authMethods.contains('email')) {
        _errorMessage =
            'This account uses Google sign-in. Continue with Google, or set a password using Forgot Password.';
      } else {
        _errorMessage = baseMessage;
      }

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

      // Deferred signup also needs OTP while user is authenticated.
      if (_isInDeferredSignupFlow && _authService.currentUserId != null) {
        await _authService.sendPhoneChangeOtp(phone: phone);
        _isOwnerPhoneVerificationFlow = true;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Authenticated owners must verify phone to unlock app access.
      if (_currentOwner != null && _authService.currentUserId != null) {
        await _authService.sendPhoneChangeOtp(phone: phone);
        _isOwnerPhoneVerificationFlow = true;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Login OTP: owner must exist by phone.
      bool ownerExistsByPhone = false;
      try {
        ownerExistsByPhone = await _dbService.ownerExists(phone: phone);
      } catch (e) {
        debugPrint(
            'ownerExists check failed, falling back to table lookup: $e');
      }

      if (!ownerExistsByPhone) {
        final owner = await _dbService.getOwnerByPhone(phone);
        ownerExistsByPhone = owner != null;
      }

      if (!ownerExistsByPhone) {
        _isLoading = false;
        _errorMessage = 'Phone number not registered. Please sign up.';
        notifyListeners();
        return false;
      }

      await _authService.sendPhoneOtp(phone: phone);
      _isOwnerPhoneVerificationFlow = false;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not send OTP. Please try again.',
      );
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

      // Verification flow for logged-in Owner (phone-link gate).
      if (_isOwnerPhoneVerificationFlow) {
        await _authService.verifyPhoneChangeOtp(
          phone: _phoneNumber!,
          token: smsCode,
        );

        if (_isInDeferredSignupFlow) {
          // Store verified phone and complete DB profile creation in dashboard step.
          _tempSignupPhone = _phoneNumber!;
          _isOwnerPhoneVerificationFlow = false;
          _isLoading = false;
          notifyListeners();
          return true;
        }

        final ownerId = _currentOwner?.uid ?? _authService.currentUserId;
        if (ownerId == null || ownerId.isEmpty) {
          throw 'Could not verify owner account.';
        }

        final mergedMethods = _mergeAuthMethods(
          existing: _currentOwner?.authMethods ?? const ['email'],
          add: 'otp',
        );

        await _dbService.updateOwner(ownerId, {
          'phone': _phoneNumber!,
          'auth_methods': mergedMethods,
        });

        await _loadUserProfile(ownerId);

        if (_currentOwner == null) {
          final recovered = await _recoverMissingOwnerProfile(
            uid: ownerId,
            preferredPhone: _phoneNumber,
            allowCreate: true,
          );
          if (!recovered || _currentOwner == null) {
            throw _errorMessage ??
                'Owner profile could not be synced after verification.';
          }
        }

        _isOwnerPhoneVerificationFlow = false;
        _isLoading = false;
        notifyListeners();
        return true;
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
        final recovered = await _recoverMissingOwnerProfile(
          uid: uid,
          preferredPhone: _phoneNumber,
          allowCreate: true,
        );
        if (!recovered || _currentOwner == null) {
          await signOut();
          throw _errorMessage ?? 'Phone number not registered. Please sign up.';
        }
      }

      // Update auth methods
      final mergedMethods = _mergeAuthMethods(
        existing: _currentOwner?.authMethods ?? const ['email'],
        add: 'otp',
      );
      await _dbService.updateOwner(uid, {
        'auth_methods': mergedMethods,
      });

      await _loadUserProfile(uid);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not verify OTP. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Complete deferred signup for Owner after OTP verification
  /// This creates the database profile that was deferred until OTP was verified
  Future<bool> completeDeferredOwnerSignup() async {
    try {
      if (!_isInDeferredSignupFlow) {
        throw 'Not in deferred signup flow.';
      }

      if (_tempSignupUid == null ||
          _tempSignupName == null ||
          _tempSignupEmail == null ||
          _tempSignupPhone == null) {
        throw 'Signup information missing.';
      }

      _isLoading = true;
      notifyListeners();

      // Create owner profile in database
      await _dbService.createOwnerProfile(
        id: _tempSignupUid!,
        name: _tempSignupName!,
        email: _tempSignupEmail!,
        phone: _tempSignupPhone!,
        hasPassword: _tempSignupHasPassword,
      );

      final mergedMethods = _mergeAuthMethods(
        existing: [_tempSignupMethod],
        add: 'otp',
      );
      await _dbService.updateOwner(_tempSignupUid!, {
        'auth_methods': mergedMethods,
      });

      // Load the created profile
      await _loadUserProfile(_tempSignupUid!);

      if (_currentOwner == null) {
        throw 'Could not load owner profile after signup completion.';
      }

      // Clear temporary state
      _tempSignupName = null;
      _tempSignupEmail = null;
      _tempSignupPhone = null;
      _tempSignupUid = null;
      _tempSignupMethod = 'email';
      _tempSignupHasPassword = true;
      _isInDeferredSignupFlow = false;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not complete signup. Please try again.',
      );
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
      _isOwnerPhoneVerificationFlow = false;
      // Clear deferred signup state
      _tempSignupName = null;
      _tempSignupEmail = null;
      _tempSignupPhone = null;
      _tempSignupUid = null;
      _tempSignupMethod = 'email';
      _tempSignupHasPassword = true;
      _isInDeferredSignupFlow = false;
      _authState = AuthStatus.unauthenticated;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to sign out: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Cancel deferred signup and sign out.
  /// This is called when user goes back from phone verification modal.
  /// The Supabase auth user will be signed out (account deletion requires admin SDK).
  Future<void> cancelDeferredSignup() async {
    try {
      // Clear deferred signup state first
      _tempSignupName = null;
      _tempSignupEmail = null;
      _tempSignupPhone = null;
      _tempSignupUid = null;
      _tempSignupMethod = 'email';
      _tempSignupHasPassword = true;
      _isInDeferredSignupFlow = false;
      _isOwnerPhoneVerificationFlow = false;
      _phoneNumber = null;

      // Sign out the Supabase auth user
      await _authService.signOut();

      _currentOwner = null;
      _currentPlayer = null;
      _authState = AuthStatus.unauthenticated;
      notifyListeners();
    } catch (e) {
      // Even if signout fails, clear all local state
      _currentOwner = null;
      _currentPlayer = null;
      _authState = AuthStatus.unauthenticated;
      _errorMessage = 'Failed to cancel signup: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Send password reset email
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
      return true;
    } catch (e) {
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not send password reset email. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  // State for forgot password OTP flow
  String? _forgotPasswordEmail;
  String? _forgotPasswordPhone;
  bool _isForgotPasswordOtpSent = false;
  bool _isForgotPasswordOtpVerified = false;

  String? get forgotPasswordEmail => _forgotPasswordEmail;
  String? get forgotPasswordPhone => _forgotPasswordPhone;
  bool get isForgotPasswordOtpSent => _isForgotPasswordOtpSent;
  bool get isForgotPasswordOtpVerified => _isForgotPasswordOtpVerified;

  /// Initialize forgot password flow - find user by email and get their phone
  Future<bool> initForgotPassword(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final normalizedEmail = email.trim().toLowerCase();
      final ownerData = await _dbService.getOwnerByEmail(normalizedEmail);

      if (ownerData == null) {
        _isLoading = false;
        _errorMessage = 'No account found with this email.';
        notifyListeners();
        return false;
      }

      final phone = ownerData['phone'] as String?;
      if (phone == null || phone.isEmpty || phone.startsWith('pending_')) {
        _isLoading = false;
        _errorMessage =
            'No verified phone number linked to this account. Please contact support.';
        notifyListeners();
        return false;
      }

      _forgotPasswordEmail = normalizedEmail;
      _forgotPasswordPhone = phone;
      _isForgotPasswordOtpSent = false;
      _isForgotPasswordOtpVerified = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not find account. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Send OTP to the phone number for password reset
  Future<bool> sendForgotPasswordOtp() async {
    try {
      if (_forgotPasswordPhone == null || _forgotPasswordPhone!.isEmpty) {
        _errorMessage = 'Phone number not found. Please start over.';
        notifyListeners();
        return false;
      }

      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Use signInWithOtp for existing users
      await _authService.sendPhoneOtp(phone: _forgotPasswordPhone!);

      _isForgotPasswordOtpSent = true;
      _phoneNumber = _forgotPasswordPhone;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not send OTP. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Verify OTP for password reset flow
  Future<bool> verifyForgotPasswordOtp(String otp) async {
    try {
      if (_forgotPasswordPhone == null || _forgotPasswordPhone!.isEmpty) {
        _errorMessage = 'Phone number not found. Please start over.';
        notifyListeners();
        return false;
      }

      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _authService.verifyPhoneOtp(
        phone: _forgotPasswordPhone!,
        token: otp,
      );

      _isForgotPasswordOtpVerified = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Invalid OTP. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Set new password after OTP verification (for forgot password flow)
  Future<bool> setNewPasswordAfterOtpVerification(String newPassword) async {
    try {
      if (!_isForgotPasswordOtpVerified) {
        _errorMessage = 'Please verify OTP first.';
        notifyListeners();
        return false;
      }

      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      if (!_isStrongPassword(newPassword)) {
        _isLoading = false;
        _errorMessage =
            'Password must be at least 8 characters with uppercase, lowercase, number, and special character.';
        notifyListeners();
        return false;
      }

      await _authService.updatePassword(newPassword);

      // Update has_password flag in database
      final uid = _authService.currentUserId;
      if (uid != null) {
        await _dbService.updateOwner(uid, {
          'has_password': true,
          'auth_methods': await _getUpdatedAuthMethods(uid, 'email'),
        });
        await _loadUserProfile(uid);
      }

      // Clear forgot password state
      _forgotPasswordEmail = null;
      _forgotPasswordPhone = null;
      _isForgotPasswordOtpSent = false;
      _isForgotPasswordOtpVerified = false;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not set password. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Helper to get updated auth methods
  Future<List<String>> _getUpdatedAuthMethods(
      String uid, String addMethod) async {
    final ownerData = await _dbService.getOwner(uid);
    final existingMethods = ownerData?['auth_methods'];
    final methods = existingMethods is List
        ? List<String>.from(existingMethods.map((m) => m.toString()))
        : <String>[];
    return _mergeAuthMethods(existing: methods, add: addMethod);
  }

  /// Clear forgot password state
  void clearForgotPasswordState() {
    _forgotPasswordEmail = null;
    _forgotPasswordPhone = null;
    _isForgotPasswordOtpSent = false;
    _isForgotPasswordOtpVerified = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Check if phone number is already registered to another owner.
  /// Returns null if phone is available, or returns error message if taken.
  Future<String?> checkPhoneAvailability(String phone) async {
    try {
      final existingEmail = await _dbService.checkPhoneAlreadyRegistered(phone);
      if (existingEmail != null) {
        // Check if it's the current user's phone (for re-verification scenarios)
        final currentEmail = _tempSignupEmail ?? _currentOwner?.email;
        if (currentEmail != null &&
            existingEmail.toLowerCase() == currentEmail.toLowerCase()) {
          return null; // Same user, phone is available for them
        }
        return 'This phone number is already registered with another account.';
      }
      return null; // Phone is available
    } catch (e) {
      // If check fails, allow to proceed (unique constraint will catch duplicates)
      return null;
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
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not update email. Please try again.',
      );
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
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not confirm email update. Please try again.',
      );
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

      if (!_isStrongPassword(newPassword)) {
        _isLoading = false;
        _errorMessage =
            'Password must be at least 8 characters with uppercase, lowercase, number, and special character.';
        notifyListeners();
        return false;
      }

      await _authService.updatePassword(newPassword);

      // Update has_password flag and add email to auth methods
      if (_currentOwner != null) {
        final updatedMethods = _mergeAuthMethods(
          existing: _currentOwner!.authMethods,
          add: 'email',
        );
        await _dbService.updateOwner(_currentOwner!.uid, {
          'has_password': true,
          'auth_methods': updatedMethods,
        });
        await _loadUserProfile(_currentOwner!.uid);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not update password. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Set password for Google user (unlocks manual login option)
  /// Requires phone OTP verification to be done first in the calling screen
  Future<bool> setPasswordForGoogleUser(String newPassword) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      if (!_isStrongPassword(newPassword)) {
        _isLoading = false;
        _errorMessage =
            'Password must be at least 8 characters with uppercase, lowercase, number, and special character.';
        notifyListeners();
        return false;
      }

      await _authService.updatePassword(newPassword);

      // Mark that this Google user now has a password and add email to auth methods
      if (_currentOwner != null) {
        final updatedMethods = _mergeAuthMethods(
          existing: _currentOwner!.authMethods,
          add: 'email',
        );
        await _dbService.updateOwner(_currentOwner!.uid, {
          'has_password': true,
          'auth_methods': updatedMethods,
        });
        await _loadUserProfile(_currentOwner!.uid);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not set password. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Get current email
  String? get currentEmail => _authService.currentUserEmail;

  /// Get current phone
  String? get currentPhone => _authService.currentUserPhone;

  /// Best-effort owner display values for UI while profile sync catches up.
  String get ownerDisplayName => _resolveOwnerName();

  String get ownerDisplayEmail {
    final ownerEmail = _currentOwner?.email.trim() ?? '';
    if (ownerEmail.isNotEmpty) {
      return ownerEmail;
    }
    return _normalizedEmail(_tempSignupEmail ?? _authService.currentUserEmail);
  }

  String get ownerDisplayPhone {
    final ownerPhone = _currentOwner?.phone.trim() ?? '';
    if (ownerPhone.isNotEmpty) {
      return ownerPhone;
    }
    return (_tempSignupPhone ??
            _phoneNumber ??
            _authService.currentUserPhone ??
            '')
        .trim();
  }

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
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not complete profile. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }
}
