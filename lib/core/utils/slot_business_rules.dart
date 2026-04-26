import 'package:flutter/foundation.dart';

/// Pure (no I/O, no Flutter widgets) helpers that encode the
/// business rules around slot scheduling: operating-hour windows,
/// block-reason classification, and time-period bucketing.
///
/// All time values are expressed as **minutes since 00:00 of the
/// turf's local day** in the range `[0, 1440]`. A `closeMinutes`
/// value greater than `1440` represents an overnight window that
/// wraps past midnight (see [normalizeCloseMinutes]).
class SlotBusinessRules {
  /// Normalizes the raw close-time value coming from the DB into a
  /// canonical minute count usable by [isWithinOperatingHours].
  ///
  /// Conventions:
  /// * `closeMinutesRaw == 0`  → "open until midnight" → returns `1440`.
  /// * `closeMinutesRaw == openMinutes` → **closed all day** (zero-length
  ///   operating window). [isWithinOperatingHours] will return `false` for
  ///   every slot in this case.
  /// * `closeMinutesRaw <  openMinutes` → overnight wrap; returns
  ///   `closeMinutesRaw + 1440` so the caller can detect "past midnight".
  /// * Otherwise the value is returned unchanged.
  static int normalizeCloseMinutes({
    required int openMinutes,
    required int closeMinutesRaw,
  }) {
    if (closeMinutesRaw == 0) {
      return 1440;
    }
    if (closeMinutesRaw == openMinutes) {
      // Zero-length window = "closed all day". Documented intentionally;
      // do NOT change to mean "open 24h" without auditing existing rows.
      return openMinutes;
    }
    if (closeMinutesRaw < openMinutes) {
      return closeMinutesRaw + 1440;
    }
    return closeMinutesRaw;
  }

  /// Returns `true` when the half-open slot `[slotStartMin, slotEndMin)`
  /// fits entirely inside the operating window
  /// `[openMinutes, closeMinutes)`.
  ///
  /// Inputs must be expressed in minutes-since-midnight; the slot
  /// values must lie in `[0, 1440]`. A zero-length window
  /// (`closeMinutes == openMinutes`) is treated as "closed".
  static bool isWithinOperatingHours({
    required int openMinutes,
    required int closeMinutes,
    required int slotStartMin,
    required int slotEndMin,
  }) {
    // Phase 8 Iter 5 SLOT-01: defensive range check. Asserts in debug,
    // returns false (and logs in debug) in release if a caller passes
    // out-of-range minute values rather than silently matching the
    // overnight branch.
    assert(
      slotStartMin >= 0 &&
          slotStartMin <= 1440 &&
          slotEndMin >= 0 &&
          slotEndMin <= 1440 &&
          openMinutes >= 0 &&
          openMinutes <= 1440,
      'isWithinOperatingHours: minutes must be in [0, 1440] '
      '(got start=$slotStartMin, end=$slotEndMin, open=$openMinutes)',
    );
    if (slotStartMin < 0 ||
        slotStartMin > 1440 ||
        slotEndMin < 0 ||
        slotEndMin > 1440 ||
        openMinutes < 0 ||
        openMinutes > 1440) {
      if (kDebugMode) {
        debugPrint(
          'isWithinOperatingHours: rejecting out-of-range input '
          '(start=$slotStartMin, end=$slotEndMin, open=$openMinutes, '
          'close=$closeMinutes)',
        );
      }
      return false;
    }

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

  /// Returns `true` if [blockReason] indicates the owner manually
  /// re-opened a slot/day that the auto-scheduler had blocked.
  static bool isManualOverrideReason(String? blockReason) {
    return blockReason == BlockReason.dayOpenedByOwner ||
        blockReason == BlockReason.openedByOwner;
  }

  /// Returns `true` if [blockReason] is one of the auto-applied
  /// "this slot is unavailable" reasons (closed, outside hours,
  /// renovation, etc.).
  static bool isAutoClosedReason(String? blockReason) {
    return blockReason == BlockReason.closed ||
        blockReason == BlockReason.outsideOperatingHours ||
        blockReason == BlockReason.turfClosed ||
        blockReason == BlockReason.underRenovation;
  }

  /// Returns `true` if [blockReason] indicates a "Period closed …"
  /// block. Uses substring match (rather than equality with a single
  /// constant) so future variants like `"Period closed by admin"` or
  /// `"Period closed early"` are still classified correctly without a
  /// code change.
  static bool isPeriodCloseReason(String? blockReason) {
    final r = blockReason ?? '';
    return r.contains('Period closed');
  }

  /// Maps a 24h hour value to its period bucket key.
  /// Buckets: morning [6,12), afternoon [12,18), evening [18,24), night [0,6).
  static SlotPeriod periodForHour(int hour) {
    if (hour >= 6 && hour < 12) return SlotPeriod.morning;
    if (hour >= 12 && hour < 18) return SlotPeriod.afternoon;
    if (hour >= 18 && hour < 24) return SlotPeriod.evening;
    return SlotPeriod.night;
  }
}

/// Canonical block-reason strings written to / read from the DB.
/// Centralised so UI logic compares against constants rather than
/// brittle string literals scattered across screens.
///
/// ⚠️ Renaming any of these values is a **DB-migration-level change**:
/// existing rows in the `slots` table contain the literal text and
/// will not be retroactively updated.
class BlockReason {
  BlockReason._();

  /// Generic "this slot is closed" — used by the auto-scheduler.
  static const String closed = 'Closed';

  /// Slot falls outside the turf's configured operating-hours window.
  static const String outsideOperatingHours = 'Outside operating hours';

  /// Whole turf is marked closed (vacation, off-season, etc.).
  static const String turfClosed = 'Turf closed';

  /// Turf is unavailable due to maintenance/renovation.
  static const String underRenovation = 'Under renovation';

  /// Owner closed a date-range period explicitly.
  static const String periodClosedByOwner = 'Period closed by owner';

  /// Owner manually blocked an individual slot.
  static const String manuallyBlockedByOwner = 'Manually blocked by owner';

  /// Owner manually re-opened an entire day that the auto-scheduler
  /// would have closed.
  static const String dayOpenedByOwner = 'Day opened by owner';

  /// Owner manually re-opened a single slot that was auto-blocked.
  static const String openedByOwner = 'Opened by owner';
}

/// Time-of-day bucket used for pricing and analytics.
/// * [morning]   06:00 – 11:59
/// * [afternoon] 12:00 – 17:59
/// * [evening]   18:00 – 23:59
/// * [night]     00:00 – 05:59
enum SlotPeriod { morning, afternoon, evening, night }
