class SlotBusinessRules {
  static int normalizeCloseMinutes({
    required int openMinutes,
    required int closeMinutesRaw,
  }) {
    if (closeMinutesRaw == 0) {
      return 1440;
    }
    if (closeMinutesRaw == openMinutes) {
      return openMinutes;
    }
    if (closeMinutesRaw < openMinutes) {
      return closeMinutesRaw + 1440;
    }
    return closeMinutesRaw;
  }

  static bool isWithinOperatingHours({
    required int openMinutes,
    required int closeMinutes,
    required int slotStartMin,
    required int slotEndMin,
  }) {
    if (closeMinutes == openMinutes) {
      return false;
    }

    if (closeMinutes <= 1440) {
      return slotStartMin >= openMinutes && slotEndMin <= closeMinutes;
    }

    final inDayPortion = slotStartMin >= openMinutes && slotEndMin <= 1440;
    final inNightPortion = slotStartMin < (closeMinutes - 1440) &&
        slotEndMin <= (closeMinutes - 1440);
    return inDayPortion || inNightPortion;
  }

  static bool isManualOverrideReason(String? blockReason) {
    return blockReason == 'Day opened by owner' ||
        blockReason == 'Opened by owner';
  }

  static bool isAutoClosedReason(String? blockReason) {
    return blockReason == 'Closed' ||
        blockReason == 'Outside operating hours' ||
        blockReason == 'Turf closed' ||
        blockReason == 'Under renovation';
  }
}
