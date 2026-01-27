import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firebase Authentication Service
/// Handles all authentication-related operations
class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Check if user is logged in
  bool get isLoggedIn => _auth.currentUser != null;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign up with email and password
  /// Returns the user ID on success
  Future<String> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String role, // 'OWNER' or 'PLAYER'
  }) async {
    try {
      // Create Firebase Auth user
      final UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String uid = credential.user!.uid;

      // Update display name
      await credential.user!.updateDisplayName(name);

      // Create document in Firestore based on role
      final String collection = role == 'OWNER' ? 'owners' : 'players';
      final Map<String, dynamic> userData = {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'profileImage': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': null,
      };

      // Add role-specific fields
      if (role == 'OWNER') {
        userData['isVerified'] = false;
        userData['authMethods'] = ['email'];
      } else {
        userData['favoriteTurfs'] = [];
      }

      try {
        if (role == 'OWNER') {
          final batch = _firestore.batch();
          final ownerRef = _firestore.collection(collection).doc(uid);
          batch.set(ownerRef, userData);

          final emailKey = email.trim().toLowerCase();
          final phoneKey = phone.trim();
          final emailIndexRef = _firestore.collection('owner_email_index').doc(emailKey);
          final phoneIndexRef = _firestore.collection('owner_phone_index').doc(phoneKey);

          batch.set(emailIndexRef, {
            'ownerId': uid,
            'email': emailKey,
            'createdAt': FieldValue.serverTimestamp(),
          });
          batch.set(phoneIndexRef, {
            'ownerId': uid,
            'phone': phoneKey,
            'createdAt': FieldValue.serverTimestamp(),
          });

          await batch.commit();
        } else {
          await _firestore.collection(collection).doc(uid).set(userData);
        }
      } catch (firestoreError) {
        // CRITICAL: If Firestore write fails, DELETE the auth user.
        // This prevents "Zombie Users" (Auth exists, but no Profile).
        await credential.user?.delete();
        if (firestoreError is FirebaseException && firestoreError.code == 'permission-denied') {
          throw 'Phone already registered. Please sign in instead.';
        }
        throw 'Database error: ${firestoreError.toString()}. Please try again.';
      }

      return uid;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  /// Sign in with email and password
  Future<String> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return credential.user!.uid;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  /// Verify phone number to send OTP
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String code, int? resendToken) onCodeSent,
    required Function(String errorMessage) onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Do not auto-sign-in to avoid bypassing owner checks.
      },
      verificationFailed: (FirebaseAuthException e) {
        onError(_handleAuthException(e));
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  /// Sign in with OTP
  Future<UserCredential> signInWithOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final AuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to sign in. Please check the code and try again.';
    }
  }

  /// Sign in with custom token (used after secure backend verification)
  Future<UserCredential> signInWithCustomToken(String token) async {
    try {
      return await _auth.signInWithCustomToken(token);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to sign in. Please try again.';
    }
  }

  /// Create or update user profile after phone auth
  Future<void> setupProfile({
    required String uid,
    required String name,
    required String email,
    required String phone,
    required String role,
  }) async {
    try {
      final String collection = role == 'OWNER' ? 'owners' : 'players';
      final Map<String, dynamic> userData = {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final doc = await _firestore.collection(collection).doc(uid).get();
      if (!doc.exists) {
        userData['createdAt'] = FieldValue.serverTimestamp();
        userData['profileImage'] = null;
        if (role == 'OWNER') {
          userData['isVerified'] = false;
        } else {
          userData['favoriteTurfs'] = [];
        }
      }

      await _firestore.collection(collection).doc(uid).set(userData, SetOptions(merge: true));
      await _auth.currentUser?.updateDisplayName(name);
    } catch (e) {
      throw 'Failed to setup profile: $e';
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Check if email is already registered
  Future<bool> isEmailRegistered(String email) async {
    try {
      final methods = await _auth.fetchSignInMethodsForEmail(email);
      return methods.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Handle Firebase Auth exceptions with user-friendly messages
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please sign in instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled.';
      case 'weak-password':
        return 'Please use a stronger password (at least 6 characters).';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
        return 'No account found with this email. Please sign up.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'invalid-verification-code':
        return 'Invalid OTP. Please try again.';
      case 'session-expired':
        return 'OTP expired. Please request a new one.';
      case 'invalid-verification-id':
        return 'OTP session invalid. Please request a new one.';
      default:
        return 'Authentication error: ${e.message ?? e.code}';
    }
  }
}
