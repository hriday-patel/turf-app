import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/database_service.dart';
import '../../../data/models/owner_model.dart';
import '../../../data/models/player_model.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/auth_flow_rules.dart';
import '../utils/auth_form_utils.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

enum _OtpFlow {
  none,
  ownerLogin,
  playerLogin,
  ownerPhoneVerification,
  deferredSignup,
  forgotPassword,
}

class _DeferredOwnerSignupData {
  final String uid;
  final UserRole role;
  final String name;
  final String email;
  final String phone;
  final String method;
  final bool hasPassword;
  final DateTime createdAt;
  final bool resumed;

  const _DeferredOwnerSignupData({
    required this.uid,
    required this.role,
    required this.name,
    required this.email,
    required this.phone,
    required this.method,
    required this.hasPassword,
    required this.createdAt,
    this.resumed = false,
  });

  _DeferredOwnerSignupData copyWith({
    String? uid,
    UserRole? role,
    String? name,
    String? email,
    String? phone,
    String? method,
    bool? hasPassword,
    DateTime? createdAt,
    bool? resumed,
  }) {
    return _DeferredOwnerSignupData(
      uid: uid ?? this.uid,
      role: role ?? this.role,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      method: method ?? this.method,
      hasPassword: hasPassword ?? this.hasPassword,
      createdAt: createdAt ?? this.createdAt,
      resumed: resumed ?? this.resumed,
    );
  }
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
  String? _blockingDialogMessage;
  bool _isLoading = false;
  String? _phoneNumber;
  _OtpFlow _otpFlow = _OtpFlow.none;
  bool _isResumingPendingSignup = false;

  // Pending signup data (account creation is completed only after OTP verify)
  _DeferredOwnerSignupData? _deferredOwnerSignup;

  // Getters
  AuthStatus get authState => _authState;
  OwnerModel? get currentOwner => _currentOwner;
  PlayerModel? get currentPlayer => _currentPlayer;
  String? get errorMessage => _errorMessage;
  String? get blockingDialogMessage => _blockingDialogMessage;
  String? get phoneNumber => _phoneNumber;
  bool get isAuthenticated => _authState == AuthStatus.authenticated;
  bool get isLoading => _authState == AuthStatus.loading || _isLoading;
  String? get currentUserId => _authService.currentUserId;
  bool get isInDeferredSignupFlow => _deferredOwnerSignup != null;
  bool get hasPendingSignup => _deferredOwnerSignup != null;
  bool get isResumingPendingSignup => _isResumingPendingSignup;
  UserRole? get pendingSignupRole => _deferredOwnerSignup?.role;
  String get deferredSignupPhone => _deferredOwnerSignup?.phone ?? '';
  String get deferredSignupMethod => _deferredOwnerSignup?.method ?? 'email';
  bool get isPendingSignupExpired => _isDeferredSignupExpired();
  bool get requiresOwnerGooglePhoneCollection {
    final deferred = _deferredOwnerSignup;
    if (deferred == null) return false;
    if (deferred.role != UserRole.owner) return false;
    if (deferred.method.trim().toLowerCase() != 'google') return false;
    return deferred.phone.trim().isEmpty;
  }

  bool get isOwnerPhoneVerified {
    final owner = _currentOwner;
    if (owner == null) return false;
    return AuthFlowRules.isVerifiedPhone(owner.phone);
  }

  bool get requiresOwnerPhoneVerificationGate {
    return AuthFlowRules.requiresOwnerPhoneVerificationGate(
      hasPendingOwnerSignup: _deferredOwnerSignup?.role == UserRole.owner,
      ownerPhone: _currentOwner?.phone ?? '',
    );
  }

  UserRole? get currentUserRole {
    if (_currentOwner != null) return UserRole.owner;
    if (_currentPlayer != null) return UserRole.player;
    return null;
  }

  String? consumeBlockingDialogMessage() {
    final value = _blockingDialogMessage;
    _blockingDialogMessage = null;
    return value;
  }

