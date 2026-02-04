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
  /// If forceRegenerate is true, delete existing AVAILABLE slots and regenerate
  /// Ensures all nets have slots generated properly
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

      // Parse times
      final openHour = int.parse(turf.openTime.split(':')[0]);
      final openMinute = int.parse(turf.openTime.split(':')[1]);
      final closeHour = int.parse(turf.closeTime.split(':')[0]);
      final closeMinute = int.parse(turf.closeTime.split(':')[1]);

      final openMinutes = openHour * 60 + openMinute;
      final closeMinutes = closeHour * 60 + closeMinute;
      final slotDuration = turf.slotDurationMinutes;

      final List<Map<String, dynamic>> slotsData = [];
      int totalNetsProcessed = 0;
      int totalSlotsCreated = 0;

      // Generate slots for each net - ensure all nets are processed
      for (int netNumber = 1; netNumber <= turf.numberOfNets; netNumber++) {
        debugPrint('Processing Net $netNumber of ${turf.numberOfNets} for date $date');
        
        // For force regeneration of future dates:
        // 1. Delete ALL available slots for this net first
        // 2. Then regenerate with new settings (duration, pricing)
        if (forceRegenerate && isFutureDate) {
          await _dbService.deleteAvailableSlotsForDateAndNet(turf.turfId, date, netNumber);
          debugPrint('Deleted AVAILABLE slots for $date Net $netNumber');
        } else {
          // For regular generation (today or non-force), check if any slots exist
          final exists = await _dbService.slotsExistForDateAndNet(turf.turfId, date, netNumber);
          if (exists) {
            debugPrint('Slots already exist for Net $netNumber, skipping generation');
            await _syncSlotPricesForNet(
              turf: turf,
              date: date,
              netNumber: netNumber,
            );
            totalNetsProcessed++;
            continue; // Slots for this net already exist, skip to next net
          }
        }
        
        // Get existing slot times for this net (to avoid duplicates with booked/reserved slots)
        final existingSlotTimes = await _dbService.getExistingSlotTimes(turf.turfId, date, netNumber);
        int netSlotsCreated = 0;
        
        for (int startMinute = openMinutes;
             startMinute + slotDuration <= closeMinutes;
             startMinute += slotDuration) {
          
          final startHour = startMinute ~/ 60;
          final startMin = startMinute % 60;
          final endMinute = startMinute + slotDuration;
          final endHour = endMinute ~/ 60;
          final endMin = endMinute % 60;

          final startTime = '${startHour.toString().padLeft(2, '0')}:${startMin.toString().padLeft(2, '0')}';
          final endTime = '${endHour.toString().padLeft(2, '0')}:${endMin.toString().padLeft(2, '0')}';

          // Skip if this time slot already exists (e.g., booked/reserved slot)
          if (existingSlotTimes.contains(startTime)) {
            debugPrint('Skipping existing slot at $startTime for Net $netNumber');
            continue;
          }

          // Calculate price for this slot with correct net number
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
            'status': 'AVAILABLE',
            'price': priceInfo['price'],
            'price_type': priceInfo['priceType'],
            'reserved_until': null,
            'reserved_by': null,
            'blocked_by': null,
            'block_reason': null,
          });
          netSlotsCreated++;
        }
        
        debugPrint('Prepared $netSlotsCreated slots for Net $netNumber');
        totalSlotsCreated += netSlotsCreated;
        totalNetsProcessed++;
      }

      // Batch create slots (only if there are new slots to create)
      if (slotsData.isNotEmpty) {
        await _dbService.batchCreateSlots(slotsData);
        debugPrint('Created $totalSlotsCreated new slots across $totalNetsProcessed nets for $date with ${turf.slotDurationMinutes}min duration');
      } else {
        debugPrint('No new slots to create for $date - all ${turf.numberOfNets} nets already have slots');
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
