import 'dart:math' as math;

import '../../core/constants/enums.dart';

/// Phase 4 Iter 13 BM-10: booking record for a specific turf slot.
///
/// Invariants enforced by [BookingModel.fromMap]:
///   * [amount] >= 0 and [advanceAmount] is clamped to `[0, amount]`.
///   * [netNumber] >= 1.
///   * `HH:MM` start/end times are preserved verbatim; invalid values
///     fall through to the raw string in display helpers rather than
///     crashing the UI.
///   * Malformed timestamp strings from legacy rows fall back to
///     `DateTime.now()` instead of throwing.
///   * [cancelledAt] / [cancelledBy] / [cancellationReason] should be
///     set iff [bookingStatus] == `BookingStatus.cancelled`, but the
///     model does not enforce this — DB triggers / service layer do.
class BookingModel {
  final String bookingId;
  final String turfId;
  final String slotId;

  // Slot Info (denormalized)
  final String bookingDate;
  final String startTime;
  final String endTime;
  final String turfName;
  final int netNumber; // Net number for multi-net turfs

  // Customer Info
  final String? userId;
  final String customerName;
  final String customerPhone;

  // Booking Details
  final BookingSource bookingSource;

  // Payment Info
  final PaymentMode paymentMode;
  final PaymentStatus paymentStatus;
  final double amount;
  final double advanceAmount; // Advance payment received
  final String? transactionId;

  // Status
  final BookingStatus bookingStatus;

  // Cancellation Info
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancellationReason;

  // Metadata
  final DateTime createdAt;
  final DateTime? updatedAt;

  BookingModel({
    required this.bookingId,
    required this.turfId,
    required this.slotId,
    required this.bookingDate,
    required this.startTime,
    required this.endTime,
    required this.turfName,
    this.netNumber = 1,
    this.userId,
    required this.customerName,
    required this.customerPhone,
    required this.bookingSource,
    required this.paymentMode,
    required this.paymentStatus,
    required this.amount,
    this.advanceAmount = 0,
    this.transactionId,
    this.bookingStatus = BookingStatus.confirmed,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
    required this.createdAt,
    this.updatedAt,
  });

  /// Create from Supabase map
  factory BookingModel.fromMap(Map<String, dynamic> data) {
    // Phase 4 Iter 13 BM-02: tolerate malformed timestamps from
    // legacy rows instead of crashing list fetches.
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    // Phase 4 Iter 13 BM-05: clamp amounts to sane ranges.
    final rawAmount = (data['amount'] ?? 0);
    final amount = rawAmount is num
        ? math.max(0.0, rawAmount.toDouble())
        : math.max(0.0, double.tryParse(rawAmount.toString()) ?? 0);
    final rawAdvance = data['advance_amount'] ?? data['advanceAmount'] ?? 0;
    final advanceRaw = rawAdvance is num
        ? rawAdvance.toDouble()
        : double.tryParse(rawAdvance.toString()) ?? 0.0;
    final advance = advanceRaw.clamp(0.0, amount).toDouble();

    // Phase 4 Iter 13 BM-06: guard against 0/negative net numbers.
    final rawNet = data['net_number'] ?? data['netNumber'] ?? 1;
    final netNum =
        rawNet is int ? rawNet : int.tryParse(rawNet.toString()) ?? 1;
    final safeNet = netNum < 1 ? 1 : netNum;

    return BookingModel(
      bookingId: data['id'] ?? data['bookingId'] ?? '',
      turfId: data['turf_id'] ?? data['turfId'] ?? '',
      slotId: data['slot_id'] ?? data['slotId'] ?? '',
      bookingDate: data['booking_date'] ?? data['bookingDate'] ?? '',
      startTime: data['start_time'] ?? data['startTime'] ?? '',
      endTime: data['end_time'] ?? data['endTime'] ?? '',
      turfName: data['turf_name'] ?? data['turfName'] ?? '',
      netNumber: safeNet,
      userId: data['user_id'] ?? data['userId'],
      customerName: data['customer_name'] ?? data['customerName'] ?? '',
      customerPhone: data['customer_phone'] ?? data['customerPhone'] ?? '',
      bookingSource: BookingSourceExtension.fromString(
        data['booking_source'] ?? data['bookingSource'] ?? 'APP',
      ),
      paymentMode: PaymentModeExtension.fromString(
        data['payment_mode'] ?? data['paymentMode'] ?? 'OFFLINE',
      ),
      paymentStatus: PaymentStatusExtension.fromString(
        data['payment_status'] ?? data['paymentStatus'] ?? 'PENDING',
      ),
      amount: amount,
      advanceAmount: advance,
      transactionId: data['transaction_id'] ?? data['transactionId'],
      bookingStatus: BookingStatusExtension.fromString(
        data['booking_status'] ?? data['bookingStatus'] ?? 'CONFIRMED',
      ),
      cancelledAt: data['cancelled_at'] != null || data['cancelledAt'] != null
          ? parseDate(data['cancelled_at'] ?? data['cancelledAt'])
          : null,
      cancelledBy: data['cancelled_by'] ?? data['cancelledBy'],
      cancellationReason:
          data['cancellation_reason'] ?? data['cancellationReason'],
      createdAt: parseDate(data['created_at'] ?? data['createdAt']),
      updatedAt: data['updated_at'] != null || data['updatedAt'] != null
          ? parseDate(data['updated_at'] ?? data['updatedAt'])
          : null,
    );
  }

