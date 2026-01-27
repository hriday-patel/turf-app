import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>?> getOwner(String ownerId) async {
    return await _client.from('owners').select('*').eq('id', ownerId).maybeSingle();
  }

  Future<void> updateOwner(String ownerId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('owners').update(data).eq('id', ownerId);
  }

  Future<bool> checkOwnerExists({String? email, String? phone}) async {
    if (email != null) {
      final result = await _client.from('owners').select('id').eq('email', email).maybeSingle();
      if (result != null) return true;
    }
    if (phone != null) {
      final result = await _client.from('owners').select('id').eq('phone', phone).maybeSingle();
      if (result != null) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>?> getOwnerByPhone(String phone) async {
    return await _client.from('owners').select('*').eq('phone', phone).maybeSingle();
  }

  Stream<List<Map<String, dynamic>>> streamOwnerTurfs(String ownerId) {
    return _client
        .from('turfs')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows
            .where((row) => row['owner_id'] == ownerId)
            .toList());
  }

  Future<List<Map<String, dynamic>>> getApprovedTurfs({String? city}) async {
    var query = _client.from('turfs').select('*').eq('is_approved', true);
    if (city != null && city.isNotEmpty) {
      query = query.eq('city', city);
    }
    return await query.order('created_at', ascending: false);
  }

  Future<Map<String, dynamic>?> getTurf(String turfId) async {
    return await _client.from('turfs').select('*').eq('id', turfId).maybeSingle();
  }

  Future<String> createTurf(Map<String, dynamic> data, {String? turfId}) async {
    data['created_at'] = DateTime.now().toIso8601String();
    data['is_approved'] = false;
    data['verification_status'] = 'PENDING';

    if (turfId != null) {
      data['id'] = turfId;
      await _client.from('turfs').insert(data);
      return turfId;
    }

    final result = await _client.from('turfs').insert(data).select('id').single();
    return result['id'] as String;
  }

  Future<void> updateTurf(String turfId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('turfs').update(data).eq('id', turfId);
  }

  Stream<List<Map<String, dynamic>>> streamTurfSlots(String turfId, String date) {
    return _client
        .from('slots')
        .stream(primaryKey: ['id'])
        .order('start_time', ascending: true)
        .map((rows) => rows
            .where((row) => row['turf_id'] == turfId && row['date'] == date)
            .toList());
  }

  Future<bool> slotsExistForDate(String turfId, String date) async {
    final result = await _client
        .from('slots')
        .select('id')
        .eq('turf_id', turfId)
        .eq('date', date)
        .limit(1);
    return result.isNotEmpty;
  }

  Future<void> batchCreateSlots(List<Map<String, dynamic>> slotsData) async {
    await _client.from('slots').insert(slotsData);
  }

  Future<void> blockSlot(String slotId, String ownerId, String? reason) async {
    await _client.from('slots').update({
      'status': 'BLOCKED',
      'blocked_by': ownerId,
      'block_reason': reason,
      'reserved_until': null,
      'reserved_by': null,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', slotId);
  }

  Future<void> unblockSlot(String slotId) async {
    await _client.from('slots').update({
      'status': 'AVAILABLE',
      'blocked_by': null,
      'block_reason': null,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', slotId);
  }

  Stream<List<Map<String, dynamic>>> streamOwnerBookings(List<String> turfIds) {
    return _client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows
            .where((row) => turfIds.contains(row['turf_id']))
            .toList());
  }

  Future<List<Map<String, dynamic>>> getTodaysBookings(List<String> turfIds, String date) async {
    return await _client
        .from('bookings')
        .select('*')
        .inFilter('turf_id', turfIds)
        .eq('booking_date', date)
        .order('created_at', ascending: false);
  }

  Future<List<Map<String, dynamic>>> getPendingPayments(List<String> turfIds) async {
    return await _client
        .from('bookings')
        .select('*')
        .inFilter('turf_id', turfIds)
        .eq('payment_status', 'PAY_AT_TURF')
        .order('created_at', ascending: false);
  }

  Future<void> updateBooking(String bookingId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('bookings').update(data).eq('id', bookingId);
  }

  Future<Map<String, dynamic>?> getBookingById(String bookingId) async {
    return await _client.from('bookings').select('*').eq('id', bookingId).maybeSingle();
  }
}
