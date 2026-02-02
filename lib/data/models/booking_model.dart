import '../../core/constants/enums.dart';

/// Booking model representing a turf slot booking
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
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) return DateTime.parse(value);
      return DateTime.now();
    }

    return BookingModel(
      bookingId: data['id'] ?? data['bookingId'] ?? '',
      turfId: data['turf_id'] ?? data['turfId'] ?? '',
      slotId: data['slot_id'] ?? data['slotId'] ?? '',
      bookingDate: data['booking_date'] ?? data['bookingDate'] ?? '',
      startTime: data['start_time'] ?? data['startTime'] ?? '',
      endTime: data['end_time'] ?? data['endTime'] ?? '',
      turfName: data['turf_name'] ?? data['turfName'] ?? '',
      netNumber: data['net_number'] ?? data['netNumber'] ?? 1,
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
      amount: (data['amount'] ?? 0).toDouble(),
      advanceAmount: (data['advance_amount'] ?? data['advanceAmount'] ?? 0).toDouble(),
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

  String _formatTime(String time24) {
    final parts = time24.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  /// Check if this is an app booking
  bool get isAppBooking => bookingSource == BookingSource.app;

  /// Check if this is a manual (phone/walk-in) booking
  bool get isManualBooking =>
      bookingSource == BookingSource.phone ||
      bookingSource == BookingSource.walkIn;

  /// Check if payment is completed
  bool get isPaid => paymentStatus == PaymentStatus.paid;

  /// Check if payment is pending (pay at turf OR has advance but not confirmed)
  bool get isPendingPayment => 
      paymentStatus == PaymentStatus.payAtTurf || 
      paymentStatus == PaymentStatus.pending;

  /// Check if booking is active (not cancelled)
  bool get isActive => bookingStatus == BookingStatus.confirmed;

  /// Check if this is a partial payment booking
  bool get isPartialPayment => advanceAmount > 0 && advanceAmount < amount;

  /// Get remaining amount to be paid
  double get remainingAmount => amount - advanceAmount;

  /// Copy with modified fields
  BookingModel copyWith({
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
    return 'BookingModel(bookingId: $bookingId, turfName: $turfName, date: $bookingDate, status: ${bookingStatus.displayName})';
  }
}
