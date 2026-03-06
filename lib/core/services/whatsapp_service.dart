import 'package:url_launcher/url_launcher.dart';

/// WhatsApp Booking Confirmation Service
/// Sends booking confirmation messages via WhatsApp
class WhatsAppService {
  // Admin WhatsApp number for business notifications
  static const String adminPhone = '919773424512';

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

    // Clean phone number (remove spaces, dashes, ensure +91 prefix)
    String cleanPhone = customerPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!cleanPhone.startsWith('+')) {
      if (cleanPhone.startsWith('91') && cleanPhone.length > 10) {
        cleanPhone = '+$cleanPhone';
      } else {
        cleanPhone = '+91$cleanPhone';
      }
    }

    final whatsappUrl = Uri.parse(
      'https://wa.me/${cleanPhone.replaceAll('+', '')}?text=${Uri.encodeComponent(message)}',
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (_) {}
    return false;
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

    final whatsappUrl = Uri.parse(
      'https://wa.me/$adminPhone?text=${Uri.encodeComponent(message)}',
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (_) {}
    return false;
  }
}
