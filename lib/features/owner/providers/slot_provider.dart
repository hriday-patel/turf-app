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

  /// Load slots for a turf on a specific date
  void loadSlots(String turfId, String date) {
    _selectedDate = date;
    _isLoading = true;
    notifyListeners();

    _dbService.streamTurfSlots(turfId, date).listen(
      (rows) {
        _slots = rows.map((row) => SlotModel.fromMap(row)).toList();
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = 'Failed to load slots: $error';
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  /// Generate slots for a turf on a specific date
  /// Slots are generated from opening time to closing time
  /// Slots that extend past closing time are marked as CLOSED
  Future<bool> generateSlots({
    required TurfModel turf,
    required String date,
    bool forceRegenerate = false,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Check if this is a future date (tomorrow or later)
      final today = DateTime.now();
      final slotDate = DateTime.parse(date);
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final isFutureDate = !slotDate.isBefore(tomorrow);

      // Parse operating hours (e.g., "06:00" -> 360 minutes, "23:00" -> 1380 minutes)
      final openHour = int.parse(turf.openTime.split(':')[0]);
      final openMinute = int.parse(turf.openTime.split(':')[1]);
      final closeHour = int.parse(turf.closeTime.split(':')[0]);
      final closeMinute = int.parse(turf.closeTime.split(':')[1]);

      final openMinutes = openHour * 60 + openMinute;
      // Handle midnight as 1440 (end of day)
      final closeMinutesRaw = closeHour * 60 + closeMinute;
      final closeMinutes = closeMinutesRaw == 0 ? 1440 : closeMinutesRaw;
      final slotDuration = turf.slotDurationMinutes;

      final List<Map<String, dynamic>> slotsData = [];
      int totalNetsProcessed = 0;
      int totalSlotsCreated = 0;

      // Generate slots for each net
      for (int netNumber = 1; netNumber <= turf.numberOfNets; netNumber++) {
        debugPrint('Processing Net $netNumber of ${turf.numberOfNets} for date $date');
        
        // For force regeneration: delete existing AVAILABLE/BLOCKED slots first
        if (forceRegenerate && isFutureDate) {
          await _dbService.deleteAvailableSlotsForDateAndNet(turf.turfId, date, netNumber);
          debugPrint('Deleted AVAILABLE slots for $date Net $netNumber');
        }

        // Sync prices for existing slots
        await _syncSlotPricesForNet(turf: turf, date: date, netNumber: netNumber);
        
        // Sync operating hours for existing slots
        await _syncOperatingHoursForNet(turf: turf, date: date, netNumber: netNumber);

        // Get existing slot times to avoid duplicates
        final existingSlotTimes = await _dbService.getExistingSlotTimes(turf.turfId, date, netNumber);
        int netSlotsCreated = 0;
        
        // ============================================================
        // SLOT GENERATION RULES (per user requirements):
        // 1. Generate slots starting exactly from opening time
        // 2. Do NOT stop when a slot becomes unavailable or exceeds closing
        // 3. Continue until: slotStartTime >= closingTime + duration
        // 4. All slots must exist in data model (even if outside operating hours)
        // 5. AVAILABLE: slotStart >= open AND slotEnd <= close
        // 6. CLOSED: slotEnd > close (marked as BLOCKED in DB)
        // 7. CLOSED slots remain visible and support manual override
        // ============================================================
        
        // Continue until slotStart >= closeMinutes + slotDuration
        // This generates one extra slot that starts at closing time
        for (int slotStart = openMinutes; slotStart < closeMinutes + slotDuration; slotStart += slotDuration) {
          final slotEnd = slotStart + slotDuration;
          
          // Stop if slot would extend past midnight (24:00 = 1440 minutes)
          if (slotEnd > 1440) break;
          
          // Format times as HH:MM
          final startHour = slotStart ~/ 60;
          final startMin = slotStart % 60;
          final endHour = (slotEnd ~/ 60) % 24; // Handle 24:00 as 00:00
          final endMin = slotEnd % 60;

          final startTime = '${startHour.toString().padLeft(2, '0')}:${startMin.toString().padLeft(2, '0')}';
          final endTime = '${endHour.toString().padLeft(2, '0')}:${endMin.toString().padLeft(2, '0')}';

          // Skip if slot already exists (booked/reserved)
          if (existingSlotTimes.contains(startTime)) {
            debugPrint('Skipping existing slot at $startTime for Net $netNumber');
            continue;
          }

          // Determine availability: AVAILABLE only if slot ends within closing time
          final isAvailable = slotEnd <= closeMinutes;

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
            'status': isAvailable ? 'AVAILABLE' : 'BLOCKED',
            'price': priceInfo['price'],
            'price_type': priceInfo['priceType'],
            'reserved_until': null,
            'reserved_by': null,
            'blocked_by': isAvailable ? null : turf.ownerId,
            'block_reason': isAvailable ? null : 'Closed',
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
      final closeMinutes = closeMinutesRaw == 0 ? 1440 : closeMinutesRaw;

      for (final slot in slots) {
        final status = (slot['status'] as String?) ?? 'AVAILABLE';
        if (status != 'AVAILABLE' && status != 'BLOCKED') {
          continue;
        }

        final startTime = slot['start_time'] as String;
        final endTime = (slot['end_time'] as String?) ?? startTime;

        final startParts = startTime.split(':');
        final endParts = endTime.split(':');
        final startMinute = (int.parse(startParts[0]) * 60) + int.parse(startParts[1]);
        final endMinuteRaw = (int.parse(endParts[0]) * 60) + int.parse(endParts[1]);
        final endMinute = endMinuteRaw == 0 ? 1440 : endMinuteRaw;

        // Slot is available only if: start >= open AND end <= close
        final isAvailable = startMinute >= openMinutes && endMinute <= closeMinutes;

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
