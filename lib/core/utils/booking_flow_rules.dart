/// Pure booking-flow business rules.
///
/// Stateless helpers used by manual-booking and slot-management code.
/// Keep this file dependency-free (no Flutter, no Supabase) so it stays
/// easy to unit test.
class BookingFlowRules {
  /// Clamp an advance amount into the valid range `[0, totalAmount]`.
  ///
  /// Phase 8 Iter 3 BOOK-01: defensively coerces `NaN` and `Infinity`
  /// (which would otherwise sail past `<` / `>` comparisons) to `0` so
  /// a malformed text-field parse never poisons the booking row.
  static double clampAdvanceAmount({
    required double totalAmount,
    required double advanceAmount,
  }) {
    if (advanceAmount.isNaN || advanceAmount.isInfinite) {
      return 0;
    }
    if (advanceAmount < 0) {
      return 0;
    }
    if (advanceAmount > totalAmount) {
      return totalAmount;
    }
    return advanceAmount;
  }

  /// Returns the payment status (`'PAID'` or `'PENDING'`) for a manual
  /// booking given the total and the advance collected.
  ///
  /// Phase 8 Iter 3 BOOK-02: a zero-priced (complimentary / fully
  /// discounted) booking is treated as `'PAID'` since `0 >= 0` is fully
  /// settled. Previously these rows were stuck in `'PENDING'` forever.
  static String paymentStatusForManualBooking({
    required double totalAmount,
    required double advanceAmount,
  }) {
    if (advanceAmount >= totalAmount) {
      return 'PAID';
    }
    return 'PENDING';
  }

  /// Returns the slot status (`'BOOKED'` or `'RESERVED'`) for the same
  /// amount comparison. Mirrors [paymentStatusForManualBooking] so a
  /// fully-paid booking always lands in `'BOOKED'`.
  ///
  /// Phase 8 Iter 3 BOOK-02: zero-priced bookings now flip to
  /// `'BOOKED'` instead of being stranded in `'RESERVED'`.
  static String slotStatusForAmounts({
    required double totalAmount,
    required double advanceAmount,
  }) {
    if (advanceAmount >= totalAmount) {
      return 'BOOKED';
    }
    return 'RESERVED';
  }
}
