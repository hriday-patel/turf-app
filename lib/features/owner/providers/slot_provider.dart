import 'dart:async';
import 'package:flutter/material.dart';
import '../../../data/models/slot_model.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/services/database_service.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/price_calculator.dart';

/// Slot Provider
/// Manages slot generation, availability, and state
class SlotProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<SlotModel> _slots = [];
  String? _selectedDate;
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _slotsSubscription;

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
    _selectedDate = date;
    _isLoading = true;
    notifyListeners();

    // Cancel any previous stream subscription
    _slotsSubscription?.cancel();

    try {
      final rows = await _dbService.fetchTurfSlotsForDate(turfId, date);
      _slots = rows.map((row) => SlotModel.fromMap(row)).toList();
      _isLoading = false;
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to load slots: $error';
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
    try {
      _isLoading = true;
      notifyListeners();

      // Parse operating hours
      final openHour = int.parse(turf.openTime.split(':')[0]);
      final openMinute = int.parse(turf.openTime.split(':')[1]);
      final closeHour = int.parse(turf.closeTime.split(':')[0]);
      final closeMinute = int.parse(turf.closeTime.split(':')[1]);

      final openMinutes = openHour * 60 + openMinute;
      final closeMinutesRaw = closeHour * 60 + closeMinute;
      int closeMinutes;
      if (closeMinutesRaw == 0) {
        closeMinutes = 1440; // Midnight = end of day
      } else if (closeMinutesRaw <= openMinutes) {
        closeMinutes = closeMinutesRaw + 1440; // Overnight wrap
      } else {
        closeMinutes = closeMinutesRaw;
      }
      final slotDuration = turf.slotDurationMinutes;

      final List<Map<String, dynamic>> slotsData = [];
      int totalNetsProcessed = 0;
      int totalSlotsCreated = 0;

      // Generate slots for each net
      for (int netNumber = 1; netNumber <= turf.numberOfNets; netNumber++) {
        debugPrint('Processing Net $netNumber of ${turf.numberOfNets} for date $date');
        
        // For force regeneration: delete existing AVAILABLE/BLOCKED(Closed) slots first
        // This ensures a clean set of all 24-hour slots is always generated
        if (forceRegenerate) {
          await _dbService.deleteAvailableSlotsForDateAndNet(turf.turfId, date, netNumber);
          debugPrint('Deleted regeneratable slots for $date Net $netNumber');
        }

        // Sync prices for existing slots
        await _syncSlotPricesForNet(turf: turf, date: date, netNumber: netNumber);
        
        // Sync operating hours for existing slots
        await _syncOperatingHoursForNet(turf: turf, date: date, netNumber: netNumber);

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

          final startTime = '${startHour.toString().padLeft(2, '0')}:${startMin.toString().padLeft(2, '0')}';
          final endTime = '${endHour.toString().padLeft(2, '0')}:${endMin.toString().padLeft(2, '0')}';

          // Determine if slot is within operating hours
          // For overnight turfs (closeMinutes > 1440), a slot is available if:
          //   slotStart >= openMinutes (in day portion) OR
          //   slotStart + 1440 < closeMinutes (in overnight portion)
          bool isWithinOperatingHours;
          if (closeMinutes <= 1440) {
            // Normal hours (e.g., 06:00-23:00)
            isWithinOperatingHours = slotStart >= openMinutes && slotEnd <= closeMinutes;
          } else {
            // Overnight hours (e.g., 06:00-02:00 = open 360, close 1560)
            // Day portion: slotStart >= openMinutes
            // Night portion: slot is before close (slotStart + 1440 < closeMinutes)
            final inDayPortion = slotStart >= openMinutes;
            final inNightPortion = (slotStart + 1440) >= openMinutes && (slotEnd + 1440) <= closeMinutes;
            isWithinOperatingHours = inDayPortion || inNightPortion;
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
            'block_reason': isWithinOperatingHours ? null : 'Closed',
          });
          netSlotsCreated++;
        }
        
        debugPrint('Prepared $netSlotsCreated slots for Net $netNumber');
        totalSlotsCreated += netSlotsCreated;
        totalNetsProcessed++;
      }

      // Batch create all new slots
      if (slotsData.isNotEmpty) {
        await _dbService.batchCreateSlots(slotsData);
        debugPrint('Created $totalSlotsCreated slots across $totalNetsProcessed nets for $date');
      } else {
        debugPrint('No new slots to create for $date');
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to generate slots: $e';
      debugPrint('Error generating slots: $e');
      notifyListeners();
      return false;
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

      final openHour = int.parse(turf.openTime.split(':')[0]);
      final openMinute = int.parse(turf.openTime.split(':')[1]);
      final closeHour = int.parse(turf.closeTime.split(':')[0]);
      final closeMinute = int.parse(turf.closeTime.split(':')[1]);

      final openMinutes = openHour * 60 + openMinute;
      final closeMinutesRaw = closeHour * 60 + closeMinute;
      int closeMinutes;
      if (closeMinutesRaw == 0) {
        closeMinutes = 1440;
      } else if (closeMinutesRaw <= openMinutes) {
        closeMinutes = closeMinutesRaw + 1440;
      } else {
        closeMinutes = closeMinutesRaw;
      }

      for (final slot in slots) {
        final status = (slot['status'] as String?) ?? 'AVAILABLE';
        if (status != 'AVAILABLE' && status != 'BLOCKED') {
          continue;
        }

        final startTime = slot['start_time'] as String;
        final endTime = (slot['end_time'] as String?) ?? startTime;

        final startParts = startTime.split(':');
        final endParts = endTime.split(':');
        final slotStartMin = (int.parse(startParts[0]) * 60) + int.parse(startParts[1]);
        final slotEndMin = (int.parse(endParts[0]) * 60) + int.parse(endParts[1]);
        final slotEndAdj = slotEndMin == 0 ? 1440 : slotEndMin;

        // Determine if slot is within operating hours (same logic as generation)
        bool isAvailable;
        if (closeMinutes <= 1440) {
          isAvailable = slotStartMin >= openMinutes && slotEndAdj <= closeMinutes;
        } else {
          final inDayPortion = slotStartMin >= openMinutes;
          final inNightPortion = (slotStartMin + 1440) >= openMinutes && (slotEndAdj + 1440) <= closeMinutes;
          isAvailable = inDayPortion || inNightPortion;
        }

        // Check if slot was auto-blocked due to being closed
        final blockReason = slot['block_reason'] as String?;
        final isAutoBlocked = blockReason == 'Closed' || blockReason == 'Outside operating hours';

        if (!isAvailable && status == 'AVAILABLE') {
          await _dbService.blockSlot(slot['id'] as String, turf.ownerId, 'Closed');
        } else if (isAvailable && status == 'BLOCKED' && isAutoBlocked) {
          await _dbService.unblockSlot(slot['id'] as String);
        }
      }
    } catch (e) {
      debugPrint('Failed to sync operating hours for Net $netNumber on $date: $e');
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
          await _dbService.updateSlotPricing(slot['id'] as String, newPrice, newType);
        }
      }
    } catch (e) {
      debugPrint('Failed to sync slot prices for Net $netNumber on $date: $e');
    }
  }

  /// Block a slot (owner action) with retry and immediate UI feedback
  Future<bool> blockSlot(String slotId, String ownerId, String? reason) async {
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
      _errorMessage = 'Failed to block slot: $e';
      // Revert optimistic update by reloading
      if (_selectedDate != null && _slots.isNotEmpty) {
        loadSlots(_slots.first.turfId, _selectedDate!);
      }
      notifyListeners();
      return false;
    }
  }

  /// Unblock a slot with retry and immediate UI feedback
  Future<bool> unblockSlot(String slotId) async {
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
          blockReason: null,
          createdAt: oldSlot.createdAt,
        );
        notifyListeners();
      }
      
      await _dbService.unblockSlot(slotId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to unblock slot: $e';
      // Revert optimistic update by reloading
      if (_selectedDate != null && _slots.isNotEmpty) {
        loadSlots(_slots.first.turfId, _selectedDate!);
      }
      notifyListeners();
      return false;
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
      _errorMessage = 'Failed to reserve slot: $e';
      notifyListeners();
      return false;
    }
  }

  /// Confirm booking (mark as booked)
  Future<bool> confirmBooking(String slotId) async {
    try {
      await _dbService.bookSlot(slotId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to confirm booking: $e';
      notifyListeners();
      return false;
    }
  }

  /// Mark slot as booked (used when payment is received)
  Future<bool> markSlotAsBooked(String slotId) async {
    try {
      await _dbService.bookSlot(slotId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to mark slot as booked: $e';
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
      _errorMessage = 'Failed to release slot: $e';
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
}
