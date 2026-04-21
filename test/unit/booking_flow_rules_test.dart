import 'package:flutter_test/flutter_test.dart';
import 'package:fieldpass_business/core/utils/booking_flow_rules.dart';

void main() {
  group('BookingFlowRules', () {
    test('clampAdvanceAmount limits advance to total amount', () {
      final clamped = BookingFlowRules.clampAdvanceAmount(
        totalAmount: 1200,
        advanceAmount: 1500,
      );

      expect(clamped, 1200);
    });

    test('slot and payment transitions for partial payment', () {
      final paymentStatus = BookingFlowRules.paymentStatusForManualBooking(
        totalAmount: 1200,
        advanceAmount: 300,
      );
      final slotStatus = BookingFlowRules.slotStatusForAmounts(
        totalAmount: 1200,
        advanceAmount: 300,
      );

      expect(paymentStatus, 'PENDING');
      expect(slotStatus, 'RESERVED');
    });

    test('slot and payment transitions for full payment', () {
      final paymentStatus = BookingFlowRules.paymentStatusForManualBooking(
        totalAmount: 1200,
        advanceAmount: 1200,
      );
      final slotStatus = BookingFlowRules.slotStatusForAmounts(
        totalAmount: 1200,
        advanceAmount: 1200,
      );

      expect(paymentStatus, 'PAID');
      expect(slotStatus, 'BOOKED');
    });
  });
}
