import 'dart:math' as math;

import '../../core/constants/enums.dart';

/// Phase 4 Iter 14 SM-10: slot record for a given turf/net/date/time.
///
/// Invariants enforced by [SlotModel.fromMap]:
///   * [price] >= 0 and [netNumber] >= 1.
///   * [priceType] is normalised to UPPER_CASE so downstream matchers
///     work across legacy lowercase DB rows.
///   * `HH:MM` strings are preserved verbatim; invalid values fall
///     through to the raw string in display helpers rather than
///     crashing the UI.
///   * Malformed timestamp strings fall back to `DateTime.now()`.
///
/// Note: [isBookable] consults the device clock for expired
/// reservations. Server RPC is authoritative; the client check is
/// best-effort and uses a small skew buffer.
class SlotModel {
  final String slotId;
  final String turfId;

  // Time Information
  final String date; // "2026-01-27"
  final String startTime; // "18:00"
  final String endTime; // "19:00"

  // Net Information (for multi-net turfs)
  final int netNumber;

  // Status
  final SlotStatus status;

  // Reservation Tracking
  final DateTime? reservedUntil;
  final String? reservedBy;

  // Pricing
  final double price;
  final String priceType; // "WEEKDAY_NIGHT"

  // Blocking Info (manual by owner)
  final String? blockedBy;
  final String? blockReason;

  // Metadata
  final DateTime createdAt;

  SlotModel({
    required this.slotId,
    required this.turfId,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.netNumber = 1,
    this.status = SlotStatus.available,
    this.reservedUntil,
    this.reservedBy,
    required this.price,
    required this.priceType,
    this.blockedBy,
    this.blockReason,
    required this.createdAt,
  });

  /// Create from Supabase map
  factory SlotModel.fromMap(Map<String, dynamic> data) {
    // Phase 4 Iter 14 SM-01: tolerate malformed timestamps.
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    DateTime? parseDateNullable(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    // Phase 4 Iter 14 SM-03: clamp price to non-negative.
    final rawPrice = data['price'] ?? 0;
    final price = rawPrice is num
        ? math.max(0.0, rawPrice.toDouble())
        : math.max(0.0, double.tryParse(rawPrice.toString()) ?? 0);

    // Phase 4 Iter 14 SM-04: clamp netNumber >= 1.
    final rawNet = data['net_number'] ?? data['netNumber'] ?? 1;
    final netNum =
        rawNet is int ? rawNet : int.tryParse(rawNet.toString()) ?? 1;
    final safeNet = netNum < 1 ? 1 : netNum;

    // Phase 4 Iter 14 SM-08: normalise priceType casing.
    final rawPriceType = data['price_type'] ?? data['priceType'] ?? '';
    final priceType = rawPriceType.toString().toUpperCase();

    return SlotModel(
      slotId: data['id'] ?? data['slotId'] ?? '',
      turfId: data['turf_id'] ?? data['turfId'] ?? '',
      date: data['date'] ?? '',
      startTime: data['start_time'] ?? data['startTime'] ?? '',
      endTime: data['end_time'] ?? data['endTime'] ?? '',
      netNumber: safeNet,
      status: SlotStatusExtension.fromString(data['status'] ?? 'AVAILABLE'),
      reservedUntil:
          parseDateNullable(data['reserved_until'] ?? data['reservedUntil']),
      reservedBy: data['reserved_by'] ?? data['reservedBy'],
      price: price,
      priceType: priceType,
      blockedBy: data['blocked_by'] ?? data['blockedBy'],
      blockReason: data['block_reason'] ?? data['blockReason'],
      createdAt: parseDate(data['created_at'] ?? data['createdAt']),
    );
  }

  /// Convert to Supabase map.
  /// Phase 4 Iter 14 SM-09: include `id` when non-empty so upserts
  /// target the existing row instead of inserting a duplicate.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'turf_id': turfId,
      'date': date,
      'start_time': startTime,
      'end_time': endTime,
      'net_number': netNumber,
      'status': status.value,
      'reserved_until': reservedUntil?.toIso8601String(),
      'reserved_by': reservedBy,
      'price': price,
      'price_type': priceType,
      'blocked_by': blockedBy,
      'block_reason': blockReason,
      'created_at': createdAt.toIso8601String(),
    };
    if (slotId.isNotEmpty) map['id'] = slotId;
    return map;
  }

  /// Check if the slot is currently available for booking.
  /// Note: Expired reservations are handled server-side via RPC.
  /// Client treats reserved slots as unavailable until refreshed.
  bool get isAvailable {
    return status == SlotStatus.available;
  }

  /// Check if the slot might be bookable (available or expired reservation).
  /// Server-side RPC performs the authoritative check.
  /// Phase 4 Iter 14 SM-05: widen the "expired" check with a 30-second
  /// skew buffer since the device clock isn't trusted.
  static const Duration _clockSkewBuffer = Duration(seconds: 30);
  bool get isBookable {
    if (status == SlotStatus.available) return true;
    if (status == SlotStatus.reserved && reservedUntil != null) {
      return DateTime.now().isAfter(reservedUntil!.add(_clockSkewBuffer));
    }
    return false;
  }

  /// Get display time range (e.g., "06:00 PM - 07:00 PM")
  String get displayTimeRange {
    return '${_formatTime(startTime)} - ${_formatTime(endTime)}';
  }

  /// Phase 4 Iter 14 SM-02: regex-guard malformed input; SM-07: zero-pad hour.
  static final RegExp _timeHHMM = RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$');

  String _formatTime(String time24) {
    if (!_timeHHMM.hasMatch(time24)) return time24;
    final parts = time24.split(':');
    int hour = int.parse(parts[0]);
    final minute = parts[1];
    if (hour == 0 && minute == '00') {
      return '12:00 AM';
    }
    if (hour >= 24) hour = 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final paddedHour = displayHour.toString().padLeft(2, '0');
    return '$paddedHour:$minute $period';
  }

  /// Copy with modified fields.
  /// Phase 4 Iter 14 SM-06: [netNumber] is now preserved when callers
  /// want to re-assign a slot to another net (previously required full
  /// re-construction).
  SlotModel copyWith({
    int? netNumber,
    SlotStatus? status,
    DateTime? reservedUntil,
    String? reservedBy,
    double? price,
    String? priceType,
    String? blockedBy,
    String? blockReason,
  }) {
    return SlotModel(
      slotId: slotId,
      turfId: turfId,
      date: date,
      startTime: startTime,
      endTime: endTime,
      netNumber: netNumber ?? this.netNumber,
      status: status ?? this.status,
      reservedUntil: reservedUntil ?? this.reservedUntil,
      reservedBy: reservedBy ?? this.reservedBy,
      price: price ?? this.price,
      priceType: priceType ?? this.priceType,
      blockedBy: blockedBy ?? this.blockedBy,
      blockReason: blockReason ?? this.blockReason,
      createdAt: createdAt,
    );
  }

  @override
  String toString() {
    // Phase 4 Iter 14 SM-11: include turfId + price for support triage.
    return 'SlotModel(slotId: $slotId, turfId: $turfId, date: $date, '
        '$startTime-$endTime, net: $netNumber, price: $price, '
        'status: ${status.displayName})';
  }
}
