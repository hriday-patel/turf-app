import '../../core/constants/enums.dart';

class TurfLocation {
  final double lat;
  final double lng;

  TurfLocation({required this.lat, required this.lng});

  factory TurfLocation.fromMap(Map<String, dynamic> map) {
    return TurfLocation(
      lat: (map['lat'] ?? 0).toDouble(),
      lng: (map['lng'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
      };
}

/// Pricing rule for a specific day/time combination
class PricingRule {
  final String start;  // "06:00"
  final String end;    // "18:00"
  final double price;   // 1000

  PricingRule({
    required this.start,
    required this.end,
    required this.price,
  });

  factory PricingRule.fromMap(Map<String, dynamic> map) {
    return PricingRule(
      start: map['start'] ?? '06:00',
      end: map['end'] ?? '18:00',
      price: (map['price'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'start': start,
      'end': end,
      'price': price,
    };
  }
}

/// Day pricing containing day and night rates
class DayPricing {
  final PricingRule day;
  final PricingRule night;

  DayPricing({
    required this.day,
    required this.night,
  });

  factory DayPricing.fromMap(Map<String, dynamic> map) {
    return DayPricing(
      day: PricingRule.fromMap(map['day'] ?? {}),
      night: PricingRule.fromMap(map['night'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'day': day.toMap(),
      'night': night.toMap(),
    };
  }
}

/// Complete pricing rules for a turf
class PricingRules {
  final DayPricing weekday;
  final DayPricing saturday;
  final DayPricing sunday;
  final DayPricing holiday;

  PricingRules({
    required this.weekday,
    required this.saturday,
    required this.sunday,
    required this.holiday,
  });

  factory PricingRules.fromMap(Map<String, dynamic> map) {
    // Handle backward compatibility with old 'weekend' field
    final saturdayData = map['saturday'] ?? map['weekend'] ?? {};
    final sundayData = map['sunday'] ?? map['weekend'] ?? {};
    
    return PricingRules(
      weekday: DayPricing.fromMap(map['weekday'] ?? {}),
      saturday: DayPricing.fromMap(saturdayData),
      sunday: DayPricing.fromMap(sundayData),
      holiday: DayPricing.fromMap(map['holiday'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'weekday': weekday.toMap(),
      'saturday': saturday.toMap(),
      'sunday': sunday.toMap(),
      'holiday': holiday.toMap(),
    };
  }

  /// Get default pricing rules
  factory PricingRules.defaultRules() {
    return PricingRules(
      weekday: DayPricing(
        day: PricingRule(start: '06:00', end: '18:00', price: 1000),
        night: PricingRule(start: '18:00', end: '23:00', price: 1200),
      ),
      saturday: DayPricing(
        day: PricingRule(start: '06:00', end: '18:00', price: 1400),
        night: PricingRule(start: '18:00', end: '23:00', price: 1600),
      ),
      sunday: DayPricing(
        day: PricingRule(start: '06:00', end: '18:00', price: 1500),
        night: PricingRule(start: '18:00', end: '23:00', price: 1700),
      ),
      holiday: DayPricing(
        day: PricingRule(start: '06:00', end: '18:00', price: 1800),
        night: PricingRule(start: '18:00', end: '23:00', price: 2000),
      ),
    );
  }
}

/// Turf image with metadata
class TurfImage {
  final String url;
  final TurfImageType type;
  final bool isPrimary;

  TurfImage({
    required this.url,
    required this.type,
    this.isPrimary = false,
  });

  factory TurfImage.fromMap(Map<String, dynamic> map) {
    return TurfImage(
      url: map['url'] ?? '',
      type: _parseImageType(map['type']),
      isPrimary: map['isPrimary'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'type': type.value,
      'isPrimary': isPrimary,
    };
  }

  static TurfImageType _parseImageType(String? type) {
    switch (type) {
      case 'GROUND':
        return TurfImageType.ground;
      case 'NIGHT_LIGHTS':
        return TurfImageType.nightLights;
      case 'FACILITY':
        return TurfImageType.facility;
      default:
        return TurfImageType.other;
    }
  }
}

/// Main Turf model representing a turf/ground
class TurfModel {
  final String turfId;
  final String ownerId;
  
  // Basic Details
  final String turfName;
  final String city;
  final String address;
  final TurfLocation? location;
  final TurfType turfType;
  final String? description;
  
  // Operational Details
  final String openTime;
  final String closeTime;
  final int slotDurationMinutes;
  final List<String> daysOpen;
  
  // Pricing
  final PricingRules pricingRules;
  final List<String> publicHolidays;
  
  // Images
  final List<TurfImage> images;
  
  // Verification Status
  final bool isApproved;
  final VerificationStatus verificationStatus;
  final String? rejectionReason;
  
  // Metadata
  final DateTime createdAt;
  final DateTime? updatedAt;

  TurfModel({
    required this.turfId,
    required this.ownerId,
    required this.turfName,
    required this.city,
    required this.address,
    this.location,
    required this.turfType,
    this.description,
    required this.openTime,
    required this.closeTime,
    this.slotDurationMinutes = 60,
    this.daysOpen = const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'],
    required this.pricingRules,
    this.publicHolidays = const [],
    this.images = const [],
    this.isApproved = false,
    this.verificationStatus = VerificationStatus.pending,
    this.rejectionReason,
    required this.createdAt,
    this.updatedAt,
  });

  /// Create from Supabase map
  factory TurfModel.fromMap(Map<String, dynamic> data) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) return DateTime.parse(value);
      return DateTime.now();
    }

    return TurfModel(
      turfId: data['id'] ?? data['turfId'] ?? '',
      ownerId: data['owner_id'] ?? data['ownerId'] ?? '',
      turfName: data['turf_name'] ?? data['turfName'] ?? '',
      city: data['city'] ?? '',
      address: data['address'] ?? '',
      location: data['location'] != null
          ? TurfLocation.fromMap(Map<String, dynamic>.from(data['location']))
          : null,
      turfType: TurfTypeExtension.fromString(data['turf_type'] ?? data['turfType'] ?? 'BOX_CRICKET'),
      description: data['description'],
      openTime: data['open_time'] ?? data['openTime'] ?? '06:00',
      closeTime: data['close_time'] ?? data['closeTime'] ?? '23:00',
      slotDurationMinutes: data['slot_duration_minutes'] ?? data['slotDurationMinutes'] ?? 60,
      daysOpen: List<String>.from(data['days_open'] ?? data['daysOpen'] ?? ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']),
      pricingRules: PricingRules.fromMap(data['pricing_rules'] ?? data['pricingRules'] ?? {}),
      publicHolidays: List<String>.from(data['public_holidays'] ?? data['publicHolidays'] ?? []),
      images: (data['images'] as List<dynamic>?)
          ?.map((e) => TurfImage.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
      isApproved: data['is_approved'] ?? data['isApproved'] ?? false,
      verificationStatus: VerificationStatusExtension.fromString(data['verification_status'] ?? data['verificationStatus'] ?? 'PENDING'),
      rejectionReason: data['rejection_reason'] ?? data['rejectionReason'],
      createdAt: parseDate(data['created_at'] ?? data['createdAt']),
      updatedAt: data['updated_at'] != null || data['updatedAt'] != null
          ? parseDate(data['updated_at'] ?? data['updatedAt'])
          : null,
    );
  }

  /// Convert to Supabase map
  Map<String, dynamic> toMap() {
    return {
      'owner_id': ownerId,
      'turf_name': turfName,
      'city': city,
      'address': address,
      'location': location?.toMap(),
      'turf_type': turfType.value,
      'description': description,
      'open_time': openTime,
      'close_time': closeTime,
      'slot_duration_minutes': slotDurationMinutes,
      'days_open': daysOpen,
      'pricing_rules': pricingRules.toMap(),
      'public_holidays': publicHolidays,
      'images': images.map((e) => e.toMap()).toList(),
      'is_approved': isApproved,
      'verification_status': verificationStatus.value,
      'rejection_reason': rejectionReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Get primary image URL
  String? get primaryImageUrl {
    final primary = images.where((img) => img.isPrimary).firstOrNull;
    return primary?.url ?? images.firstOrNull?.url;
  }

  /// Copy with modified fields
  TurfModel copyWith({
    String? turfName,
    String? city,
    String? address,
    TurfLocation? location,
    TurfType? turfType,
    String? description,
    String? openTime,
    String? closeTime,
    int? slotDurationMinutes,
    List<String>? daysOpen,
    PricingRules? pricingRules,
    List<String>? publicHolidays,
    List<TurfImage>? images,
    bool? isApproved,
    VerificationStatus? verificationStatus,
    String? rejectionReason,
    DateTime? updatedAt,
  }) {
    return TurfModel(
      turfId: turfId,
      ownerId: ownerId,
      turfName: turfName ?? this.turfName,
      city: city ?? this.city,
      address: address ?? this.address,
      location: location ?? this.location,
      turfType: turfType ?? this.turfType,
      description: description ?? this.description,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      slotDurationMinutes: slotDurationMinutes ?? this.slotDurationMinutes,
      daysOpen: daysOpen ?? this.daysOpen,
      pricingRules: pricingRules ?? this.pricingRules,
      publicHolidays: publicHolidays ?? this.publicHolidays,
      images: images ?? this.images,
      isApproved: isApproved ?? this.isApproved,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'TurfModel(turfId: $turfId, turfName: $turfName, city: $city)';
  }
}
