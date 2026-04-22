import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../data/models/slot_model.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/services/database_service.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/slot_business_rules.dart';

/// Slot Provider
/// Manages slot generation, availability, and state
class SlotProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<SlotModel> _slots = [];
  String? _selectedDate;
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _slotsSubscription;
  int _loadRequestToken = 0;

  // Guards concurrent block/unblock to prevent optimistic-update race conditions
  final Set<String> _pendingSlotOps = {};
  // Guards concurrent generateSlots calls per turf+date
  final Set<String> _pendingGenerateOps = {};

  // Getters
  List<SlotModel> get slots => _slots;
  String? get selectedDate => _selectedDate;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<SlotModel> get availableSlots =>
      _slots.where((s) => s.status == SlotStatus.available).toList();
  List<SlotModel> get bookedSlots =>
      _slots.where((s) => s.status == SlotStatus.booked).toList();
  List<SlotModel> get blockedSlots =>
      _slots.where((s) => s.status == SlotStatus.blocked).toList();

  @override
  void dispose() {
    _slotsSubscription?.cancel();
    super.dispose();
  }

  /// Load slots for a turf on a specific date
  /// Uses a direct query to fetch all slots reliably (no stream row-limit truncation).
  Future<void> loadSlots(String turfId, String date) async {
    final requestToken = ++_loadRequestToken;
    _selectedDate = date;
    _isLoading = true;
    notifyListeners();

    // Cancel any previous stream subscription
    _slotsSubscription?.cancel();

    try {
      final rows = await _dbService.fetchTurfSlotsForDate(turfId, date);
      if (requestToken != _loadRequestToken) return;
      _slots = rows.map((row) => SlotModel.fromMap(row)).toList();
      _isLoading = false;
      notifyListeners();
    } catch (error) {
      if (requestToken != _loadRequestToken) return;
      _errorMessage = _friendlyError(
        error,
        fallback: 'Could not load slots. Please try again.',
      );
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Generate slots for a turf on a specific date
  /// ALL 24 hours are generated. Slots within operating hours are AVAILABLE,
  /// slots outside operating hours are BLOCKED with reason 'Closed'.
  /// Owner can manually open closed slots.
  Future<bool> generateSlots({
    required TurfModel turf,
    required String date,
    bool forceRegenerate = false,
  }) async {
    // Prevent concurrent generation for the same turf+date.
    // Phase 3 Iter5 BUG-11 fix: previously returned `true` when a duplicate
    // call came in, falsely telling the caller the work was done. Now we
    // return `false` and surface a friendly message so the caller can wait
    // / retry instead of advancing the UI prematurely.
    final genKey = '${turf.turfId}_$date';
    if (_pendingGenerateOps.contains(genKey)) {
      _errorMessage =
          'Slot generation is already in progress. Please wait\u2026';
      notifyListeners();
      return false;
    }
    _pendingGenerateOps.add(genKey);
    try {
      _isLoading = true;
      notifyListeners();

      // Validate turf configuration
      if (turf.numberOfNets <= 0) {
        debugPrint('Cannot generate slots: turf has ${turf.numberOfNets} nets');
        _isLoading = false;
        _errorMessage = 'Turf has no nets configured';
        notifyListeners();
        return false;
      }
      if (turf.daysOpen.isEmpty) {
        debugPrint(
            'Warning: turf has no daysOpen configured — all slots will be blocked');
      }

      // Check if this date's day-of-week is in daysOpen
      final parsedDate = DateTime.parse(date);
      const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      final dayOfWeek =
          dayNames[parsedDate.weekday - 1]; // weekday: 1=Mon..7=Sun
      final isDayOpen = turf.daysOpen.contains(dayOfWeek);

      // Parse operating hours
      final openHour = int.parse(turf.openTime.split(':')[0]);
      final openMinute = int.parse(turf.openTime.split(':')[1]);
      final closeHour = int.parse(turf.closeTime.split(':')[0]);
      final closeMinute = int.parse(turf.closeTime.split(':')[1]);

      final openMinutes = openHour * 60 + openMinute;
      final closeMinutesRaw = closeHour * 60 + closeMinute;
      final closeMinutes = SlotBusinessRules.normalizeCloseMinutes(
        openMinutes: openMinutes,
        closeMinutesRaw: closeMinutesRaw,
      );
      final slotDuration = turf.slotDurationMinutes;

      final List<Map<String, dynamic>> slotsData = [];
      int totalNetsProcessed = 0;
      int totalSlotsCreated = 0;

      // Generate slots for each net
      for (int netNumber = 1; netNumber <= turf.numberOfNets; netNumber++) {
        debugPrint(
            'Processing Net $netNumber of ${turf.numberOfNets} for date $date');
        final isRenovationNet = turf.status == TurfStatus.renovation &&
            turf.renovationNetNumbers.contains(netNumber);
        final isNetForceClosed =
            turf.status == TurfStatus.closed || isRenovationNet;

        // For force regeneration: delete existing AVAILABLE/BLOCKED(Closed) slots first
        // This ensures a clean set of all 24-hour slots is always generated
        if (forceRegenerate) {
          await _dbService.deleteAvailableSlotsForDateAndNet(
              turf.turfId, date, netNumber);
          debugPrint('Deleted regeneratable slots for $date Net $netNumber');
        }

        // Sync prices for existing slots
        await _syncSlotPricesForNet(
            turf: turf, date: date, netNumber: netNumber);

        // Sync operating hours for existing slots
        await _syncOperatingHoursForNet(
            turf: turf, date: date, netNumber: netNumber);

        int netSlotsCreated = 0;

        // ============================================================
        // FULL 24-HOUR SLOT GENERATION:
        // 1. Generate slots for ALL 24 hours (0:00 to 23:59)
        // 2. AVAILABLE if slot is within operating hours
        //    (slotStart >= openTime AND slotEnd <= closeTime)
        // 3. BLOCKED with reason 'Closed' if outside operating hours
        // 4. Owner can manually open any closed slot
        // 5. Uses upsert (ignore duplicates) so existing slots are preserved
        // ============================================================

        for (int slotStart = 0; slotStart < 1440; slotStart += slotDuration) {
          final slotEnd = slotStart + slotDuration;

          // Don't generate partial slots past midnight
          if (slotEnd > 1440) break;

          final startHour = slotStart ~/ 60;
          final startMin = slotStart % 60;
          final endHour = (slotEnd ~/ 60) % 24; // 24 → 0 for midnight
          final endMin = slotEnd % 60;

          final startTime =
              '${startHour.toString().padLeft(2, '0')}:${startMin.toString().padLeft(2, '0')}';
          final endTime =
              '${endHour.toString().padLeft(2, '0')}:${endMin.toString().padLeft(2, '0')}';

          // Determine if slot is within operating hours
          // If the day is not in daysOpen, all slots are closed regardless of operating hours
          // If openTime == closeTime, all slots are closed (invalid config)
          bool isWithinOperatingHours;
          if (isNetForceClosed) {
            isWithinOperatingHours = false;
          } else if (!isDayOpen || closeMinutes == openMinutes) {
            isWithinOperatingHours = false;
          } else {
            isWithinOperatingHours = SlotBusinessRules.isWithinOperatingHours(
              openMinutes: openMinutes,
              closeMinutes: closeMinutes,
              slotStartMin: slotStart,
              slotEndMin: slotEnd,
            );
          }

          // Calculate price for this slot
          final priceInfo = PriceCalculator.calculateSlotPrice(
            pricingRules: turf.pricingRules,
            date: date,
            startTime: startTime,
            publicHolidays: turf.publicHolidays,
            netNumber: netNumber,
          );

          slotsData.add({
            'turf_id': turf.turfId,
            'date': date,
            'start_time': startTime,
            'end_time': endTime,
            'net_number': netNumber,
            'status': isWithinOperatingHours ? 'AVAILABLE' : 'BLOCKED',
            'price': priceInfo['price'],
            'price_type': priceInfo['priceType'],
            'reserved_until': null,
            'reserved_by': null,
            'blocked_by': isWithinOperatingHours ? null : turf.ownerId,
            'block_reason': isWithinOperatingHours
                ? null
                : isRenovationNet
                    ? 'Under renovation'
                    : turf.status == TurfStatus.closed
                        ? 'Turf closed'
                        : 'Closed',
          });
          netSlotsCreated++;
        }

        debugPrint('Prepared $netSlotsCreated slots for Net $netNumber');
        totalSlotsCreated += netSlotsCreated;
        totalNetsProcessed++;
      }

      // Batch create all new slots
      if (slotsData.isNotEmpty) {
        try {
          await _dbService.batchCreateSlots(slotsData);
          debugPrint(
              'Created $totalSlotsCreated slots across $totalNetsProcessed nets for $date');
        } catch (e) {
          debugPrint('Batch slot creation failed: $e. Retrying...');
          // Retry once on failure
          try {
            await _dbService.batchCreateSlots(slotsData);
            debugPrint('Retry succeeded for $date');
          } catch (retryError) {
            _isLoading = false;
            _errorMessage = _friendlyError(
              retryError,
              fallback: 'Could not create slots. Please try again.',
            );
            notifyListeners();
            return false;
          }
        }
      } else {
        debugPrint('No new slots to create for $date');
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyError(
        e,
        fallback: 'Could not generate slots. Please try again.',
      );
      debugPrint('Error generating slots: $e');
      notifyListeners();
      return false;
    } finally {
      _pendingGenerateOps.remove(genKey);
    }
  }

  Future<void> _syncOperatingHoursForNet({
    required TurfModel turf,
    required String date,
    required int netNumber,
  }) async {
    try {
      final slots = await _dbService.getSlotsForDateAndNet(
        turf.turfId,
        date,
        netNumber,
      );

      // Check if this date's day-of-week is in daysOpen
      final parsedDate = DateTime.parse(date);
      const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      final dayOfWeek = dayNames[parsedDate.weekday - 1];
      final isDayOpen = turf.daysOpen.contains(dayOfWeek);
      final isRenovationNet = turf.status == TurfStatus.renovation &&
          turf.renovationNetNumbers.contains(netNumber);
      final isNetForceClosed =
          turf.status == TurfStatus.closed || isRenovationNet;

      final openHour = int.parse(turf.openTime.split(':')[0]);
      final openMinute = int.parse(turf.openTime.split(':')[1]);
      final closeHour = int.parse(turf.closeTime.split(':')[0]);
      final closeMinute = int.parse(turf.closeTime.split(':')[1]);

      final openMinutes = openHour * 60 + openMinute;
      final closeMinutesRaw = closeHour * 60 + closeMinute;
      final closeMinutes = SlotBusinessRules.normalizeCloseMinutes(
        openMinutes: openMinutes,
        closeMinutesRaw: closeMinutesRaw,
      );

      for (final slot in slots) {
        final status = (slot['status'] as String?) ?? 'AVAILABLE';
        if (status != 'AVAILABLE' && status != 'BLOCKED') {
          continue;
        }

        final startTime = slot['start_time'] as String;
        final endTime = (slot['end_time'] as String?) ?? startTime;
        final blockReason = slot['block_reason'] as String?;

        final startParts = startTime.split(':');
        final endParts = endTime.split(':');
        final slotStartMin =
            (int.parse(startParts[0]) * 60) + int.parse(startParts[1]);
        final slotEndMin =
            (int.parse(endParts[0]) * 60) + int.parse(endParts[1]);
        final slotEndAdj = slotEndMin == 0 ? 1440 : slotEndMin;

        bool isWithinOperatingHours;
        if (closeMinutes == openMinutes) {
          isWithinOperatingHours = false;
        } else {
          isWithinOperatingHours = SlotBusinessRules.isWithinOperatingHours(
            openMinutes: openMinutes,
            closeMinutes: closeMinutes,
            slotStartMin: slotStartMin,
            slotEndMin: slotEndAdj,
          );
        }

        final isManualOverride =
            SlotBusinessRules.isManualOverrideReason(blockReason);
        final isAutoClosed = SlotBusinessRules.isAutoClosedReason(blockReason);

        if (isNetForceClosed) {
          if (status == 'AVAILABLE' && !isManualOverride) {
            await _dbService.blockSlot(
              slot['id'] as String,
              turf.ownerId,
              isRenovationNet ? 'Under renovation' : 'Turf closed',
            );
          }
          continue;
        }

        // === daysOpen enforcement ===
        if (!isDayOpen) {
          // Day is CLOSED in config.
          if (status == 'AVAILABLE' && !isManualOverride) {
            // Block non-overridden AVAILABLE slots on closed days
            await _dbService.blockSlot(
                slot['id'] as String, turf.ownerId, 'Closed');
          }
          // Skip operating-hours check — day is closed, slots are already handled
          continue;
        }

        // Day is OPEN in config from here on.
        // Cleanup: clear override marker ONLY if slot is within operating hours
        // (if outside operating hours, the marker is still needed to prevent re-blocking)
        if (status == 'AVAILABLE' &&
            isManualOverride &&
            isWithinOperatingHours) {
          await _dbService.unblockSlot(
              slot['id'] as String); // clears marker, stays AVAILABLE
        }
        // Unblock auto-closed slots that are now within operating hours
        if (status == 'BLOCKED' && isAutoClosed && isWithinOperatingHours) {
          await _dbService.unblockSlot(slot['id'] as String);
        }

        // === Operating hours enforcement (open days only) ===
        // Don't re-block manually overridden slots — owner explicitly opened them
        if (!isWithinOperatingHours &&
            status == 'AVAILABLE' &&
            !isManualOverride) {
          await _dbService.blockSlot(
              slot['id'] as String, turf.ownerId, 'Closed');
        }
      }
    } catch (e) {
      // Phase 3 Iter5 BUG-12 fix: previously this swallowed the failure
      // silently, so generateSlots could report success while owners were
      // shown stale open/closed status. Surface a friendly error and rethrow
      // so the parent generateSlots catch can mark the run as failed.
      debugPrint(
          'Failed to sync operating hours for Net $netNumber on $date: $e');
      _errorMessage = _friendlyError(
        e,
        fallback:
            'Could not refresh open/closed hours for some slots. Please try again.',
      );
      rethrow;
    }
  }

  Future<void> _syncSlotPricesForNet({
    required TurfModel turf,
    required String date,
    required int netNumber,
  }) async {
    try {
      final slots = await _dbService.getSlotsForDateAndNet(
        turf.turfId,
        date,
        netNumber,
      );

      for (final slot in slots) {
        final status = (slot['status'] as String?) ?? 'AVAILABLE';
        if (status != 'AVAILABLE' && status != 'BLOCKED') {
          continue; // Don't change pricing for booked/reserved slots
        }

        final startTime = slot['start_time'] as String;
        final priceInfo = PriceCalculator.calculateSlotPrice(
          pricingRules: turf.pricingRules,
          date: date,
          startTime: startTime,
          publicHolidays: turf.publicHolidays,
          netNumber: netNumber,
        );

        final currentPrice = (slot['price'] as num?)?.toDouble() ?? 0;
        final currentType = slot['price_type'] as String?;
        final newPrice = (priceInfo['price'] as num).toDouble();
        final newType = priceInfo['priceType'] as String;

        if (currentPrice != newPrice || currentType != newType) {
          await _dbService.updateSlotPricing(
              slot['id'] as String, newPrice, newType);
        }
      }
    } catch (e) {
      // Phase 3 Iter5 BUG-12 fix: surface price-sync failures instead of
      // silently leaving stale prices on the schedule.
      debugPrint('Failed to sync slot prices for Net $netNumber on $date: $e');
      _errorMessage = _friendlyError(
        e,
        fallback: 'Could not refresh prices for some slots. Please try again.',
      );
      rethrow;
    }
  }

  /// Block a slot (owner action) with retry and immediate UI feedback
  Future<bool> blockSlot(String slotId, String ownerId, String? reason) async {
    // Prevent concurrent operations on the same slot
    if (_pendingSlotOps.contains(slotId)) return false;
    _pendingSlotOps.add(slotId);
    // Phase 3 Iter5 EDGE-07 fix: capture the turf+date for revert before any
    // await, so a date change mid-flight can't cause us to reload the wrong
    // turf's slots into the wrong selectedDate.
    final revertTurfId = _slots.isNotEmpty ? _slots.first.turfId : null;
    final revertDate = _selectedDate;
    try {
      // Optimistically update local state for instant feedback
      final index = _slots.indexWhere((s) => s.slotId == slotId);
      if (index != -1) {
        final oldSlot = _slots[index];
        _slots[index] = SlotModel(
          slotId: oldSlot.slotId,
          turfId: oldSlot.turfId,
          date: oldSlot.date,
          startTime: oldSlot.startTime,
          endTime: oldSlot.endTime,
          netNumber: oldSlot.netNumber,
          status: SlotStatus.blocked,
          price: oldSlot.price,
          priceType: oldSlot.priceType,
          blockedBy: ownerId,
          blockReason: reason,
          createdAt: oldSlot.createdAt,
        );
        notifyListeners();
      }

      await _dbService.blockSlot(slotId, ownerId, reason);
      return true;
    } catch (e) {
      _errorMessage = _friendlyError(
        e,
        fallback: 'Could not block slot. Please try again.',
      );
      // Revert optimistic update by reloading (using captured locals)
      if (revertTurfId != null && revertDate != null) {
        loadSlots(revertTurfId, revertDate);
      }
      notifyListeners();
      return false;
    } finally {
      _pendingSlotOps.remove(slotId);
    }
  }

  /// Unblock a slot with retry and immediate UI feedback.
  /// [overrideMarker] — if provided, stored as block_reason on the AVAILABLE
  /// slot to mark it as a manual override (e.g. 'Day opened by owner').
  Future<bool> unblockSlot(String slotId, {String? overrideMarker}) async {
    // Prevent concurrent operations on the same slot
    if (_pendingSlotOps.contains(slotId)) return false;
    _pendingSlotOps.add(slotId);
    // Phase 3 Iter5 EDGE-07 fix: capture revert context before await.
    final revertTurfId = _slots.isNotEmpty ? _slots.first.turfId : null;
    final revertDate = _selectedDate;
    try {
      // Optimistically update local state for instant feedback
      final index = _slots.indexWhere((s) => s.slotId == slotId);
      if (index != -1) {
        final oldSlot = _slots[index];
        _slots[index] = SlotModel(
          slotId: oldSlot.slotId,
          turfId: oldSlot.turfId,
          date: oldSlot.date,
          startTime: oldSlot.startTime,
          endTime: oldSlot.endTime,
          netNumber: oldSlot.netNumber,
          status: SlotStatus.available,
          price: oldSlot.price,
          priceType: oldSlot.priceType,
          blockedBy: null,
          blockReason: overrideMarker,
          createdAt: oldSlot.createdAt,
        );
        notifyListeners();
      }

      await _dbService.unblockSlot(slotId, overrideMarker: overrideMarker);
      return true;
    } catch (e) {
      _errorMessage = _friendlyError(
        e,
        fallback: 'Could not unblock slot. Please try again.',
      );
      // Revert optimistic update by reloading (using captured locals)
      if (revertTurfId != null && revertDate != null) {
        loadSlots(revertTurfId, revertDate);
      }
      notifyListeners();
      return false;
    } finally {
      _pendingSlotOps.remove(slotId);
    }
  }

  /// Reserve a slot (for booking flow)
  Future<bool> reserveSlot(String slotId, String userId) async {
    try {
      return await _dbService.reserveSlot(
        slotId: slotId,
        userId: userId,
        reservationMinutes: 10,
      );
    } catch (e) {
      _errorMessage = _friendlyError(
        e,
        fallback: 'Could not reserve slot. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  // Phase 3 Iter5 CLEAN-04: removed unused `confirmBooking` — it duplicated
  // `markSlotAsBooked` exactly and had no callers in the codebase.

  /// Mark slot as booked (used when payment is received)
  Future<bool> markSlotAsBooked(String slotId) async {
    try {
      await _dbService.bookSlot(slotId);
      return true;
    } catch (e) {
      _errorMessage = _friendlyError(
        e,
        fallback: 'Could not mark slot as booked. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Release slot (cancel reservation)
  Future<bool> releaseSlot(String slotId) async {
    try {
      await _dbService.releaseSlot(slotId);
      return true;
    } catch (e) {
      _errorMessage = _friendlyError(
        e,
        fallback: 'Could not release slot. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear slots
  void clearSlots() {
    _slots = [];
    _selectedDate = null;
    notifyListeners();
  }

  /// Phase 3 Iter5 ERR-03 fix: never leak raw backend exception text to
  /// production users (OWASP A09). In debug builds we still surface the
  /// real error so developers can diagnose.
  String _friendlyError(Object error, {required String fallback}) {
    if (kDebugMode) {
      return '$fallback (debug: $error)';
    }
    return fallback;
  }
}
