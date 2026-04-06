class BookingFlowRules {
  static double clampAdvanceAmount({
    required double totalAmount,
    required double advanceAmount,
  }) {
    if (advanceAmount < 0) {
      return 0;
    }
    if (advanceAmount > totalAmount) {
      return totalAmount;
    }
    return advanceAmount;
  }

  static String paymentStatusForManualBooking({
    required double totalAmount,
    required double advanceAmount,
  }) {
    if (totalAmount > 0 && advanceAmount >= totalAmount) {
      return 'PAID';
    }
    return 'PENDING';
  }

  static String slotStatusForAmounts({
    required double totalAmount,
    required double advanceAmount,
  }) {
    if (totalAmount > 0 && advanceAmount >= totalAmount) {
      return 'BOOKED';
    }
    return 'RESERVED';
  }
}
