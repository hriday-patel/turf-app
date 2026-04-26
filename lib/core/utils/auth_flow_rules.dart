/// Pure auth-flow business rules.
///
/// Stateless helpers shared by `AuthProvider` and tests. Keep this file
/// dependency-free (no Flutter, no Supabase) so it stays easy to unit
/// test and reason about.
class AuthFlowRules {
  /// Time window during which a not-yet-completed signup row is treated
  /// as resumable. Older deferred signups are considered abandoned.
  static const Duration deferredSignupTtl = Duration(minutes: 30);

  /// Returns true if a deferred signup row is past its TTL and should
  /// be treated as expired (forcing the user to start signup over).
  static bool isDeferredSignupExpired(
    DateTime createdAt, {
    DateTime? now,
    Duration ttl = deferredSignupTtl,
  }) {
    final currentTime = now ?? DateTime.now();
    return currentTime.difference(createdAt) > ttl;
  }

  /// Returns true when a pending signup has a valid timestamp and is still
  /// inside the resume window.
  static bool isDeferredSignupResumable(
    DateTime? createdAt, {
    DateTime? now,
    Duration ttl = deferredSignupTtl,
  }) {
    if (createdAt == null) return false;
    return !isDeferredSignupExpired(createdAt, now: now, ttl: ttl);
  }

  /// Merge a new auth method (`add`) into an existing list of methods,
  /// returning a sorted, de-duplicated, lowercase list.
  ///
  /// Phase 8 Iter 2 AUTH-01 + AUTH-02: trims and lowercases on both sides
  /// and silently skips empty/whitespace-only `add` values so a single
  /// upstream typo cannot persist a phantom method or duplicate row
  /// (e.g. 'Google' vs 'google').
  static List<String> mergeAuthMethods({
    required List<String> existing,
    required String add,
  }) {
    final normalizedAdd = add.trim().toLowerCase();
    final merged = <String>{
      ...existing.map((m) => m.trim().toLowerCase()).where((m) => m.isNotEmpty),
      if (normalizedAdd.isNotEmpty) normalizedAdd,
    };
    return merged.toList()..sort();
  }

  /// Returns true only for accounts that were created with, or already
  /// legitimately have, an email/password credential.
  static bool canUsePasswordLogin({
    required Iterable<String> authMethods,
    required bool hasPassword,
  }) {
    if (!hasPassword) return false;
    return authMethods
        .map((method) => method.trim().toLowerCase())
        .contains('email');
  }

  /// Returns true if [value] looks like a real verified phone number
  /// (non-empty and not the temporary `pending_*` placeholder we use
  /// while OTP is in-flight).
  static bool isVerifiedPhone(String value) {
    final phone = value.trim();
    return phone.isNotEmpty && !phone.startsWith('pending_');
  }

  /// Returns true if the owner must complete phone verification before
  /// proceeding (either a deferred signup row exists, or their stored
  /// phone is missing/placeholder).
  static bool requiresOwnerPhoneVerificationGate({
    required bool hasPendingOwnerSignup,
    required String ownerPhone,
  }) {
    if (hasPendingOwnerSignup) {
      return true;
    }
    return !isVerifiedPhone(ownerPhone);
  }
}
