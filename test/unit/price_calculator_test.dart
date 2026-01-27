import 'package:flutter_test/flutter_test.dart';
import 'package:turf_app/core/utils/price_calculator.dart';
import 'package:turf_app/data/models/turf_model.dart';
import 'package:turf_app/core/constants/enums.dart';

void main() {
  late PricingRules pricingRules;

  setUp(() {
    // Create test pricing rules
    pricingRules = PricingRules(
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
  });

  group('PriceCalculator.calculateSlotPrice', () {
    
    group('Weekday pricing', () {
      test('should apply weekday day price for Monday morning', () {
        // Monday, 2026-01-26 10:00
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-26', // Monday
          startTime: '10:00',
          publicHolidays: [],
        );

        expect(result['price'], 1000);
        expect(result['dayType'], DayType.weekday);
        expect(result['timeType'], TimeType.day);
        expect(result['priceType'], 'WEEKDAY_DAY');
      });

      test('should apply weekday night price for Tuesday evening', () {
        // Tuesday, 2026-01-27 19:00
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-27', // Tuesday
          startTime: '19:00',
          publicHolidays: [],
        );

        expect(result['price'], 1200);
        expect(result['dayType'], DayType.weekday);
        expect(result['timeType'], TimeType.night);
        expect(result['priceType'], 'WEEKDAY_NIGHT');
      });

      test('should apply weekday price for Friday', () {
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-30', // Friday
          startTime: '14:00',
          publicHolidays: [],
        );

        expect(result['price'], 1000);
        expect(result['dayType'], DayType.weekday);
      });
    });

    group('Saturday pricing (separate from Sunday)', () {
      test('should apply Saturday day price', () {
        // Saturday, 2026-01-31 12:00
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-31', // Saturday
          startTime: '12:00',
          publicHolidays: [],
        );

        expect(result['price'], 1400); // Saturday day price
        expect(result['dayType'], DayType.saturday);
        expect(result['timeType'], TimeType.day);
        expect(result['priceType'], 'SATURDAY_DAY');
      });

      test('should apply Saturday night price', () {
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-31', // Saturday
          startTime: '20:00',
          publicHolidays: [],
        );

        expect(result['price'], 1600); // Saturday night price
        expect(result['dayType'], DayType.saturday);
        expect(result['timeType'], TimeType.night);
        expect(result['priceType'], 'SATURDAY_NIGHT');
      });
    });

    group('Sunday pricing (separate from Saturday)', () {
      test('should apply Sunday day price (different from Saturday)', () {
        // Sunday, 2026-02-01 10:00
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-02-01', // Sunday
          startTime: '10:00',
          publicHolidays: [],
        );

        expect(result['price'], 1500); // Sunday day price (100 more than Saturday)
        expect(result['dayType'], DayType.sunday);
        expect(result['timeType'], TimeType.day);
        expect(result['priceType'], 'SUNDAY_DAY');
      });

      test('should apply Sunday night price (different from Saturday)', () {
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-02-01', // Sunday
          startTime: '19:00',
          publicHolidays: [],
        );

        expect(result['price'], 1700); // Sunday night price (100 more than Saturday)
        expect(result['dayType'], DayType.sunday);
        expect(result['timeType'], TimeType.night);
        expect(result['priceType'], 'SUNDAY_NIGHT');
      });
    });

    group('Holiday pricing', () {
      test('should apply holiday day price when date is a public holiday', () {
        // Wednesday, 2026-01-28 14:00 (marking as holiday)
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-28', // Wednesday, but a holiday
          startTime: '14:00',
          publicHolidays: ['2026-01-28'],
        );

        expect(result['price'], 1800); // Holiday day price
        expect(result['dayType'], DayType.holiday);
        expect(result['timeType'], TimeType.day);
        expect(result['priceType'], 'HOLIDAY_DAY');
      });

      test('should apply holiday night price for holiday evening', () {
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-28',
          startTime: '21:00',
          publicHolidays: ['2026-01-28'],
        );

        expect(result['price'], 2000); // Holiday night price
        expect(result['dayType'], DayType.holiday);
        expect(result['timeType'], TimeType.night);
        expect(result['priceType'], 'HOLIDAY_NIGHT');
      });

      test('holiday should override weekend pricing', () {
        // Saturday that is also a holiday
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-31', // Saturday
          startTime: '12:00',
          publicHolidays: ['2026-01-31'],
        );

        expect(result['dayType'], DayType.holiday);
        expect(result['price'], 1800); // Holiday price, not Saturday
      });
    });

    group('Day/Night boundary', () {
      test('should apply day price at 17:59', () {
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-26',
          startTime: '17:00',
          publicHolidays: [],
        );

        expect(result['timeType'], TimeType.day);
        expect(result['price'], 1000);
      });

      test('should apply night price at 18:00', () {
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-26',
          startTime: '18:00',
          publicHolidays: [],
        );

        expect(result['timeType'], TimeType.night);
        expect(result['price'], 1200);
      });
    });
  });

  group('PriceCalculator.formatPrice', () {
    test('should format whole number price', () {
      expect(PriceCalculator.formatPrice(1000), '₹1000');
    });

    test('should format decimal price', () {
      expect(PriceCalculator.formatPrice(1000.50), '₹1000.50');
    });
  });

  group('PriceCalculator.getPriceLabel', () {
    test('should return correct label for SATURDAY_DAY', () {
      expect(PriceCalculator.getPriceLabel('SATURDAY_DAY'), 'Saturday (Day)');
    });

    test('should return correct label for SUNDAY_NIGHT', () {
      expect(PriceCalculator.getPriceLabel('SUNDAY_NIGHT'), 'Sunday (Night)');
    });

    test('should handle backward compatible WEEKEND labels', () {
      expect(PriceCalculator.getPriceLabel('WEEKEND_DAY'), 'Weekend (Day)');
    });
  });
}