  /// Convert to Supabase map
  Map<String, dynamic> toMap() {
    return {
      'turf_id': turfId,
      'slot_id': slotId,
      'booking_date': bookingDate,
      'start_time': startTime,
      'end_time': endTime,
      'turf_name': turfName,
      'net_number': netNumber,
      'user_id': userId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'booking_source': bookingSource.value,
      'payment_mode': paymentMode.value,
      'payment_status': paymentStatus.value,
      'amount': amount,
      'advance_amount': advanceAmount,
      'transaction_id': transactionId,
      'booking_status': bookingStatus.value,
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancelled_by': cancelledBy,
      'cancellation_reason': cancellationReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Get display time range
  String get displayTimeRange {
    return '${_formatTime(startTime)} - ${_formatTime(endTime)}';
  }

  /// Phase 4 Iter 13 BM-01: malformed `startTime`/`endTime` now returns
  /// the raw value instead of crashing the UI with a FormatException.
  /// BM-08: single-digit hours are zero-padded for consistent layout.
  static final RegExp _timeHHMM = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  String _formatTime(String time24) {
    if (!_timeHHMM.hasMatch(time24)) return time24;
    final parts = time24.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final paddedHour = displayHour.toString().padLeft(2, '0');
    return '$paddedHour:$minute $period';
  }

  /// Check if this is an app booking
  bool get isAppBooking => bookingSource == BookingSource.app;

  /// Check if this is a manual (phone/walk-in) booking
  bool get isManualBooking =>
      bookingSource == BookingSource.phone ||
      bookingSource == BookingSource.walkIn;

  /// Check if payment is completed
  bool get isPaid => paymentStatus == PaymentStatus.paid;

  /// Phase 4 Iter 13 BM-07: distinct pay-at-turf signal for callers
  /// that need to show "pay on arrival" UI separately.
  bool get isPayAtTurf => paymentStatus == PaymentStatus.payAtTurf;

  /// Check if payment is pending (pay at turf OR has advance but not confirmed)
  bool get isPendingPayment =>
      paymentStatus == PaymentStatus.payAtTurf ||
      paymentStatus == PaymentStatus.pending;

  /// Phase 4 Iter 13 BM-04: active means the slot is still upcoming /
  /// honorable. `completed`, `noShow`, and `cancelled` are all terminal
  /// states and therefore NOT active.
  bool get isActive => bookingStatus == BookingStatus.confirmed;

  bool get isCancelled => bookingStatus == BookingStatus.cancelled;

  bool get isCompleted => bookingStatus == BookingStatus.completed;

  /// Check if this is a partial payment booking
  bool get isPartialPayment => advanceAmount > 0 && advanceAmount < amount;

  /// Get remaining amount to be paid
  double get remainingAmount => amount - advanceAmount;

  /// Copy with modified fields.
  /// Phase 4 Iter 13 BM-03: [netNumber] is now preserved (previously
  /// silently reset to the default of 1 on every copy).
  BookingModel copyWith({
    int? netNumber,
    PaymentStatus? paymentStatus,
    String? transactionId,
    BookingStatus? bookingStatus,
    DateTime? cancelledAt,
    String? cancelledBy,
    String? cancellationReason,
    DateTime? updatedAt,
  }) {
    return BookingModel(
      bookingId: bookingId,
      turfId: turfId,
      slotId: slotId,
      bookingDate: bookingDate,
      startTime: startTime,
      endTime: endTime,
      turfName: turfName,
      netNumber: netNumber ?? this.netNumber,
      userId: userId,
      customerName: customerName,
      customerPhone: customerPhone,
      bookingSource: bookingSource,
      paymentMode: paymentMode,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      amount: amount,
      advanceAmount: advanceAmount,
      transactionId: transactionId ?? this.transactionId,
      bookingStatus: bookingStatus ?? this.bookingStatus,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    // Phase 4 Iter 13 BM-09: include customer phone + amount for
    // support-log triage.
    return 'BookingModel(bookingId: $bookingId, turfName: $turfName, date: $bookingDate, '
        'customerPhone: $customerPhone, amount: $amount, status: ${bookingStatus.displayName})';
  }
}
