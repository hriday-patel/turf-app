import '../../data/models/turf_model.dart';
import '../constants/enums.dart';

/// Price Calculator Utility
/// Calculates slot prices based on pricing rules, date, and time
/// Uses the new pricing structure with nets and 4 time slots
class PriceCalculator {
  /// Phase 8 Iter 4 PRICE-05: single source of truth for the currency
  /// symbol so a future localization pass only edits this constant.
  static const String _currencySymbol = '₹';

  /// Phase 8 Iter 4 PRICE-06: shared day-type → DayTypePricing resolver
  /// used by both [calculateSlotPrice] and [getPriceForSlot].
  static DayTypePricing _dayTypePricingFor(
      NetPricing netPricing, DayType dayType) {
    switch (dayType) {
      case DayType.holiday:
        return netPricing.holiday;
      case DayType.weekend:
        return netPricing.weekend;
      case DayType.weekday:
        return netPricing.weekday;
    }
  }

  /// Phase 8 Iter 4 PRICE-06: flatten one [NetPricing] into all 12
  /// time-slot prices (3 day types × 4 time slots). Used by min/max
  /// price helpers.
  static List<double> _allPricesFor(NetPricing netPricing) => [
        netPricing.weekday.morning.price,
        netPricing.weekday.afternoon.price,
        netPricing.weekday.evening.price,
        netPricing.weekday.night.price,
        netPricing.weekend.morning.price,
        netPricing.weekend.afternoon.price,
        netPricing.weekend.evening.price,
        netPricing.weekend.night.price,
        netPricing.holiday.morning.price,
        netPricing.holiday.afternoon.price,
        netPricing.holiday.evening.price,
        netPricing.holiday.night.price,
      ];

  /// Calculate price for a slot (uses first net by default)
  static Map<String, dynamic> calculateSlotPrice({
    required PricingRules pricingRules,
    required String date,
    required String startTime,
    required List<String> publicHolidays,
    int netNumber = 1,
  }) {
    // Phase 8 Iter 4 PRICE-01: parse defensively so a malformed string
    // surfaces as a clear ArgumentError instead of an opaque
    // FormatException at deep call-site.
    final dateTime = DateTime.tryParse(date);
    if (dateTime == null) {
      throw ArgumentError.value(date, 'date', 'Expected ISO date (yyyy-MM-dd)');
    }
    final hourPart =
        startTime.split(':').isNotEmpty ? startTime.split(':')[0] : '';
    final hour = int.tryParse(hourPart);
    if (hour == null || hour < 0 || hour > 23) {
      throw ArgumentError.value(startTime, 'startTime', 'Expected HH:MM (24h)');
    }

    // Phase 8 Iter 4 PRICE-02: empty pricing list is unrecoverable here
    // (we cannot guess a price), so fail loudly so the caller can show a
    // proper error toast instead of a `Bad state: No element` crash.
    if (pricingRules.netPricing.isEmpty) {
      throw StateError('Turf has no pricing rules configured');
    }

    final dayOfWeek = dateTime.weekday; // 1 = Monday, 7 = Sunday

    // Check if it's a holiday
    final isHoliday = publicHolidays.contains(date);

    // Determine day type
    DayType dayType;
    if (isHoliday) {
      dayType = DayType.holiday;
    } else if (dayOfWeek == 6 || dayOfWeek == 7) {
      // Saturday or Sunday
      dayType = DayType.weekend;
    } else {
      dayType = DayType.weekday;
    }

    // Get the net pricing (default to first net if not found)
    final netPricing =
        pricingRules.getNetPricing(netNumber) ?? pricingRules.netPricing.first;

    final dayTypePricing = _dayTypePricingFor(netPricing, dayType);

    // Determine time slot based on START hour.
    // For slots spanning two periods (e.g., 11:30-13:00),
    // the price is determined by the period at slot start time.
    String timeSlot;
    double price;

    if (hour >= 6 && hour < 12) {
      timeSlot = 'MORNING';
      price = dayTypePricing.morning.price;
    } else if (hour >= 12 && hour < 18) {
      timeSlot = 'AFTERNOON';
      price = dayTypePricing.afternoon.price;
    } else if (hour >= 18 && hour < 24) {
      timeSlot = 'EVENING';
      price = dayTypePricing.evening.price;
    } else {
      // 0:00 - 5:59
      timeSlot = 'NIGHT';
      price = dayTypePricing.night.price;
    }

    // Generate price type string
    final priceType = '${dayType.value}_$timeSlot';

    return {
      'price': price,
      'priceType': priceType,
      'dayType': dayType,
      'timeSlot': timeSlot,
      'netNumber': netNumber,
    };
  }

