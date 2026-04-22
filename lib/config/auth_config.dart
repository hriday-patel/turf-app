/// Auth-related configuration constants.
///
/// Centralizing these here (instead of hard-coded inside services) makes
/// per-environment overrides explicit and discoverable.
class AuthConfig {
  AuthConfig._();

  /// Android OAuth deep-link redirect URI.
  /// Must match the scheme registered in AndroidManifest.xml and in your
  /// Supabase Auth → URL Configuration → Redirect URLs allowlist.
  static const String androidOAuthRedirect = String.fromEnvironment(
    'ANDROID_OAUTH_REDIRECT',
    defaultValue: 'com.fieldpass.business://login-callback',
  );

  /// Minimum number of seconds between two consecutive OTP requests for the
  /// same phone number on the same device. Prevents accidental spamming and
  /// burns down SMS-bombing attacks via the app UI.
  static const int otpResendCooldownSeconds = 60;
}
