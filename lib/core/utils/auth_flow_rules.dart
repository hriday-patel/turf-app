class AuthFlowRules {
  static const Duration deferredSignupTtl = Duration(minutes: 30);

  static bool isDeferredSignupExpired(
    DateTime createdAt, {
    DateTime? now,
    Duration ttl = deferredSignupTtl,
  }) {
    final currentTime = now ?? DateTime.now();
    return currentTime.difference(createdAt) > ttl;
  }

  static List<String> mergeAuthMethods({
    required List<String> existing,
    required String add,
  }) {
    final merged = <String>{
      ...existing.where((m) => m.trim().isNotEmpty),
      add,
    };
    return merged.toList()..sort();
  }

  static bool isVerifiedPhone(String value) {
    final phone = value.trim();
    return phone.isNotEmpty && !phone.startsWith('pending_');
  }

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
