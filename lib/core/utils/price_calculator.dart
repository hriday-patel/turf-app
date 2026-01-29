import '../../data/models/turf_model.dart';
import '../constants/enums.dart';

/// Price Calculator Utility
/// Calculates slot prices based on pricing rules, date, and time
/// Uses the new pricing structure with nets and 4 time slots
class PriceCalculator {
  /// Calculate price for a slot (uses first net by default)
  static Map<String, dynamic> calculateSlotPrice({
    required PricingRules pricingRules,
    required String date,
    required String startTime,
    required List<String> publicHolidays,
    int netNumber = 1,
  }) {
    // Parse date to determine day type
    final dateTime = DateTime.parse(date);
    final dayOfWeek = dateTime.weekday; // 1 = Monday, 7 = Sunday
    
    // Check if it's a holiday
    final isHoliday = publicHolidays.contains(date);
    
    // Determine day type
    DayType dayType;
    if (isHoliday) {
      dayType = DayType.holiday;
    } else if (dayOfWeek == 6 || dayOfWeek == 7) { // Saturday or Sunday
      dayType = DayType.weekend;
    } else {
      dayType = DayType.weekday;
    }
    
    // Get the net pricing (default to first net if not found)
    final netPricing = pricingRules.getNetPricing(netNumber) ?? 
                       pricingRules.netPricing.first;
    
    // Get pricing for the day type
    DayTypePricing dayTypePricing;
    switch (dayType) {
      case DayType.holiday:
        dayTypePricing = netPricing.holiday;
        break;
      case DayType.weekend:
        dayTypePricing = netPricing.weekend;
        break;
      case DayType.weekday:
        dayTypePricing = netPricing.weekday;
        break;
    }
    
    // Parse start time
    final hour = int.parse(startTime.split(':')[0]);
    
    // Determine time slot based on hour
    String timeSlot;
    double price;
    
    if (hour >= 6 && hour < 12) {
      timeSlot = 'MORNING';
      price = dayTypePricing.morning.price;
    } else if (hour >= 12 && hour < 18) {
      timeSlot = 'AFTERNOON';
      price = dayTypePricing.afternoon.price;
    } else if (hour >= 18 || hour < 0) {
      timeSlot = 'EVENING';
      price = dayTypePricing.evening.price;
    } else {
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
    final netPricing = pricingRules.getNetPricing(netNumber) ?? 
                       pricingRules.netPricing.first;
    
    DayTypePricing dayTypePricing;
    switch (dayType) {
      case DayType.holiday:
        dayTypePricing = netPricing.holiday;
        break;
      case DayType.weekend:
        dayTypePricing = netPricing.weekend;
        break;
      case DayType.weekday:
        dayTypePricing = netPricing.weekday;
        break;
    }
    
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
  
  /// Get the minimum price across all slots for a turf (for display)
  static double getMinPrice(PricingRules pricingRules) {
    double minPrice = double.infinity;
    
    for (final netPricing in pricingRules.netPricing) {
      final prices = [
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
      
      for (final price in prices) {
        if (price < minPrice) minPrice = price;
      }
    }
    
    return minPrice == double.infinity ? 0 : minPrice;
  }
  
  /// Get the maximum price across all slots for a turf (for display)
  static double getMaxPrice(PricingRules pricingRules) {
    double maxPrice = 0;
    
    for (final netPricing in pricingRules.netPricing) {
      final prices = [
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
      
      for (final price in prices) {
        if (price > maxPrice) maxPrice = price;
      }
    }
    
    return maxPrice;
  }
  
  /// Format price for display
  static String formatPrice(double price) {
    if (price == price.roundToDouble()) {
      return '₹${price.toInt()}';
    }
    return '₹${price.toStringAsFixed(2)}';
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

