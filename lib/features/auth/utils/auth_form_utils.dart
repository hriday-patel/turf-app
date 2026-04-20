class AuthFormUtils {
  AuthFormUtils._();

  static const String indiaDialCode = '+91';

  static bool isValidEmail(String email) {
    final normalized = email.trim();
    if (normalized.isEmpty) return false;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized);
  }

  static String normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  static bool isValidIndianPhoneInput(String phone) {
    return RegExp(r'^\d{10}$').hasMatch(phone.trim());
  }

  static String normalizeIndianPhone(String phone) {
    final compact = phone.trim();
    if (compact.startsWith('+')) {
      return compact;
    }
    return '$indiaDialCode$compact';
  }

  static String stripIndiaDialCode(String phone) {
    return phone.trim().replaceFirst(indiaDialCode, '');
  }

  static bool isValidOtp(String otp) {
    return RegExp(r'^\d{6}$').hasMatch(otp.trim());
  }

  static bool isStrongPassword(String password) {
    final hasMinLength = password.length >= 8;
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    return hasMinLength && hasUpper && hasLower && hasNumber && hasSpecial;
  }

  static bool isValidDisplayName(String value) {
    return value.trim().length >= 3;
  }
}
