import 'package:supabase_flutter/supabase_flutter.dart';

/// Database Service
/// Handles all Supabase database operations using RPC functions
class DatabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  // =====================================================
  // OWNER OPERATIONS
  // =====================================================

  /// Check if owner exists by email or phone (using RPC)
  Future<bool> ownerExists({String? email, String? phone}) async {
    try {
      final result = await _client.rpc('check_owner_exists', params: {
        'check_email': email?.trim().toLowerCase(),
        'check_phone': phone?.trim(),
      });
      return result == true;
    } catch (e) {
      // If RPC doesn't exist, fall back to direct query
      return await _ownerExistsFallback(email: email, phone: phone);
    }
  }

  /// Fallback method for checking owner exists
  Future<bool> _ownerExistsFallback({String? email, String? phone}) async {
    if (email != null && email.isNotEmpty) {
      final result = await _client
          .from('owners')
          .select('id')
          .eq('email', email.toLowerCase().trim())
          .maybeSingle();
      if (result != null) return true;
    }

    if (phone != null && phone.isNotEmpty) {
      final result = await _client
          .from('owners')
          .select('id')
          .eq('phone', phone.trim())
          .maybeSingle();
      if (result != null) return true;
    }

    return false;
  }

  /// Create owner profile (using RPC - bypasses RLS)
  Future<void> createOwnerProfile({
    required String id,
    required String name,
    required String email,
    required String phone,
  }) async {
    try {
      await _client.rpc('create_owner_profile', params: {
        'user_id': id,
        'user_name': name.trim(),
        'user_email': email.trim().toLowerCase(),
        'user_phone': phone.trim(),
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('unique') || e.message.contains('duplicate')) {
        throw 'Email or phone already registered.';
      }
      throw 'Failed to create profile: ${e.message}';
    }
  }

  /// Get owner by ID
  Future<Map<String, dynamic>?> getOwner(String ownerId) async {
    return await _client
        .from('owners')
        .select('*')
        .eq('id', ownerId)
        .maybeSingle();
  }

  /// Update owner
  Future<void> updateOwner(String ownerId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('owners').update(data).eq('id', ownerId);
  }

  /// Get owner by phone
  Future<Map<String, dynamic>?> getOwnerByPhone(String phone) async {
    return await _client
        .from('owners')
        .select('*')
        .eq('phone', phone)
        .maybeSingle();
  }

  // =====================================================
  // PLAYER OPERATIONS
  // =====================================================

  /// Create player profile (using RPC - bypasses RLS)
  Future<void> createPlayerProfile({
    required String id,
    required String name,
    required String email,
    required String phone,
  }) async {
    try {
      await _client.rpc('create_player_profile', params: {
        'user_id': id,
        'user_name': name.trim(),
        'user_email': email.trim().toLowerCase(),
        'user_phone': phone.trim(),
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('unique') || e.message.contains('duplicate')) {
        throw 'Email or phone already registered.';
      }
      throw 'Failed to create profile: ${e.message}';
    }
  }

  /// Get player by ID
  Future<Map<String, dynamic>?> getPlayer(String playerId) async {
    return await _client
        .from('players')
        .select('*')
        .eq('id', playerId)
        .maybeSingle();
  }

  // =====================================================
  // TURF OPERATIONS
  // =====================================================

  /// Stream owner's turfs
  Stream<List<Map<String, dynamic>>> streamOwnerTurfs(String ownerId) {
    return _client
        .from('turfs')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.where((row) => row['owner_id'] == ownerId).toList());
  }
  
  /// Get owner's turfs (one-time fetch)
  Future<List<Map<String, dynamic>>> getOwnerTurfs(String ownerId) async {
    return await _client
        .from('turfs')
        .select('*')
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false);
  }

  /// Get approved turfs (for players)
  Future<List<Map<String, dynamic>>> getApprovedTurfs({String? city}) async {
    var query = _client.from('turfs').select('*').eq('is_approved', true);
    if (city != null && city.isNotEmpty) {
      query = query.eq('city', city);
    }
    return await query.order('created_at', ascending: false);
  }

  /// Get turf by ID
  Future<Map<String, dynamic>?> getTurf(String turfId) async {
    return await _client.from('turfs').select('*').eq('id', turfId).maybeSingle();
  }

  /// Create turf with retry logic for network issues
  Future<String> createTurf(Map<String, dynamic> data, {String? turfId, int retryCount = 3}) async {
    data['created_at'] = DateTime.now().toIso8601String();
    data['is_approved'] = false;
    data['verification_status'] = 'PENDING';
    
    Exception? lastError;
    
    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        if (turfId != null) {
          data['id'] = turfId;
          await _client.from('turfs').insert(data);
          return turfId;
        }

        final result = await _client.from('turfs').insert(data).select('id').single();
        return result['id'] as String;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        
        // Check if it's a network error (Failed to fetch)
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('failed to fetch') || 
            errorStr.contains('network') ||
            errorStr.contains('timeout') ||
            errorStr.contains('connection')) {
          // Wait before retrying (exponential backoff)
          if (attempt < retryCount) {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            continue;
          }
        }
        
        // For non-network errors, throw immediately
        rethrow;
      }
    }
    
    throw lastError ?? Exception('Failed to create turf after $retryCount attempts');
  }

  /// Update turf with retry logic for network issues
  Future<void> updateTurf(String turfId, Map<String, dynamic> data, {int retryCount = 3}) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    
    Exception? lastError;
    
    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        await _client.from('turfs').update(data).eq('id', turfId);
        return; // Success
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        
        // Check if it's a network error (Failed to fetch)
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('failed to fetch') || 
            errorStr.contains('network') ||
            errorStr.contains('timeout') ||
            errorStr.contains('connection') ||
            errorStr.contains('clientexception')) {
          // Wait before retrying (exponential backoff)
          if (attempt < retryCount) {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            continue;
          }
        }
        
        // For non-network errors, throw immediately
        rethrow;
      }
    }
    
    throw lastError ?? Exception('Failed to update turf after $retryCount attempts');
  }

  // =====================================================
  // SLOT OPERATIONS
  // =====================================================

  /// Stream turf slots for a date
  Stream<List<Map<String, dynamic>>> streamTurfSlots(String turfId, String date) {
    return _client
        .from('slots')
        .stream(primaryKey: ['id'])
        .order('start_time', ascending: true)
        .map((rows) => rows
            .where((row) => row['turf_id'] == turfId && row['date'] == date)
            .toList());
  }

  /// Check if slots exist for a date
  Future<bool> slotsExistForDate(String turfId, String date) async {
    final result = await _client
        .from('slots')
        .select('id')
        .eq('turf_id', turfId)
        .eq('date', date)
        .limit(1);
    return result.isNotEmpty;
  }

  /// Batch create slots
  Future<void> batchCreateSlots(List<Map<String, dynamic>> slotsData) async {
    await _client.from('slots').insert(slotsData);
  }

  /// Block slot
  Future<void> blockSlot(String slotId, String ownerId, String? reason) async {
    await _client.from('slots').update({
      'status': 'BLOCKED',
      'blocked_by': ownerId,
      'block_reason': reason,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', slotId);
  }

  /// Unblock slot
  Future<void> unblockSlot(String slotId) async {
    await _client.from('slots').update({
      'status': 'AVAILABLE',
      'blocked_by': null,
      'block_reason': null,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', slotId);
  }

  /// Reserve slot (using RPC)
  Future<bool> reserveSlot({
    required String slotId,
    required String userId,
    required int reservationMinutes,
  }) async {
    final result = await _client.rpc('reserve_slot', params: {
      'p_slot_id': slotId,
      'p_reserved_by': userId,
      'p_reservation_minutes': reservationMinutes,
    });
    return result == true;
  }

  /// Release slot (using RPC)
  Future<void> releaseSlot(String slotId) async {
    await _client.rpc('release_slot', params: {
      'p_slot_id': slotId,
    });
  }

  /// Book slot (using RPC)
  Future<void> bookSlot(String slotId) async {
    await _client.rpc('book_slot', params: {
      'p_slot_id': slotId,
    });
  }

  // =====================================================
  // BOOKING OPERATIONS
  // =====================================================

  /// Create booking atomically (using RPC)
  Future<String> createBookingAtomic({
    required String slotId,
    required Map<String, dynamic> bookingData,
  }) async {
    final result = await _client.rpc('create_booking_atomic', params: {
      'p_slot_id': slotId,
      'p_booking_data': bookingData,
    });
    return result as String;
  }

  /// Cancel booking (using RPC)
  Future<bool> cancelBooking({
    required String bookingId,
    required String slotId,
    required String cancelledBy,
    String? reason,
  }) async {
    final result = await _client.rpc('cancel_booking', params: {
      'p_booking_id': bookingId,
      'p_slot_id': slotId,
      'p_cancelled_by': cancelledBy,
      'p_cancel_reason': reason,
    });
    return result == true;
  }

  /// Stream owner bookings
  Stream<List<Map<String, dynamic>>> streamOwnerBookings(String ownerId) {
    return _client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .order('booking_date', ascending: false)
        .map((rows) => rows.where((row) => row['owner_id'] == ownerId).toList());
  }

  /// Get booking by ID
  Future<Map<String, dynamic>?> getBooking(String bookingId) async {
    return await _client
        .from('bookings')
        .select('*')
        .eq('id', bookingId)
        .maybeSingle();
  }

  /// Get bookings for a date
  Future<List<Map<String, dynamic>>> getBookingsForDate(
    String ownerId,
    String date,
  ) async {
    return await _client
        .from('bookings')
        .select('*')
        .eq('owner_id', ownerId)
        .eq('booking_date', date)
        .order('start_time', ascending: true);
  }

  /// Stream bookings for owner's turfs
  Stream<List<Map<String, dynamic>>> streamBookingsByTurfs(List<String> turfIds) {
    if (turfIds.isEmpty) {
      return Stream.value([]);
    }
    return _client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .order('booking_date', ascending: false)
        .map((rows) => rows.where((row) => turfIds.contains(row['turf_id'])).toList());
  }

  /// Get today's bookings
  Future<List<Map<String, dynamic>>> getTodaysBookings(
    List<String> turfIds,
    String date,
  ) async {
    if (turfIds.isEmpty) return [];
    return await _client
        .from('bookings')
        .select('*')
        .inFilter('turf_id', turfIds)
        .eq('booking_date', date)
        .eq('booking_status', 'CONFIRMED')
        .order('start_time', ascending: true);
  }

  /// Get pending payments
  Future<List<Map<String, dynamic>>> getPendingPayments(List<String> turfIds) async {
    if (turfIds.isEmpty) return [];
    return await _client
        .from('bookings')
        .select('*')
        .inFilter('turf_id', turfIds)
        .eq('payment_status', 'PAY_AT_TURF')
        .eq('booking_status', 'CONFIRMED')
        .order('booking_date', ascending: false);
  }

  /// Update booking
  Future<void> updateBooking(String bookingId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('bookings').update(data).eq('id', bookingId);
  }
}
