import '../../../data/models/turf_model.dart';
import '../constants/enums.dart';

/// Price Calculator Utility
/// Calculates slot prices based on pricing rules, date, and time
class PriceCalculator {
  /// Calculate price for a slot
  static Map<String, dynamic> calculateSlotPrice({
    required PricingRules pricingRules,
    required String date,
    required String startTime,
    required List<String> publicHolidays,
  }) {
    // Parse date to determine day type
    final dateTime = DateTime.parse(date);
    final dayOfWeek = dateTime.weekday; // 1 = Monday, 7 = Sunday
    
    // Check if it's a holiday
    final isHoliday = publicHolidays.contains(date);
    
    // Determine day type (Saturday and Sunday are now separate)
    DayType dayType;
    if (isHoliday) {
      dayType = DayType.holiday;
    } else if (dayOfWeek == 6) { // Saturday
      dayType = DayType.saturday;
    } else if (dayOfWeek == 7) { // Sunday
      dayType = DayType.sunday;
    } else {
      dayType = DayType.weekday;
    }
    
    // Get pricing for the day type
    DayPricing dayPricing;
    switch (dayType) {
      case DayType.holiday:
        dayPricing = pricingRules.holiday;
        break;
      case DayType.saturday:
        dayPricing = pricingRules.saturday;
        break;
      case DayType.sunday:
        dayPricing = pricingRules.sunday;
        break;
      case DayType.weekday:
        dayPricing = pricingRules.weekday;
        break;
    }
    
    // Parse start time
    final hour = int.parse(startTime.split(':')[0]);
    
    // Determine if it's day or night based on the pricing rule times
    final dayEndHour = int.parse(dayPricing.day.end.split(':')[0]);
    
    // Check if the slot falls in day or night time
    TimeType timeType;
    double price;
    
    if (hour < dayEndHour) {
      timeType = TimeType.day;
      price = dayPricing.day.price;
    } else {
      timeType = TimeType.night;
      price = dayPricing.night.price;
    }
    
    // Generate price type string
    final priceType = '${dayType.value}_${timeType.name.toUpperCase()}';
    
    return {
      'price': price,
      'priceType': priceType,
      'dayType': dayType,
      'timeType': timeType,
    };
  }
  
  /// Format price for display
  static String formatPrice(double price) {
    if (price == price.roundToDouble()) {
      return '₹${price.toInt()}';
    }
    return '₹${price.toStringAsFixed(2)}';
  }
  
  /// Get price label
  static String getPriceLabel(String priceType) {
    switch (priceType) {
      case 'WEEKDAY_DAY':
        return 'Weekday (Day)';
      case 'WEEKDAY_NIGHT':
        return 'Weekday (Night)';
      case 'SATURDAY_DAY':
        return 'Saturday (Day)';
      case 'SATURDAY_NIGHT':
        return 'Saturday (Night)';
      case 'SUNDAY_DAY':
        return 'Sunday (Day)';
      case 'SUNDAY_NIGHT':
        return 'Sunday (Night)';
      case 'HOLIDAY_DAY':
        return 'Holiday (Day)';
      case 'HOLIDAY_NIGHT':
        return 'Holiday (Night)';
      // Backward compatibility
      case 'WEEKEND_DAY':
        return 'Weekend (Day)';
      case 'WEEKEND_NIGHT':
        return 'Weekend (Night)';
      default:
        return priceType;
    }
  }
}