  void _setBlockingDialogMessage(String message) {
    _blockingDialogMessage = message;
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
        _clearDeferredOwnerSignup();
        _isResumingPendingSignup = false;
        notifyListeners();
      }
    });
  }

  DateTime _parsePendingCreatedAt(Map<String, dynamic> pending) {
    final raw = pending['created_at'];
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.parse(raw);
    }
    return DateTime.now();
  }

  Future<void> _forceSignOutWithMessage(String message) async {
    _errorMessage = message;
    _setBlockingDialogMessage(message);
    _clearOtpContext();
    _clearDeferredOwnerSignup();
    _currentOwner = null;
    _currentPlayer = null;
    try {
      await _authService.signOut();
    } catch (_) {}
    _authState = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> _handleExpiredPendingSignupSession() async {
    await _forceSignOutWithMessage(
      'Signup session expired. Please sign up again.',
    );
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
        _clearDeferredOwnerSignup();
        _isResumingPendingSignup = false;
        _authState = AuthStatus.authenticated;
        notifyListeners();
        return;
      }

      // Try to load player profile
      final playerData = await _dbService.getPlayer(uid);
      if (playerData != null) {
        _currentPlayer = PlayerModel.fromMap(playerData);
        _currentOwner = null;
        _clearDeferredOwnerSignup();
        _isResumingPendingSignup = false;
        _authState = AuthStatus.authenticated;
        notifyListeners();
        return;
      }

      // During deferred signup, keep session authenticated even before profile exists.
      if (_deferredOwnerSignup != null && _deferredOwnerSignup!.uid == uid) {
        _authState = AuthStatus.authenticated;
        _currentOwner = null;
        _currentPlayer = null;
        notifyListeners();
        return;
      }

      final pending = await _dbService.getPendingSignup(uid);
      if (pending != null) {
        final pendingCreatedAt = _parsePendingCreatedAt(pending);
        if (AuthFlowRules.isDeferredSignupExpired(pendingCreatedAt)) {
          await _handleExpiredPendingSignupSession();
          return;
        }
        final roleRaw = (pending['role'] ?? '').toString().toUpperCase();
        final role = roleRaw == 'OWNER' ? UserRole.owner : UserRole.player;
        _deferredOwnerSignup = _DeferredOwnerSignupData(
          uid: uid,
          role: role,
          name: (pending['name'] ?? '').toString(),
          email: (pending['email'] ?? '').toString(),
          phone: (pending['phone'] ?? '').toString(),
          method: (pending['auth_method'] ?? 'email').toString(),
          hasPassword: pending['has_password'] == true,
          createdAt: pendingCreatedAt,
          resumed: true,
        );
        _isResumingPendingSignup = true;
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
      _clearDeferredOwnerSignup();
      _isResumingPendingSignup = false;
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
        if (_authState == AuthStatus.unauthenticated &&
            _authService.currentUserId != null) {
          await _forceSignOutWithMessage(
            'Session could not be restored. Please sign in again.',
          );
        }
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
    return AuthFormUtils.isStrongPassword(password);
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
        message == 'No owner account found. Please sign up first.' ||
        message ==
            'This email is registered as a player account. Please use Player login.' ||
        message ==
            'This email is registered as an owner account. Please use Owner login.' ||
        message ==
            'This account belongs to a player. Please use Player login.' ||
        message ==
            'This account belongs to an owner. Please use Owner login.' ||
        message ==
            'This account uses Google. Use Google login or reset password.' ||
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

  /// Sign up new user (Owner or Player) into pending state.
  /// Profile is finalized only after mandatory phone OTP verification.
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
      _blockingDialogMessage = null;
      notifyListeners();

      // Validate password
      if (!_isStrongPassword(password)) {
        throw 'Password must be at least 8 characters with uppercase, lowercase, number, and special character.';
      }

      final normalizedEmail = _normalizedEmail(email);
      if (role == UserRole.owner) {
        final ownerByEmail = await _dbService.getOwnerByEmail(normalizedEmail);
        if (ownerByEmail != null) {
          throw 'Account already exists. Please log in instead.';
        }

        final playerByEmail =
            await _dbService.getPlayerByEmail(normalizedEmail);
        if (playerByEmail != null) {
          throw 'This email is registered as a player account. Please use Player login.';
        }
      }

      final normalizedPhone = AuthFormUtils.normalizeIndianPhone(phone);
      final availability = await _dbService.checkPhoneAvailabilityGlobal(
        phone: normalizedPhone,
      );
      if (availability['is_available'] != true) {
        _setBlockingDialogMessage(
          'This phone number is already linked to another account. Please use a different number or log in with that account.',
        );
        _authState = AuthStatus.error;
        _errorMessage = 'Phone number already linked to another account.';
        notifyListeners();
        return false;
      }

      // Create auth user first
      final uid = await _authService.signUpWithEmail(
        email: email,
        password: password,
      );

      try {
        await _dbService.upsertPendingSignup(
          userId: uid,
          role: role,
          name: name,
          email: normalizedEmail,
          phone: normalizedPhone,
          authMethod: 'email',
          hasPassword: true,
        );

        _deferredOwnerSignup = _DeferredOwnerSignupData(
          uid: uid,
          role: role,
          name: name.trim(),
          email: normalizedEmail,
          phone: normalizedPhone,
          method: 'email',
          hasPassword: true,
          createdAt: DateTime.now(),
          resumed: false,
        );
        _isResumingPendingSignup = false;
        _currentOwner = null;
        _currentPlayer = null;
      } catch (profileError) {
        // Pending state save failed — sign out the orphaned auth user
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
    return AuthFlowRules.mergeAuthMethods(existing: existing, add: add);
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

  void _setOtpContext({
    required String phone,
    required _OtpFlow flow,
  }) {
    _phoneNumber = phone;
    _otpFlow = flow;
  }

  void _clearOtpContext() {
    _phoneNumber = null;
    _otpFlow = _OtpFlow.none;
  }

  bool _isDeferredSignupExpired() {
    final deferred = _deferredOwnerSignup;
    if (deferred == null) return false;
    return AuthFlowRules.isDeferredSignupExpired(deferred.createdAt);
  }

  Future<bool> _ensureDeferredSignupValid() async {
    if (!_isDeferredSignupExpired()) {
      return true;
    }
    await _handleExpiredPendingSignupSession();
    return false;
  }

  Future<void> _sendOtpForFlow(_OtpFlow flow, String phone) async {
    switch (flow) {
      case _OtpFlow.ownerPhoneVerification:
      case _OtpFlow.deferredSignup:
        await _authService.sendPhoneChangeOtp(phone: phone);
        return;
      case _OtpFlow.ownerLogin:
        await _authService.sendPhoneOtp(phone: phone, shouldCreateUser: false);
        return;
      case _OtpFlow.playerLogin:
        await _authService.sendPhoneOtp(phone: phone, shouldCreateUser: true);
        return;
      case _OtpFlow.forgotPassword:
        await _authService.sendPhoneOtp(phone: phone, shouldCreateUser: false);
        return;
      case _OtpFlow.none:
        throw 'OTP flow is not initialized.';
    }
  }

  String _normalizedEmail(String? value) {
    return AuthFormUtils.normalizeEmail(value ?? '');
  }

  String _resolveOwnerName({String? emailFallback}) {
    final fromOwner = _currentOwner?.name.trim();
    if (fromOwner != null && fromOwner.isNotEmpty) {
      return fromOwner;
    }

    final fromTemp = _deferredOwnerSignup?.name.trim();
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
      emailFallback ??
          _deferredOwnerSignup?.email ??
          _authService.currentUserEmail,
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
  }) async {
    try {
      await _loadUserProfile(uid);
      if (_currentOwner != null) {
        return true;
      }

      if (_currentPlayer != null) {
        _errorMessage =
            'This email is registered as a player account. Please use Player login.';
        notifyListeners();
        return false;
      }

      final email = _normalizedEmail(
          _deferredOwnerSignup?.email ?? _authService.currentUserEmail);
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
              'This email is linked to another owner identity. Please use the original login method.';
          notifyListeners();
          return false;
        }

        _currentOwner = OwnerModel.fromMap(existingByEmail);
        _currentPlayer = null;
        _authState = AuthStatus.authenticated;
        notifyListeners();
        return true;
      }
      _errorMessage = 'No owner account found. Please sign up first.';
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not sync owner profile. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> ensureOwnerReadyForDashboard() async {
    final uid = _authService.currentUserId;
    if (uid == null || uid.isEmpty) {
      _errorMessage = 'Session expired. Please login again.';
      notifyListeners();
      return false;
    }

    if (isInDeferredSignupFlow) {
      if (_deferredOwnerSignup?.role != UserRole.owner) {
        _errorMessage = 'Pending signup belongs to a player account.';
        notifyListeners();
        return false;
      }
      return await _ensureDeferredSignupValid();
    }

    if (_currentOwner != null) {
      return true;
    }

    final recovered = await _recoverMissingOwnerProfile(uid: uid);
    if (!recovered || _currentOwner == null) {
      return false;
    }

    return true;
  }

  Future<bool> _signInWithGoogleForRole(UserRole role) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _blockingDialogMessage = null;
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
      if (_authService.currentUserId == null) {
        throw _errorMessage ??
            'Google sign-in session expired. Please try again.';
      }

      if (role == UserRole.owner && _currentPlayer != null) {
        throw 'This account belongs to a player. Please use Player login.';
      }
      if (role == UserRole.player && _currentOwner != null) {
        throw 'This account belongs to an owner. Please use Owner login.';
      }

      if (role == UserRole.owner && _currentOwner != null) {
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

      if (role == UserRole.player && _currentPlayer != null) {
        final methods = _mergeAuthMethods(
          existing: _currentPlayer!.authMethods,
          add: 'google',
        );
        await _dbService.updatePlayer(_currentPlayer!.uid, {
          'auth_methods': methods,
          'has_password': _currentPlayer!.hasPassword,
        });
        await _loadUserProfile(_currentPlayer!.uid);

        _isLoading = false;
        notifyListeners();
        return true;
      }

      final ownerByEmail = await _dbService.getOwnerByEmail(email);
      final playerByEmail = await _dbService.getPlayerByEmail(email);

      if (role == UserRole.owner && ownerByEmail != null) {
        final ownerByEmailId = ownerByEmail['id']?.toString() ?? '';
        if (ownerByEmailId.isNotEmpty && ownerByEmailId != uid) {
          _setBlockingDialogMessage(
            'This Google account email is already linked to another owner profile. Please use the original login method.',
          );
          await _authService.signOut();
          throw 'This email is linked to another owner identity. Please use the original login method.';
        }
        if (ownerByEmailId == uid) {
          _currentOwner = OwnerModel.fromMap(ownerByEmail);
          _currentPlayer = null;
          _authState = AuthStatus.authenticated;
          await _ensureOwnerAuthMethods({'google'});

          final updatedName =
              _authService.currentUser?.userMetadata?['full_name'] as String? ??
                  _authService.currentUser?.userMetadata?['name'] as String?;
          if (updatedName != null && updatedName.trim().isNotEmpty) {
            await _dbService.updateOwner(uid, {
              'name': updatedName.trim(),
              'email': email,
            });
            await _loadUserProfile(uid);
          }

          _isLoading = false;
          notifyListeners();
          return true;
        }
      }

      if (role == UserRole.owner &&
          playerByEmail != null &&
          (playerByEmail['id']?.toString() ?? '') != uid) {
        _setBlockingDialogMessage(
          'This email is registered as a player account. Please use Player login.',
        );
        throw 'This email is registered as a player account. Please use Player login.';
      }

      if (role == UserRole.player &&
          ownerByEmail != null &&
          (ownerByEmail['id']?.toString() ?? '') != uid) {
        _setBlockingDialogMessage(
          'This email is registered as an owner account. Please use Owner login.',
        );
        throw 'This email is registered as an owner account. Please use Owner login.';
      }

      // Missing profile: move to pending signup and enforce phone OTP.
      final resolvedName =
          _authService.currentUser?.userMetadata?['full_name'] as String? ??
              _authService.currentUser?.userMetadata?['name'] as String? ??
              email.split('@').first;

      final existingPending = await _dbService.getPendingSignup(uid);
      final pendingPhone = (existingPending?['phone'] ?? '').toString();
      final pendingMethod = (existingPending?['auth_method'] ?? 'google')
          .toString()
          .trim()
          .toLowerCase();
      final pendingHasPassword = existingPending?['has_password'] == true;
      final createdAt = existingPending != null
          ? _parsePendingCreatedAt(existingPending)
          : DateTime.now();

      await _dbService.upsertPendingSignup(
        userId: uid,
        role: role,
        name: resolvedName.trim(),
        email: email,
        phone: pendingPhone,
        authMethod: pendingMethod.isEmpty ? 'google' : pendingMethod,
        hasPassword: existingPending != null ? pendingHasPassword : false,
      );

      _deferredOwnerSignup = _DeferredOwnerSignupData(
        uid: uid,
        role: role,
        name: resolvedName.trim(),
        email: email,
        phone: pendingPhone,
        method: pendingMethod.isEmpty ? 'google' : pendingMethod,
        hasPassword: existingPending != null ? pendingHasPassword : false,
        createdAt: createdAt,
        resumed: existingPending != null,
      );
      _isResumingPendingSignup = existingPending != null;

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

  /// Owner-only Google OAuth login/signup.
  Future<bool> signInOwnerWithGoogle() async {
    return _signInWithGoogleForRole(UserRole.owner);
  }

  /// Player Google OAuth login/signup.
  Future<bool> signInPlayerWithGoogle() async {
    return _signInWithGoogleForRole(UserRole.player);
  }

  /// Persist phone number for deferred owner Google signup before OTP verification.
  Future<bool> stageOwnerGoogleSignupPhone(String phone) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _blockingDialogMessage = null;
      notifyListeners();

      final deferred = _deferredOwnerSignup;
      if (deferred == null || deferred.role != UserRole.owner) {
        throw 'No pending owner signup found. Please continue with Google first.';
      }

      final validDeferred = await _ensureDeferredSignupValid();
      if (!validDeferred) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final normalizedPhone = AuthFormUtils.normalizeIndianPhone(phone);
      final availability = await _dbService.checkPhoneAvailabilityGlobal(
        phone: normalizedPhone,
        excludeUserId: deferred.uid,
      );
      if (availability['is_available'] != true) {
        _setBlockingDialogMessage(
          'This phone number is already linked to another account. Please use a different number or log in with that account.',
        );
        _isLoading = false;
        _errorMessage = 'Phone number already linked to another account.';
        notifyListeners();
        return false;
      }

      await _dbService.upsertPendingSignup(
        userId: deferred.uid,
        role: deferred.role,
        name: deferred.name,
        email: deferred.email,
        phone: normalizedPhone,
        authMethod: deferred.method,
        hasPassword: deferred.hasPassword,
      );

      _deferredOwnerSignup = deferred.copyWith(
        phone: normalizedPhone,
        createdAt: DateTime.now(),
      );
      _authState = AuthStatus.authenticated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not save phone number. Please try again.',
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
      _blockingDialogMessage = null;
      notifyListeners();

      final uid = await _authService.signInWithEmail(
        email: email,
        password: password,
      );

      await _loadUserProfile(uid);

      if (_currentOwner == null) {
        final loggedInAsPlayer = _currentPlayer != null;
        await signOut();
        if (loggedInAsPlayer) {
          throw 'This email is registered as a player account. Please use Player login.';
        }
        throw 'No owner account found. Please sign up first.';
      }

      return true;
    } catch (e) {
      _authState = AuthStatus.error;

      final baseMessage = _friendlyAuthError(
        e,
        fallback: 'Could not sign in. Please try again.',
      );

      final normalizedEmail = AuthFormUtils.normalizeEmail(email);
      final ownerByEmail = await _dbService.getOwnerByEmail(normalizedEmail);
      final ownerMethods = ownerByEmail?['auth_methods'];
      final authMethods = ownerMethods is List
          ? List<String>.from(ownerMethods.map((m) => m.toString()))
          : const <String>[];
      final hasPassword = ownerByEmail?['has_password'] == true;

      if (baseMessage == 'Invalid email or password.' &&
          ownerByEmail != null &&
          authMethods.contains('google') &&
          !hasPassword) {
        _errorMessage =
            'This account uses Google. Use Google login or reset password.';
      } else {
        _errorMessage = baseMessage;
      }

      notifyListeners();
      return false;
    }
  }

  /// Player email/password login.
  Future<bool> signInPlayer({
    required String email,
    required String password,
  }) async {
    try {
      _authState = AuthStatus.loading;
      _errorMessage = null;
      _blockingDialogMessage = null;
      notifyListeners();

      final uid = await _authService.signInWithEmail(
        email: email,
        password: password,
      );

      await _loadUserProfile(uid);

      if (_currentPlayer == null) {
        final loggedInAsOwner = _currentOwner != null;
        await signOut();
        if (loggedInAsOwner) {
          throw 'This email is registered as an owner account. Please use Owner login.';
        }
        throw 'Player account not found. Please sign up.';
      }

      return true;
    } catch (e) {
      _authState = AuthStatus.error;

      final baseMessage = _friendlyAuthError(
        e,
        fallback: 'Could not sign in. Please try again.',
      );

      final normalizedEmail = AuthFormUtils.normalizeEmail(email);
      final playerByEmail = await _dbService.getPlayerByEmail(normalizedEmail);
      final playerMethods = playerByEmail?['auth_methods'];
      final authMethods = playerMethods is List
          ? List<String>.from(playerMethods.map((m) => m.toString()))
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

  /// Send OTP to phone number.
  ///
  /// Pending signup flow uses phone-change OTP and persists pending phone.
  /// Owner legacy login flow still uses SMS login OTP.
  Future<bool> sendPhoneOtp(String phone) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _blockingDialogMessage = null;
      notifyListeners();

      final normalizedPhone = AuthFormUtils.normalizeIndianPhone(phone);

      // Deferred signup also needs OTP while user is authenticated.
      if (isInDeferredSignupFlow && _authService.currentUserId != null) {
        if (!await _ensureDeferredSignupValid()) {
          _isLoading = false;
          return false;
        }

        final uid = _authService.currentUserId!;
        final availability = await _dbService.checkPhoneAvailabilityGlobal(
          phone: normalizedPhone,
          excludeUserId: uid,
        );
        if (availability['is_available'] != true) {
          _setBlockingDialogMessage(
            'This phone number is already linked to another account. Please use a different number or log in with that account.',
          );
          _isLoading = false;
          _errorMessage = 'Phone number already linked to another account.';
          notifyListeners();
          return false;
        }

        final deferred = _deferredOwnerSignup!;
        _deferredOwnerSignup = deferred.copyWith(phone: normalizedPhone);
        await _dbService.upsertPendingSignup(
          userId: deferred.uid,
          role: deferred.role,
          name: deferred.name,
          email: deferred.email,
          phone: normalizedPhone,
          authMethod: deferred.method,
          hasPassword: deferred.hasPassword,
        );

        _setOtpContext(phone: normalizedPhone, flow: _OtpFlow.deferredSignup);
        await _sendOtpForFlow(_otpFlow, normalizedPhone);
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Authenticated owners must verify phone to unlock app access.
      if (_currentOwner != null && _authService.currentUserId != null) {
        final ownerId = _currentOwner!.uid;
        final availability = await _dbService.checkPhoneAvailabilityGlobal(
          phone: normalizedPhone,
          excludeUserId: ownerId,
        );
        if (availability['is_available'] != true) {
          _setBlockingDialogMessage(
            'This phone number is already linked to another account. Please use a different number or log in with that account.',
          );
          _isLoading = false;
          _errorMessage = 'Phone number already linked to another account.';
          notifyListeners();
          return false;
        }

        _setOtpContext(
          phone: normalizedPhone,
          flow: _OtpFlow.ownerPhoneVerification,
        );
        await _sendOtpForFlow(_otpFlow, normalizedPhone);
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Login OTP: owner must exist by phone.
      final ownerExistsByPhone =
          await _dbService.ownerExists(phone: normalizedPhone);
      if (!ownerExistsByPhone) {
        _isLoading = false;
        _errorMessage = 'No owner account found. Please sign up first.';
        _clearOtpContext();
        notifyListeners();
        return false;
      }

      _setOtpContext(phone: normalizedPhone, flow: _OtpFlow.ownerLogin);
      await _sendOtpForFlow(_otpFlow, normalizedPhone);

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

  /// Send OTP for player login/signup flow.
  Future<bool> sendPlayerOtp(String phone) async {
    final pending = _deferredOwnerSignup;
    if (pending != null && pending.role == UserRole.player) {
      return sendPhoneOtp(phone);
    }

    _errorMessage =
        'Player phone OTP is only available during signup verification.';
    notifyListeners();
    return false;
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

      if (_otpFlow == _OtpFlow.deferredSignup &&
          !await _ensureDeferredSignupValid()) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (_otpFlow == _OtpFlow.ownerPhoneVerification ||
          _otpFlow == _OtpFlow.deferredSignup) {
        await _authService.verifyPhoneChangeOtp(
          phone: _phoneNumber!,
          token: smsCode,
        );

        if (_otpFlow == _OtpFlow.deferredSignup) {
          final deferred = _deferredOwnerSignup;
          if (deferred == null) {
            throw 'Pending signup not found. Please restart signup.';
          }

          final verifiedPhone = _phoneNumber!.trim();
          _deferredOwnerSignup = deferred.copyWith(phone: verifiedPhone);

          await _dbService.finalizePendingSignup(
            userId: deferred.uid,
            verifiedPhone: verifiedPhone,
          );
          await _loadUserProfile(deferred.uid);

          if (deferred.role == UserRole.owner && _currentOwner == null) {
            throw 'Could not load owner profile after verification.';
          }
          if (deferred.role == UserRole.player && _currentPlayer == null) {
            throw 'Could not load player profile after verification.';
          }

          _clearDeferredOwnerSignup();
          _isResumingPendingSignup = false;
          _clearOtpContext();
          _otpFlow = _OtpFlow.none;
          _isLoading = false;
          notifyListeners();
          return true;
        }

        final ownerId = _currentOwner?.uid ?? _authService.currentUserId;
        if (ownerId == null || ownerId.isEmpty) {
          throw 'Could not verify owner account.';
        }

        await _syncOwnerAfterOtp(
          ownerId: ownerId,
          verifiedPhone: _phoneNumber,
        );

        _otpFlow = _OtpFlow.none;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      if (_otpFlow == _OtpFlow.forgotPassword) {
        await _authService.verifyPhoneOtp(
          phone: _phoneNumber!,
          token: smsCode,
        );

        _isForgotPasswordOtpVerified = true;
        _otpFlow = _OtpFlow.none;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      if (_otpFlow == _OtpFlow.playerLogin) {
        final response = await _authService.verifyPhoneOtp(
          phone: _phoneNumber!,
          token: smsCode,
        );

        final uid = response.user?.id;
        if (uid == null || uid.isEmpty) {
          throw 'Authentication failed.';
        }

        await _loadUserProfile(uid);

        if (_currentOwner != null) {
          throw 'This account is registered as an owner. Use owner login.';
        }

        _otpFlow = _OtpFlow.none;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      if (_otpFlow != _OtpFlow.ownerLogin) {
        throw 'OTP flow is invalid. Please request OTP again.';
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
        final isPlayerAccount = _currentPlayer != null;
        await signOut();
        if (isPlayerAccount) {
          throw 'This account belongs to a player. Please use Player login.';
        }
        throw 'No owner account found. Please sign up first.';
      }

      await _syncOwnerAfterOtp(ownerId: uid, verifiedPhone: _phoneNumber);

      _otpFlow = _OtpFlow.none;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyAuthError(
        e,
        fallback: 'Could not verify OTP. Please try again.',
      );
      final lower = (_errorMessage ?? '').toLowerCase();
      if (lower.contains('phone') &&
          (lower.contains('already') || lower.contains('linked'))) {
        _setBlockingDialogMessage(
          'This phone number is already linked to another account. Please use a different number or log in with that account.',
        );
      }
      notifyListeners();
      return false;
    }
  }

  /// Complete deferred signup for Owner after OTP verification
  /// Compatibility method retained for owner dashboard fallback paths.
  Future<bool> completeDeferredOwnerSignup() async {
    try {
      final deferred = _deferredOwnerSignup;
      if (deferred == null) {
        return true;
      }

      if (deferred.role != UserRole.owner) {
        return true;
      }

      if (!await _ensureDeferredSignupValid()) {
        return false;
      }

      if (deferred.uid.trim().isEmpty ||
          deferred.name.trim().isEmpty ||
          deferred.email.trim().isEmpty ||
          deferred.phone.trim().isEmpty) {
        throw 'Signup information missing.';
      }

      _isLoading = true;
      notifyListeners();

      await _dbService.finalizePendingSignup(
        userId: deferred.uid,
        verifiedPhone: deferred.phone,
      );

      // Load the created profile
      await _loadUserProfile(deferred.uid);

      if (_currentOwner == null) {
        throw 'Could not load owner profile after signup completion.';
      }

      // Clear temporary state
      _clearDeferredOwnerSignup();

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
      _clearOtpContext();
      _clearDeferredOwnerSignup();
      _blockingDialogMessage = null;
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
      _clearDeferredOwnerSignup();
      _clearOtpContext();

      // Sign out the Supabase auth user
      await _authService.signOut();

      _currentOwner = null;
      _currentPlayer = null;
      _authState = AuthStatus.unauthenticated;
      _blockingDialogMessage = null;
      notifyListeners();
    } catch (e) {
      // Even if signout fails, clear all local state
      _currentOwner = null;
      _currentPlayer = null;
      _authState = AuthStatus.unauthenticated;
      _blockingDialogMessage = null;
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

      final normalizedEmail = AuthFormUtils.normalizeEmail(email);
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

      _setOtpContext(
          phone: _forgotPasswordPhone!, flow: _OtpFlow.forgotPassword);
      await _sendOtpForFlow(_otpFlow, _forgotPasswordPhone!);

      _isForgotPasswordOtpSent = true;
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
    if (_forgotPasswordPhone == null || _forgotPasswordPhone!.isEmpty) {
      _errorMessage = 'Phone number not found. Please start over.';
      notifyListeners();
      return false;
    }

    if (_otpFlow == _OtpFlow.none) {
      _setOtpContext(
          phone: _forgotPasswordPhone!, flow: _OtpFlow.forgotPassword);
    }

    return verifyOTP(otp);
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

  /// Check if phone number is globally available.
  /// Returns null if phone is available, or returns error message if taken.
  Future<String?> checkPhoneAvailability(String phone) async {
    try {
      final availability = await _dbService.checkPhoneAvailabilityGlobal(
        phone: phone.trim(),
        excludeUserId: _authService.currentUserId,
      );
      if (availability['is_available'] != true) {
        const message =
            'This phone number is already linked to another account. Please use a different number or log in with that account.';
        _setBlockingDialogMessage(message);
        return message;
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
    _blockingDialogMessage = null;
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
  Future<bool> verifyPhone(
    String phone, {
    UserRole role = UserRole.owner,
  }) async {
    if (isInDeferredSignupFlow) {
      return await sendPhoneOtp(phone);
    }
    if (role == UserRole.player) {
      return await sendPlayerOtp(phone);
    }
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

      final normalizedEmail = AuthFormUtils.normalizeEmail(expectedEmail);

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
    return _normalizedEmail(
        _deferredOwnerSignup?.email ?? _authService.currentUserEmail);
  }

  String get ownerDisplayPhone {
    final ownerPhone = _currentOwner?.phone.trim() ?? '';
    if (ownerPhone.isNotEmpty) {
      return ownerPhone;
    }
    return (_deferredOwnerSignup?.phone ??
            _phoneNumber ??
            _authService.currentUserPhone ??
            '')
        .trim();
  }

  void _clearDeferredOwnerSignup() {
    _deferredOwnerSignup = null;
    _isResumingPendingSignup = false;
  }

  Future<void> _syncOwnerAfterOtp({
    required String ownerId,
    String? verifiedPhone,
  }) async {
    final normalizedPhone = (verifiedPhone ?? _phoneNumber ?? '').trim();
    if (normalizedPhone.isEmpty) {
      throw 'Verified phone is required.';
    }
    await _dbService.syncOwnerAfterOtp(
      ownerId: ownerId,
      verifiedPhone: normalizedPhone,
    );

    await _loadUserProfile(ownerId);

    if (_currentOwner == null) {
      final recovered = await _recoverMissingOwnerProfile(
        uid: ownerId,
      );
      if (!recovered || _currentOwner == null) {
        throw _errorMessage ??
            'Owner profile could not be synced after verification.';
      }
    }
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
        throw 'Owner profiles are created only after pending signup OTP verification.';
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
