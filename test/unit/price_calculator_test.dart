import 'package:flutter_test/flutter_test.dart';
import 'package:turf_app/core/utils/price_calculator.dart';
import 'package:turf_app/data/models/turf_model.dart';
import 'package:turf_app/core/constants/enums.dart';

void main() {
  late PricingRules pricingRules;

  setUp(() {
    // Create test pricing rules
    pricingRules = PricingRules(
      netPricing: [
        NetPricing(
          netNumber: 1,
          netName: 'Net 1',
          weekday: DayTypePricing(
            morning: TimeSlotPricing(label: 'Morning', startTime: '06:00', endTime: '12:00', price: 1000),
            afternoon: TimeSlotPricing(label: 'Afternoon', startTime: '12:00', endTime: '18:00', price: 1100),
            evening: TimeSlotPricing(label: 'Evening', startTime: '18:00', endTime: '00:00', price: 1200),
            night: TimeSlotPricing(label: 'Night', startTime: '00:00', endTime: '06:00', price: 900),
          ),
          weekend: DayTypePricing(
            morning: TimeSlotPricing(label: 'Morning', startTime: '06:00', endTime: '12:00', price: 1400),
            afternoon: TimeSlotPricing(label: 'Afternoon', startTime: '12:00', endTime: '18:00', price: 1500),
            evening: TimeSlotPricing(label: 'Evening', startTime: '18:00', endTime: '00:00', price: 1600),
            night: TimeSlotPricing(label: 'Night', startTime: '00:00', endTime: '06:00', price: 1300),
          ),
          holiday: DayTypePricing(
            morning: TimeSlotPricing(label: 'Morning', startTime: '06:00', endTime: '12:00', price: 1800),
            afternoon: TimeSlotPricing(label: 'Afternoon', startTime: '12:00', endTime: '18:00', price: 1900),
            evening: TimeSlotPricing(label: 'Evening', startTime: '18:00', endTime: '00:00', price: 2000),
            night: TimeSlotPricing(label: 'Night', startTime: '00:00', endTime: '06:00', price: 1700),
          ),
        ),
      ],
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
        expect(result['timeSlot'], 'MORNING');
        expect(result['priceType'], 'WEEKDAY_MORNING');
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
        expect(result['timeSlot'], 'EVENING');
        expect(result['priceType'], 'WEEKDAY_EVENING');
      });

      test('should apply weekday price for Friday', () {
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-30', // Friday
          startTime: '14:00',
          publicHolidays: [],
        );

        expect(result['price'], 1100);
        expect(result['dayType'], DayType.weekday);
      });
    });

    group('Weekend pricing', () {
      test('should apply weekend morning price (Saturday)', () {
        // Saturday, 2026-01-31 12:00
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-31', // Saturday
          startTime: '12:00',
          publicHolidays: [],
        );

        expect(result['price'], 1500); // Weekend afternoon price
        expect(result['dayType'], DayType.weekend);
        expect(result['timeSlot'], 'AFTERNOON');
        expect(result['priceType'], 'WEEKEND_AFTERNOON');
      });

      test('should apply weekend evening price (Sunday)', () {
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-02-01', // Sunday
          startTime: '20:00',
          publicHolidays: [],
        );

        expect(result['price'], 1600); // Weekend evening price
        expect(result['dayType'], DayType.weekend);
        expect(result['timeSlot'], 'EVENING');
        expect(result['priceType'], 'WEEKEND_EVENING');
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

        expect(result['price'], 1900); // Holiday afternoon price
        expect(result['dayType'], DayType.holiday);
        expect(result['timeSlot'], 'AFTERNOON');
        expect(result['priceType'], 'HOLIDAY_AFTERNOON');
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
        expect(result['timeSlot'], 'EVENING');
        expect(result['priceType'], 'HOLIDAY_EVENING');
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
        expect(result['price'], 1900); // Holiday afternoon price, not weekend
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

        expect(result['timeSlot'], 'AFTERNOON');
        expect(result['price'], 1100);
      });

      test('should apply night price at 18:00', () {
        final result = PriceCalculator.calculateSlotPrice(
          pricingRules: pricingRules,
          date: '2026-01-26',
          startTime: '18:00',
          publicHolidays: [],
        );

        expect(result['timeSlot'], 'EVENING');
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
    test('should return correct label for WEEKEND_MORNING', () {
      expect(PriceCalculator.getPriceLabel('WEEKEND_MORNING'), 'Weekend (Morning)');
    });

    test('should return correct label for HOLIDAY_NIGHT', () {
      expect(PriceCalculator.getPriceLabel('HOLIDAY_NIGHT'), 'Holiday (Night)');
    });

    test('should handle unknown labels by returning the raw value', () {
      expect(PriceCalculator.getPriceLabel('WEEKEND_DAY'), 'WEEKEND_DAY');
    });
  });
}
