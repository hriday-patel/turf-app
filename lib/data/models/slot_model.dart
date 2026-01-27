import '../../core/constants/enums.dart';

/// Slot model representing a time slot for booking
class SlotModel {
  final String slotId;
  final String turfId;
  
  // Time Information
  final String date;        // "2026-01-27"
  final String startTime;   // "18:00"
  final String endTime;     // "19:00"
  
  // Status
  final SlotStatus status;
  
  // Reservation Tracking
  final DateTime? reservedUntil;
  final String? reservedBy;
  
  // Pricing
  final double price;
  final String priceType;   // "WEEKDAY_NIGHT"
  
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
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) return DateTime.parse(value);
      return DateTime.now();
    }

    return SlotModel(
      slotId: data['id'] ?? data['slotId'] ?? '',
      turfId: data['turf_id'] ?? data['turfId'] ?? '',
      date: data['date'] ?? '',
      startTime: data['start_time'] ?? data['startTime'] ?? '',
      endTime: data['end_time'] ?? data['endTime'] ?? '',
      status: SlotStatusExtension.fromString(data['status'] ?? 'AVAILABLE'),
      reservedUntil: data['reserved_until'] != null || data['reservedUntil'] != null
          ? parseDate(data['reserved_until'] ?? data['reservedUntil'])
          : null,
      reservedBy: data['reserved_by'] ?? data['reservedBy'],
      price: (data['price'] ?? 0).toDouble(),
      priceType: data['price_type'] ?? data['priceType'] ?? '',
      blockedBy: data['blocked_by'] ?? data['blockedBy'],
      blockReason: data['block_reason'] ?? data['blockReason'],
      createdAt: parseDate(data['created_at'] ?? data['createdAt']),
    );
  }

  /// Convert to Supabase map
  Map<String, dynamic> toMap() {
    return {
      'turf_id': turfId,
      'date': date,
      'start_time': startTime,
      'end_time': endTime,
      'status': status.value,
      'reserved_until': reservedUntil?.toIso8601String(),
      'reserved_by': reservedBy,
      'price': price,
      'price_type': priceType,
      'blocked_by': blockedBy,
      'block_reason': blockReason,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Check if the slot is currently available for booking
  bool get isAvailable {
    if (status == SlotStatus.available) return true;
    
    // Check if reservation has expired
    if (status == SlotStatus.reserved && reservedUntil != null) {
      return DateTime.now().isAfter(reservedUntil!);
    }
    
    return false;
  }

  /// Check if the slot is bookable (available or expired reservation)
  bool get isBookable {
    return status == SlotStatus.available || 
           (status == SlotStatus.reserved && 
            reservedUntil != null && 
            DateTime.now().isAfter(reservedUntil!));
  }

  /// Get display time range (e.g., "6:00 PM - 7:00 PM")
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

  /// Copy with modified fields
  SlotModel copyWith({
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
    return 'SlotModel(slotId: $slotId, date: $date, $startTime-$endTime, status: ${status.displayName})';
  }
}
