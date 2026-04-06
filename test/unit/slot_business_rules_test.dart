import 'package:flutter_test/flutter_test.dart';
import 'package:turf_app/core/utils/slot_business_rules.dart';

void main() {
  group('SlotBusinessRules', () {
    test('normalizeCloseMinutes handles overnight ranges', () {
      const openMinutes = 18 * 60;
      const closeMinutesRaw = 2 * 60;

      final close = SlotBusinessRules.normalizeCloseMinutes(
        openMinutes: openMinutes,
        closeMinutesRaw: closeMinutesRaw,
      );

      expect(close, 1560);
    });

    test('isWithinOperatingHours supports overnight slots', () {
      const openMinutes = 18 * 60;
      const closeMinutes = 1560; // 02:00 next day

      final inEvening = SlotBusinessRules.isWithinOperatingHours(
        openMinutes: openMinutes,
        closeMinutes: closeMinutes,
        slotStartMin: 22 * 60,
        slotEndMin: (23 * 60) + 30,
      );

      final inAfterMidnight = SlotBusinessRules.isWithinOperatingHours(
        openMinutes: openMinutes,
        closeMinutes: closeMinutes,
        slotStartMin: 60,
        slotEndMin: 120,
      );

      final outside = SlotBusinessRules.isWithinOperatingHours(
        openMinutes: openMinutes,
        closeMinutes: closeMinutes,
        slotStartMin: 8 * 60,
        slotEndMin: 9 * 60,
      );

      expect(inEvening, isTrue);
      expect(inAfterMidnight, isTrue);
      expect(outside, isFalse);
    });

    test('manual override and auto-closed reason helpers work', () {
      expect(SlotBusinessRules.isManualOverrideReason('Day opened by owner'),
          isTrue);
      expect(
          SlotBusinessRules.isManualOverrideReason('Opened by owner'), isTrue);
      expect(SlotBusinessRules.isManualOverrideReason('Closed'), isFalse);

      expect(SlotBusinessRules.isAutoClosedReason('Closed'), isTrue);
      expect(SlotBusinessRules.isAutoClosedReason('Under renovation'), isTrue);
      expect(SlotBusinessRules.isAutoClosedReason('Opened by owner'), isFalse);
    });
  });
}
