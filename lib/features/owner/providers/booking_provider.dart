import 'package:flutter/material.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/services/supabase_service.dart';
import '../../../data/services/supabase_backend_service.dart';
import '../../../core/constants/enums.dart';

/// Booking Provider
/// Manages booking state and operations
class BookingProvider extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();
  final SupabaseBackendService _backendService = SupabaseBackendService();

  List<BookingModel> _bookings = [];
  List<BookingModel> _todaysBookings = [];
  List<BookingModel> _pendingPayments = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<BookingModel> get bookings => _bookings;
  List<BookingModel> get todaysBookings => _todaysBookings;
  List<BookingModel> get pendingPayments => _pendingPayments;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get totalBookings => _bookings.length;
  int get todaysCount => _todaysBookings.length;
  int get pendingPaymentsCount => _pendingPayments.length;

  /// Load all bookings for owner's turfs
  void loadOwnerBookings(String ownerId, List<String> turfIds) {
    if (turfIds.isEmpty) return;

    _supabaseService.streamOwnerBookings(turfIds).listen(
      (rows) {
        _bookings = rows.map((row) => BookingModel.fromMap(row)).toList();
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = 'Failed to load bookings: $error';
        notifyListeners();
      },
    );
  }

  /// Load today's bookings
  Future<void> loadTodaysBookings(List<String> turfIds) async {
    try {
      final bookingDate = DateTime.now().toIso8601String().split('T').first;
      final snapshot = await _supabaseService.getTodaysBookings(
        turfIds,
        bookingDate,
      );
      _todaysBookings =
          snapshot.map((row) => BookingModel.fromMap(row)).toList();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load today\'s bookings: $e';
      notifyListeners();
    }
  }

  /// Load pending payments
  Future<void> loadPendingPayments(List<String> turfIds) async {
    try {
        final snapshot = await _supabaseService.getPendingPayments(turfIds);
        _pendingPayments =
          snapshot.map((row) => BookingModel.fromMap(row)).toList();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load pending payments: $e';
      notifyListeners();
    }
  }

  /// Create a manual booking (phone/walk-in)
  Future<String?> createManualBooking({
    required String turfId,
    required String slotId,
    required String bookingDate,
    required String startTime,
    required String endTime,
    required String turfName,
    required String customerName,
    required String customerPhone,
    required BookingSource bookingSource,
    required double amount,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Create booking data
      final data = {
        'turf_id': turfId,
        'slot_id': slotId,
        'booking_date': bookingDate,
        'start_time': startTime,
        'end_time': endTime,
        'turf_name': turfName,
        'user_id': null,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'booking_source': bookingSource.value,
        'payment_mode': 'OFFLINE',
        'payment_status': 'PAY_AT_TURF',
        'amount': amount,
        'transaction_id': null,
        'booking_status': 'CONFIRMED',
      };

      // Use atomic transaction to book slot + create booking
      final bookingId = await _backendService.createAtomicBooking(
        slotId: slotId,
        bookingData: data,
      );
      
      _isLoading = false;
      notifyListeners();
      return bookingId;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to create booking: $e';
      notifyListeners();
      return null;
    }
  }

  /// Create an app booking
  Future<String?> createAppBooking({
    required String turfId,
    required String slotId,
    required String bookingDate,
    required String startTime,
    required String endTime,
    required String turfName,
    required String userId,
    required String customerName,
    required String customerPhone,
    required PaymentMode paymentMode,
    required double amount,
    String? transactionId,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Create booking data
      final data = {
        'turf_id': turfId,
        'slot_id': slotId,
        'booking_date': bookingDate,
        'start_time': startTime,
        'end_time': endTime,
        'turf_name': turfName,
        'user_id': userId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'booking_source': 'APP',
        'payment_mode': paymentMode.value,
        'payment_status': paymentMode == PaymentMode.online 
            ? 'PAID' 
            : 'PAY_AT_TURF',
        'amount': amount,
        'transaction_id': transactionId,
        'booking_status': 'CONFIRMED',
      };

      // Use atomic transaction to book slot + create booking
      final bookingId = await _backendService.createAtomicBooking(
        slotId: slotId,
        bookingData: data,
      );
      
      _isLoading = false;
      notifyListeners();
      return bookingId;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to create booking: $e';
      notifyListeners();
      return null;
    }
  }

  /// Cancel a booking (atomic operation with slot release)
  Future<bool> cancelBooking(
    String bookingId, 
    String slotId, 
    String cancelledBy,
    String? reason,
  ) async {
    try {
      // Use atomic transaction to release slot + cancel booking
      final success = await _backendService.cancelBooking(
        bookingId: bookingId,
        slotId: slotId,
        cancelledBy: cancelledBy,
        reason: reason,
      );
      
      if (!success) {
        _errorMessage = 'Failed to cancel booking';
        notifyListeners();
      }
      
      return success;
    } catch (e) {
      _errorMessage = 'Failed to cancel booking: $e';
      notifyListeners();
      return false;
    }
  }

  /// Mark payment as received (for offline bookings)
  Future<bool> markPaymentReceived(String bookingId) async {
    try {
      await _supabaseService.updateBooking(bookingId, {
        'payment_status': 'PAID',
      });
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update payment status: $e';
      notifyListeners();
      return false;
    }
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
