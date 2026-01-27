import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/supabase_config.dart';

class SupabaseBackendService {
  Uri _uri(String path) => Uri.parse('${SupabaseConfig.backendBaseUrl}$path');

  Future<bool> ownerExists({String? email, String? phone}) async {
    final response = await http.post(
      _uri('/auth/owner-exists'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'phone': phone,
      }),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['exists'] == true;
  }

  Future<void> createOwnerProfile({
    required String id,
    required String name,
    required String email,
    required String phone,
  }) async {
    final response = await http.post(
      _uri('/auth/create-owner'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
      }),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }
  }

  Future<void> createPlayerProfile({
    required String id,
    required String name,
    required String email,
    required String phone,
  }) async {
    final response = await http.post(
      _uri('/auth/create-player'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
      }),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }
  }

  Future<bool> reserveSlot({
    required String slotId,
    required String userId,
    required int reservationMinutes,
  }) async {
    final response = await http.post(
      _uri('/slots/reserve'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'slotId': slotId,
        'userId': userId,
        'reservationMinutes': reservationMinutes,
      }),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['success'] == true;
  }

  Future<void> releaseSlot({required String slotId}) async {
    final response = await http.post(
      _uri('/slots/release'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'slotId': slotId}),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }
  }

  Future<void> bookSlot({required String slotId}) async {
    final response = await http.post(
      _uri('/slots/book'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'slotId': slotId}),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }
  }

  Future<String> createAtomicBooking({
    required String slotId,
    required Map<String, dynamic> bookingData,
  }) async {
    final response = await http.post(
      _uri('/bookings/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'slotId': slotId,
        'booking': bookingData,
      }),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['bookingId'] as String;
  }

  Future<bool> cancelBooking({
    required String bookingId,
    required String slotId,
    required String cancelledBy,
    String? reason,
  }) async {
    final response = await http.post(
      _uri('/bookings/cancel'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'bookingId': bookingId,
        'slotId': slotId,
        'cancelledBy': cancelledBy,
        'reason': reason,
      }),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['success'] == true;
  }

  String _errorFromResponse(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error']?.toString() ?? 'Request failed.';
    } catch (_) {
      return 'Request failed.';
    }
  }
}
