/// Phase 4 Iter 12 TM-11: data model for turfs / grounds. All parsing
/// entry points are defensive: malformed DB rows should degrade
/// gracefully rather than crash list/detail screens.
import '../../core/constants/enums.dart';

/// Canonical week order used for default days-open and sorting.
/// Phase 4 Iter 12 TM-08: single source of truth instead of 3 inline
/// duplicates.
const List<String> _defaultDaysOpen = <String>[
  'MON',
  'TUE',
  'WED',
  'THU',
  'FRI',
  'SAT',
  'SUN'
];

/// Matches 24h HH:MM (00:00..23:59). Phase 4 Iter 12 TM-06/TM-07.
final RegExp _timeHHMM = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

class TurfLocation {
  final double lat;
  final double lng;

  TurfLocation({required this.lat, required this.lng});

  /// Phase 4 Iter 12 TM-01: strict parser. Missing or non-numeric
  /// lat/lng returns null rather than silently producing `(0, 0)`
  /// (Null Island), which was previously indistinguishable from a
  /// legitimately dropped location.
  static TurfLocation? tryFromMap(Map<String, dynamic> map) {
    final rawLat = map['lat'];
    final rawLng = map['lng'];
    final lat = rawLat is num
        ? rawLat.toDouble()
        : double.tryParse(rawLat?.toString() ?? '');
    final lng = rawLng is num
        ? rawLng.toDouble()
        : double.tryParse(rawLng?.toString() ?? '');
    if (lat == null || lng == null) return null;
    if (lat.isNaN || lng.isNaN) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return TurfLocation(lat: lat, lng: lng);
  }

  /// Legacy non-null API retained for callers that already validated
  /// input. Prefer [tryFromMap].
  factory TurfLocation.fromMap(Map<String, dynamic> map) {
    return tryFromMap(map) ?? TurfLocation(lat: 0, lng: 0);
  }

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
      };
}

/// Time slot pricing for a specific period
class TimeSlotPricing {
  final String label; // "Morning", "Afternoon", "Evening", "Night"
  final String startTime; // "06:00"
  final String endTime; // "12:00"
  final double price;

  TimeSlotPricing({
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.price,
  });

