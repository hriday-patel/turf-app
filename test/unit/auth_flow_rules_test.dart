import 'package:flutter_test/flutter_test.dart';
import 'package:fieldpass_business/core/utils/auth_flow_rules.dart';

void main() {
  group('AuthFlowRules', () {
    test('mergeAuthMethods deduplicates and sorts', () {
      final merged = AuthFlowRules.mergeAuthMethods(
        existing: ['google', 'email', ''],
        add: 'otp',
      );

      expect(merged, ['email', 'google', 'otp']);
    });

    test('canUsePasswordLogin accepts manual password account', () {
      expect(
        AuthFlowRules.canUsePasswordLogin(
          authMethods: const ['email', 'otp'],
          hasPassword: true,
        ),
        isTrue,
      );
    });

    test('canUsePasswordLogin rejects google-only account', () {
      expect(
        AuthFlowRules.canUsePasswordLogin(
          authMethods: const ['google', 'otp'],
          hasPassword: false,
        ),
        isFalse,
      );
    });

    test('canUsePasswordLogin requires email method and password flag', () {
      expect(
        AuthFlowRules.canUsePasswordLogin(
          authMethods: const ['email', 'google', 'otp'],
          hasPassword: false,
        ),
        isFalse,
      );
      expect(
        AuthFlowRules.canUsePasswordLogin(
          authMethods: const ['google', 'otp'],
          hasPassword: true,
        ),
        isFalse,
      );
    });

    test('isDeferredSignupExpired returns true after ttl', () {
      final createdAt = DateTime(2026, 3, 30, 10, 0, 0);
      final now = createdAt.add(const Duration(minutes: 31));

      expect(
        AuthFlowRules.isDeferredSignupExpired(createdAt, now: now),
        isTrue,
      );
    });

    test('isDeferredSignupExpired returns false inside ttl', () {
      final createdAt = DateTime(2026, 3, 30, 10, 0, 0);
      final now = createdAt.add(const Duration(minutes: 15));

      expect(
        AuthFlowRules.isDeferredSignupExpired(createdAt, now: now),
        isFalse,
      );
    });

    test('isDeferredSignupResumable rejects missing timestamp', () {
      expect(AuthFlowRules.isDeferredSignupResumable(null), isFalse);
    });

    test('isDeferredSignupResumable accepts fresh pending signup', () {
      final createdAt = DateTime(2026, 3, 30, 10, 0, 0);
      final now = createdAt.add(const Duration(minutes: 10));

      expect(
        AuthFlowRules.isDeferredSignupResumable(createdAt, now: now),
        isTrue,
      );
    });

    test('isDeferredSignupResumable rejects stale pending signup', () {
      final createdAt = DateTime(2026, 3, 30, 10, 0, 0);
      final now = createdAt.add(const Duration(minutes: 31));

      expect(
        AuthFlowRules.isDeferredSignupResumable(createdAt, now: now),
        isFalse,
      );
    });

    test('isVerifiedPhone rejects pending placeholder values', () {
      expect(AuthFlowRules.isVerifiedPhone('pending_abcd1234'), isFalse);
      expect(AuthFlowRules.isVerifiedPhone(''), isFalse);
      expect(AuthFlowRules.isVerifiedPhone('+919900112233'), isTrue);
    });
  });
}
