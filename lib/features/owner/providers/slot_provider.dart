import 'package:flutter/material.dart';
import '../../../data/models/slot_model.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/services/supabase_service.dart';
import '../../../data/services/supabase_backend_service.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/price_calculator.dart';

/// Slot Provider
/// Manages slot generation, availability, and state
class SlotProvider extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();
  final SupabaseBackendService _backendService = SupabaseBackendService();

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

    _supabaseService.streamTurfSlots(turfId, date).listen(
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
  Future<bool> generateSlots({
    required TurfModel turf,
    required String date,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Check if slots already exist
        final exists =
          await _supabaseService.slotsExistForDate(turf.turfId, date);
      if (exists) {
        _isLoading = false;
        notifyListeners();
        return true; // Slots already exist
      }

      // Parse times
      final openHour = int.parse(turf.openTime.split(':')[0]);
      final openMinute = int.parse(turf.openTime.split(':')[1]);
      final closeHour = int.parse(turf.closeTime.split(':')[0]);
      final closeMinute = int.parse(turf.closeTime.split(':')[1]);

      final openMinutes = openHour * 60 + openMinute;
      final closeMinutes = closeHour * 60 + closeMinute;
      final slotDuration = turf.slotDurationMinutes;

      final List<Map<String, dynamic>> slotsData = [];

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

        // Calculate price for this slot
        final priceInfo = PriceCalculator.calculateSlotPrice(
          pricingRules: turf.pricingRules,
          date: date,
          startTime: startTime,
          publicHolidays: turf.publicHolidays,
        );

        slotsData.add({
          'turf_id': turf.turfId,
          'date': date,
          'start_time': startTime,
          'end_time': endTime,
          'status': 'AVAILABLE',
          'price': priceInfo['price'],
          'price_type': priceInfo['priceType'],
          'reserved_until': null,
          'reserved_by': null,
          'blocked_by': null,
          'block_reason': null,
        });
      }

      // Batch create slots
      await _supabaseService.batchCreateSlots(slotsData);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to generate slots: $e';
      notifyListeners();
      return false;
    }
  }

  /// Block a slot (owner action)
  Future<bool> blockSlot(String slotId, String ownerId, String? reason) async {
    try {
      await _supabaseService.blockSlot(slotId, ownerId, reason);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to block slot: $e';
      notifyListeners();
      return false;
    }
  }

  /// Unblock a slot
  Future<bool> unblockSlot(String slotId) async {
    try {
      await _supabaseService.unblockSlot(slotId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to unblock slot: $e';
      notifyListeners();
      return false;
    }
  }

  /// Reserve a slot (for booking flow)
  Future<bool> reserveSlot(String slotId, String userId) async {
    try {
      return await _backendService.reserveSlot(
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
      await _backendService.bookSlot(slotId: slotId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to confirm booking: $e';
      notifyListeners();
      return false;
    }
  }

  /// Release slot (cancel reservation)
  Future<bool> releaseSlot(String slotId) async {
    try {
      await _backendService.releaseSlot(slotId: slotId);
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