  factory TimeSlotPricing.fromMap(Map<String, dynamic> map) {
    return TimeSlotPricing(
      label: map['label'] ?? '',
      startTime: map['start_time'] ?? map['start'] ?? '06:00',
      endTime: map['end_time'] ?? map['end'] ?? '12:00',
      price: (map['price'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'start_time': startTime,
      'end_time': endTime,
      'price': price,
    };
  }
}

/// Day type pricing (contains 4 time slots)
class DayTypePricing {
  final TimeSlotPricing morning; // 6:00 AM - 12:00 PM
  final TimeSlotPricing afternoon; // 12:00 PM - 6:00 PM
  final TimeSlotPricing evening; // 6:00 PM - 12:00 AM
  final TimeSlotPricing night; // 12:00 AM - 6:00 AM

  DayTypePricing({
    required this.morning,
    required this.afternoon,
    required this.evening,
    required this.night,
  });

  factory DayTypePricing.fromMap(Map<String, dynamic> map) {
    // Handle legacy format
    if (map.containsKey('day') && map.containsKey('night')) {
      final dayPrice = (map['day']?['price'] ?? 1000).toDouble();
      final nightPrice = (map['night']?['price'] ?? 1200).toDouble();
      return DayTypePricing(
        morning: TimeSlotPricing(
            label: 'Morning',
            startTime: '06:00',
            endTime: '12:00',
            price: dayPrice),
        afternoon: TimeSlotPricing(
            label: 'Afternoon',
            startTime: '12:00',
            endTime: '18:00',
            price: dayPrice),
        evening: TimeSlotPricing(
            label: 'Evening',
            startTime: '18:00',
            endTime: '00:00',
            price: nightPrice),
        night: TimeSlotPricing(
            label: 'Night',
            startTime: '00:00',
            endTime: '06:00',
            price: nightPrice),
      );
    }
    return DayTypePricing(
      morning: TimeSlotPricing.fromMap(map['morning'] ?? {}),
      afternoon: TimeSlotPricing.fromMap(map['afternoon'] ?? {}),
      evening: TimeSlotPricing.fromMap(map['evening'] ?? {}),
      night: TimeSlotPricing.fromMap(map['night'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'morning': morning.toMap(),
      'afternoon': afternoon.toMap(),
      'evening': evening.toMap(),
      'night': night.toMap(),
    };
  }

  /// Get price for a specific time.
  /// Phase 4 Iter 12 TM-06: validates `HH:MM`. Malformed input falls
  /// back to the morning price (a safer neutral default than night,
  /// which is typically the cheapest slot and was masking data bugs
  /// as "free night pricing").
  double getPriceForTime(String time) {
    if (!_timeHHMM.hasMatch(time)) return morning.price;
    final hour = int.parse(time.split(':')[0]);
    if (hour >= 6 && hour < 12) return morning.price;
    if (hour >= 12 && hour < 18) return afternoon.price;
    if (hour >= 18 && hour < 24) return evening.price;
    return night.price; // 0-6
  }

  factory DayTypePricing.defaultPricing({double basePrice = 1000}) {
    return DayTypePricing(
      morning: TimeSlotPricing(
          label: 'Morning',
          startTime: '06:00',
          endTime: '12:00',
          price: basePrice),
      afternoon: TimeSlotPricing(
          label: 'Afternoon',
          startTime: '12:00',
          endTime: '18:00',
          price: basePrice),
      evening: TimeSlotPricing(
          label: 'Evening',
          startTime: '18:00',
          endTime: '00:00',
          price: basePrice * 1.2),
      night: TimeSlotPricing(
          label: 'Night',
          startTime: '00:00',
          endTime: '06:00',
          price: basePrice * 1.1),
    );
  }
}

/// Net/Box pricing (each net can have different pricing)
class NetPricing {
  final int netNumber; // 1, 2, 3, etc.
  final String netName; // "Net 1", "Box A", etc.
  final DayTypePricing weekday;
  final DayTypePricing weekend;
  final DayTypePricing holiday;

  NetPricing({
    required this.netNumber,
    required this.netName,
    required this.weekday,
    required this.weekend,
    required this.holiday,
  });

  factory NetPricing.fromMap(Map<String, dynamic> map) {
    return NetPricing(
      netNumber: map['net_number'] ?? map['netNumber'] ?? 1,
      netName: map['net_name'] ?? map['netName'] ?? 'Net 1',
      weekday: DayTypePricing.fromMap(map['weekday'] ?? {}),
      weekend: DayTypePricing.fromMap(map['weekend'] ?? {}),
      holiday: DayTypePricing.fromMap(map['holiday'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'net_number': netNumber,
      'net_name': netName,
      'weekday': weekday.toMap(),
      'weekend': weekend.toMap(),
      'holiday': holiday.toMap(),
    };
  }

  factory NetPricing.defaultForNet(int netNumber, {double basePrice = 1000}) {
    return NetPricing(
      netNumber: netNumber,
      netName: 'Net $netNumber',
      weekday: DayTypePricing.defaultPricing(basePrice: basePrice),
      weekend: DayTypePricing.defaultPricing(basePrice: basePrice * 1.3),
      holiday: DayTypePricing.defaultPricing(basePrice: basePrice * 1.5),
    );
  }
}

/// Complete pricing rules for a turf (with all nets)
class PricingRules {
  final List<NetPricing> netPricing;

  PricingRules({required this.netPricing});

  factory PricingRules.fromMap(Map<String, dynamic> map) {
    // Handle new format with nets
    if (map.containsKey('nets') || map.containsKey('netPricing')) {
      final netsList = map['nets'] ?? map['netPricing'] ?? [];
      return PricingRules(
        netPricing: (netsList as List)
            .map((e) => NetPricing.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
    }

    // Handle legacy format (convert to single net)
    final weekdayData = map['weekday'] ?? {};
    final saturdayData = map['saturday'] ?? map['weekend'] ?? {};
    final holidayData = map['holiday'] ?? {};

    return PricingRules(
      netPricing: [
        NetPricing(
          netNumber: 1,
          netName: 'Net 1',
          weekday: DayTypePricing.fromMap(weekdayData),
          weekend: DayTypePricing.fromMap(saturdayData),
          holiday: DayTypePricing.fromMap(holidayData),
        ),
      ],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nets': netPricing.map((e) => e.toMap()).toList(),
    };
  }

  /// Get pricing for a specific net by number
  NetPricing? getNetPricing(int netNumber) {
    try {
      return netPricing.firstWhere((n) => n.netNumber == netNumber);
    } catch (e) {
      return netPricing.isNotEmpty ? netPricing.first : null;
    }
  }

  /// Get default pricing rules for N nets
  factory PricingRules.defaultRules(
      {int numberOfNets = 1, double basePrice = 1000}) {
    return PricingRules(
      netPricing: List.generate(
        numberOfNets,
        (i) => NetPricing.defaultForNet(i + 1, basePrice: basePrice),
      ),
    );
  }

  /// Get pricing for a specific net, day type, and time.
  /// Phase 4 Iter 12 TM-02: returns `0` instead of throwing
  /// `StateError` when [netPricing] is empty. Callers should treat
  /// zero as "pricing unavailable" and fall back to UI error state.
  double getPrice(
      {required int netNumber, required String dayType, required String time}) {
    if (netPricing.isEmpty) return 0;
    final net = netPricing.firstWhere(
      (n) => n.netNumber == netNumber,
      orElse: () => netPricing.first,
    );

    DayTypePricing dayPricing;
    switch (dayType.toLowerCase()) {
      case 'weekend':
      case 'saturday':
      case 'sunday':
        dayPricing = net.weekend;
        break;
      case 'holiday':
        dayPricing = net.holiday;
        break;
      default:
        dayPricing = net.weekday;
    }

    return dayPricing.getPriceForTime(time);
  }
}

// Legacy support classes
@Deprecated('Use PricingRules / DayTypePricing / TimeSlotPricing instead')
class PricingRule {
  final String start;
  final String end;
  final double price;

  PricingRule({required this.start, required this.end, required this.price});

  factory PricingRule.fromMap(Map<String, dynamic> map) {
    return PricingRule(
      start: map['start'] ?? '06:00',
      end: map['end'] ?? '18:00',
      price: (map['price'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {'start': start, 'end': end, 'price': price};
}

@Deprecated('Use DayTypePricing instead')
class DayPricing {
  final PricingRule day;
  final PricingRule night;

  DayPricing({required this.day, required this.night});

  factory DayPricing.fromMap(Map<String, dynamic> map) {
    return DayPricing(
      day: PricingRule.fromMap(map['day'] ?? {}),
      night: PricingRule.fromMap(map['night'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() => {'day': day.toMap(), 'night': night.toMap()};
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

  /// Check if this image has a valid URL
  bool get isValid => url.isNotEmpty && _isValidUrl(url);

  /// Validate URL format
  static bool _isValidUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  factory TurfImage.fromMap(Map<String, dynamic> map) {
    final urlValue = map['url']?.toString() ?? '';
    return TurfImage(
      url: urlValue,
      type: _parseImageType(map['type']),
      isPrimary: map['isPrimary'] == true || map['is_primary'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'type': type.value,
      'isPrimary': isPrimary,
    };
  }

  /// Create a copy with modified primary status
  TurfImage copyWith({bool? isPrimary}) {
    return TurfImage(
      url: url,
      type: type,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  /// Phase 4 Iter 12 TM-05: case-insensitive so legacy rows stored as
  /// `'ground'` / `'night_lights'` keep their type metadata instead of
  /// silently degrading to `other`.
  static TurfImageType _parseImageType(String? type) {
    switch (type?.toUpperCase()) {
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
  final int numberOfNets; // Number of nets/boxes

  // Operational Details
  final String openTime;
  final String closeTime;
  final int slotDurationMinutes;
  final List<String> daysOpen;
  final TurfStatus status; // Open, Closed, Renovation
  final List<int> renovationNetNumbers; // Nets closed when status is renovation

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
    this.numberOfNets = 1,
    required this.openTime,
    required this.closeTime,
    this.slotDurationMinutes = 60,
    this.daysOpen = const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'],
    this.status = TurfStatus.open,
    this.renovationNetNumbers = const [],
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
    // Phase 4 Iter 12 TM-03: tolerate malformed date strings from
    // legacy rows instead of letting them crash list fetches.
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    // Phase 4 Iter 12 TM-07: fall back to a safe default for invalid
    // open/close times rather than propagating `"25:99"` into slot
    // generators.
    String parseTime(dynamic value, String fallback) {
      final s = value?.toString() ?? '';
      return _timeHHMM.hasMatch(s) ? s : fallback;
    }

    List<int> parseRenovationNets(dynamic value) {
      if (value is! List) return const <int>[];
      return value
          .cast<dynamic>()
          .map<int>((dynamic e) => int.tryParse(e.toString()) ?? 0)
          .where((int n) => n > 0)
          .toSet()
          .toList()
        ..sort();
    }

    List<int> parseRenovationNetsWithFallback() {
      final fromColumn = parseRenovationNets(
        data['renovation_net_numbers'] ?? data['renovationNetNumbers'],
      );
      if (fromColumn.isNotEmpty) return fromColumn;

      final pricingRulesData = data['pricing_rules'] ?? data['pricingRules'];
      if (pricingRulesData is Map) {
        final fallbackValue = pricingRulesData['renovation_net_numbers'];
        return parseRenovationNets(fallbackValue);
      }

      return const <int>[];
    }

    String? normalizeDayCode(dynamic value) {
      if (value == null) return null;
      final raw = value.toString().trim();
      if (raw.isEmpty) return null;

      final upper = raw.toUpperCase();
      final lettersOnly = upper.replaceAll(RegExp(r'[^A-Z]'), '');
      final code =
          lettersOnly.length >= 3 ? lettersOnly.substring(0, 3) : lettersOnly;

      switch (code) {
        case 'MON':
          return 'MON';
        case 'TUE':
          return 'TUE';
        case 'WED':
          return 'WED';
        case 'THU':
          return 'THU';
        case 'FRI':
          return 'FRI';
        case 'SAT':
          return 'SAT';
        case 'SUN':
          return 'SUN';
        default:
          return null;
      }
    }

    List<String> parseDaysOpen(dynamic value) {
      // Phase 4 Iter 12 TM-08: use shared _defaultDaysOpen.
      final source = value is List ? value : _defaultDaysOpen;

      final normalized =
          source.map(normalizeDayCode).whereType<String>().toSet().toList();

      normalized.sort((a, b) =>
          _defaultDaysOpen.indexOf(a).compareTo(_defaultDaysOpen.indexOf(b)));

      return normalized.isEmpty
          ? List<String>.from(_defaultDaysOpen)
          : normalized;
    }

    // Phase 4 Iter 12 TM-04: guard against 0/negative net counts from
    // legacy or partially-migrated rows.
    final rawNets = data['number_of_nets'] ?? data['numberOfNets'] ?? 1;
    final nets =
        rawNets is int ? rawNets : int.tryParse(rawNets.toString()) ?? 1;
    final safeNets = nets < 1 ? 1 : nets;

    return TurfModel(
      turfId: data['id'] ?? data['turfId'] ?? '',
      ownerId: data['owner_id'] ?? data['ownerId'] ?? '',
      turfName: data['turf_name'] ?? data['turfName'] ?? '',
      city: data['city'] ?? '',
      address: data['address'] ?? '',
      // Phase 4 Iter 12 TM-01: invalid location maps become null
      // instead of the Null-Island stand-in.
      location: data['location'] is Map
          ? TurfLocation.tryFromMap(Map<String, dynamic>.from(data['location']))
          : null,
      turfType: TurfTypeExtension.fromString(
          data['turf_type'] ?? data['turfType'] ?? 'BOX_CRICKET'),
      description: data['description'],
      numberOfNets: safeNets,
      openTime: parseTime(data['open_time'] ?? data['openTime'], '06:00'),
      closeTime: parseTime(data['close_time'] ?? data['closeTime'], '23:00'),
      slotDurationMinutes:
          data['slot_duration_minutes'] ?? data['slotDurationMinutes'] ?? 60,
      daysOpen: parseDaysOpen(data['days_open'] ?? data['daysOpen']),
      status: TurfStatusExtension.fromString(data['status'] ?? 'OPEN'),
      renovationNetNumbers: parseRenovationNetsWithFallback(),
      pricingRules: PricingRules.fromMap(
          data['pricing_rules'] ?? data['pricingRules'] ?? {}),
      publicHolidays: List<String>.from(
          data['public_holidays'] ?? data['publicHolidays'] ?? []),
      images: _parseImages(data['images']),
      isApproved: data['is_approved'] ?? data['isApproved'] ?? false,
      verificationStatus: VerificationStatusExtension.fromString(
          data['verification_status'] ??
              data['verificationStatus'] ??
              'PENDING'),
      rejectionReason: data['rejection_reason'] ?? data['rejectionReason'],
      createdAt: parseDate(data['created_at'] ?? data['createdAt']),
      updatedAt: data['updated_at'] != null || data['updatedAt'] != null
          ? parseDate(data['updated_at'] ?? data['updatedAt'])
          : null,
    );
  }

  /// Parse and filter images, removing invalid ones
  static List<TurfImage> _parseImages(dynamic imagesData) {
    if (imagesData == null) return [];
    if (imagesData is! List) return [];

    final List<TurfImage> result = [];
    for (final item in imagesData) {
      if (item is Map<String, dynamic>) {
        final image = TurfImage.fromMap(item);
        // Only include images with valid URLs
        if (image.isValid) {
          result.add(image);
        }
      }
    }
    return result;
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
      'number_of_nets': numberOfNets,
      'open_time': openTime,
      'close_time': closeTime,
      'slot_duration_minutes': slotDurationMinutes,
      'days_open': daysOpen,
      'status': status.value,
      'renovation_net_numbers': renovationNetNumbers,
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

  /// Phase 4 Iter 12 TM-09: single filtered pass over [images];
  /// [primaryImageUrl] and [validImageUrls] share this list instead of
  /// each re-scanning the full collection on every rebuild.
  List<TurfImage> get validImages =>
      images.where((img) => img.isValid).toList(growable: false);

  /// Get primary image URL (only returns valid URLs)
  String? get primaryImageUrl {
    final valid = validImages;
    for (final img in valid) {
      if (img.isPrimary) return img.url;
    }
    return valid.isEmpty ? null : valid.first.url;
  }

  /// Get all valid image URLs
  List<String> get validImageUrls =>
      validImages.map((img) => img.url).toList(growable: false);

  /// Copy with modified fields
  TurfModel copyWith({
    String? turfName,
    String? city,
    String? address,
    TurfLocation? location,
    TurfType? turfType,
    String? description,
    int? numberOfNets,
    String? openTime,
    String? closeTime,
    int? slotDurationMinutes,
    List<String>? daysOpen,
    TurfStatus? status,
    List<int>? renovationNetNumbers,
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
      numberOfNets: numberOfNets ?? this.numberOfNets,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      slotDurationMinutes: slotDurationMinutes ?? this.slotDurationMinutes,
      daysOpen: daysOpen ?? this.daysOpen,
      status: status ?? this.status,
      renovationNetNumbers: renovationNetNumbers ?? this.renovationNetNumbers,
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
    // Phase 4 Iter 12 TM-11: include ownerId for owner-scoped debug logs.
    return 'TurfModel(turfId: $turfId, ownerId: $ownerId, turfName: $turfName, city: $city, nets: $numberOfNets)';
  }
}