  /// Get price for a specific time slot and day type
  static double getPriceForSlot({
    required PricingRules pricingRules,
    required DayType dayType,
    required String timeSlot,
    int netNumber = 1,
  }) {
    // Phase 8 Iter 4 PRICE-02: same loud failure as calculateSlotPrice.
    if (pricingRules.netPricing.isEmpty) {
      throw StateError('Turf has no pricing rules configured');
    }

    final netPricing =
        pricingRules.getNetPricing(netNumber) ?? pricingRules.netPricing.first;

    final dayTypePricing = _dayTypePricingFor(netPricing, dayType);

    switch (timeSlot.toUpperCase()) {
      case 'MORNING':
        return dayTypePricing.morning.price;
      case 'AFTERNOON':
        return dayTypePricing.afternoon.price;
      case 'EVENING':
        return dayTypePricing.evening.price;
      case 'NIGHT':
        return dayTypePricing.night.price;
      default:
        return dayTypePricing.morning.price;
    }
  }

  /// Get the minimum price across all slots for a turf (for display).
  /// Phase 8 Iter 4 PRICE-03: returns `0` only when there are zero
  /// configured nets — UI should hide the price chip in that case
  /// rather than render "₹0".
  static double getMinPrice(PricingRules pricingRules) {
    if (pricingRules.netPricing.isEmpty) return 0;
    double minPrice = double.infinity;

    for (final netPricing in pricingRules.netPricing) {
      for (final price in _allPricesFor(netPricing)) {
        if (price < minPrice) minPrice = price;
      }
    }

    return minPrice == double.infinity ? 0 : minPrice;
  }

  /// Get the maximum price across all slots for a turf (for display)
  static double getMaxPrice(PricingRules pricingRules) {
    if (pricingRules.netPricing.isEmpty) return 0;
    double maxPrice = 0;

    for (final netPricing in pricingRules.netPricing) {
      for (final price in _allPricesFor(netPricing)) {
        if (price > maxPrice) maxPrice = price;
      }
    }

    return maxPrice;
  }

  /// Format price for display.
  /// Phase 8 Iter 4 PRICE-04: NaN/Infinity/negative values are coerced
  /// to `0` so the UI never shows "₹NaN" / "₹Infinity" / "₹-100".
  static String formatPrice(double price) {
    if (price.isNaN || price.isInfinite || price < 0) {
      return '${_currencySymbol}0';
    }
    if (price == price.roundToDouble()) {
      return '$_currencySymbol${price.toInt()}';
    }
    return '$_currencySymbol${price.toStringAsFixed(2)}';
  }

  /// Get price range string for display
  static String getPriceRange(PricingRules pricingRules) {
    final minPrice = getMinPrice(pricingRules);
    final maxPrice = getMaxPrice(pricingRules);

    if (minPrice == maxPrice) {
      return formatPrice(minPrice);
    }
    return '${formatPrice(minPrice)} - ${formatPrice(maxPrice)}';
  }

  /// Get price label
  static String getPriceLabel(String priceType) {
    switch (priceType) {
      case 'WEEKDAY_MORNING':
        return 'Weekday (Morning)';
      case 'WEEKDAY_AFTERNOON':
        return 'Weekday (Afternoon)';
      case 'WEEKDAY_EVENING':
        return 'Weekday (Evening)';
      case 'WEEKDAY_NIGHT':
        return 'Weekday (Night)';
      case 'WEEKEND_MORNING':
        return 'Weekend (Morning)';
      case 'WEEKEND_AFTERNOON':
        return 'Weekend (Afternoon)';
      case 'WEEKEND_EVENING':
        return 'Weekend (Evening)';
      case 'WEEKEND_NIGHT':
        return 'Weekend (Night)';
      case 'HOLIDAY_MORNING':
        return 'Holiday (Morning)';
      case 'HOLIDAY_AFTERNOON':
        return 'Holiday (Afternoon)';
      case 'HOLIDAY_EVENING':
        return 'Holiday (Evening)';
      case 'HOLIDAY_NIGHT':
        return 'Holiday (Night)';
      default:
        return priceType;
    }
  }
}
