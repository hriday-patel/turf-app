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

    test('isVerifiedPhone rejects pending placeholder values', () {
      expect(AuthFlowRules.isVerifiedPhone('pending_abcd1234'), isFalse);
      expect(AuthFlowRules.isVerifiedPhone(''), isFalse);
      expect(AuthFlowRules.isVerifiedPhone('+919900112233'), isTrue);
    });
  });
}
