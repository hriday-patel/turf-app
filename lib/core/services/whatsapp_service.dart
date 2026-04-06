import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// WhatsApp Booking Confirmation Service
/// Sends messages via your server-side WhatsApp Cloud API proxy.
class WhatsAppService {
  // Default admin WhatsApp number for business notifications.
  static const String adminPhone = '919773424512';

  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://turf-app-lyart.vercel.app/api',
  );

  /// Send booking confirmation to customer via WhatsApp
  static Future<bool> sendBookingConfirmation({
    required String customerPhone,
    required String bookingId,
    required String turfName,
    required int netNumber,
    required String date,
    required String startTime,
    required String endTime,
    required double amount,
    required double advanceAmount,
  }) async {
    final balance = (amount - advanceAmount).clamp(0, double.infinity);

    final message = '''
🏏 *Booking Confirmed!*

📋 *Booking ID:* ${bookingId.substring(0, 8).toUpperCase()}
🏟️ *Venue:* $turfName
🥅 *Net:* $netNumber
📅 *Date:* $date
⏰ *Time:* $startTime - $endTime

💰 *Amount:* ₹${amount.toInt()}
✅ *Advance Paid:* ₹${advanceAmount.toInt()}
${balance > 0 ? '⚠️ *Balance Due:* ₹${balance.toInt()}' : '✅ *Fully Paid*'}

Thank you for your booking! 🙏
''';

    return sendTextMessage(toPhone: customerPhone, message: message);
  }

  /// Send any plain text message to a phone via backend proxy.
  static Future<bool> sendTextMessage({
    required String toPhone,
    required String message,
  }) async {
    final cleanPhone = _normalizePhone(toPhone);
    if (cleanPhone == null || message.trim().isEmpty) {
      return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/whatsapp/send-message'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'to': cleanPhone,
              'message': message.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return true;
      }

      debugPrint(
        'WhatsApp send failed (${response.statusCode}): ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('WhatsApp send error: $e');
      return false;
    }
  }

  /// Send a template message when no 24h service window is available.
  static Future<bool> sendTemplateMessage({
    required String toPhone,
    required String templateName,
    String languageCode = 'en_US',
    List<Map<String, dynamic>> components = const [],
  }) async {
    final cleanPhone = _normalizePhone(toPhone);
    if (cleanPhone == null || templateName.trim().isEmpty) {
      return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/whatsapp/send-message'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'to': cleanPhone,
              'template': {
                'name': templateName.trim(),
                'languageCode': languageCode,
                if (components.isNotEmpty) 'components': components,
              },
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return true;
      }

      debugPrint(
        'WhatsApp template send failed (${response.statusCode}): ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('WhatsApp template send error: $e');
      return false;
    }
  }

  static String? _normalizePhone(String phone) {
    String digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty || digitsOnly.length < 10) {
      return null;
    }

    // Default local 10-digit numbers to India (+91) for this app.
    if (digitsOnly.length == 10) {
      digitsOnly = '91$digitsOnly';
    }

    return digitsOnly;
  }

  /// Notify admin about new turf submission
  static Future<bool> notifyAdminTurfSubmission({
    required String turfName,
    required String ownerName,
    required String city,
  }) async {
    final message = '''
🏟️ *New Turf Submission*

📋 *Turf:* $turfName
👤 *Owner:* $ownerName
📍 *City:* $city

Please review and approve/reject this turf.
''';

    return sendTextMessage(toPhone: adminPhone, message: message);
  }
}
