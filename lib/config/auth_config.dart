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

  /// iOS OAuth deep-link redirect URI.
  /// Must match the URL scheme registered in `ios/Runner/Info.plist` under
  /// `CFBundleURLTypes` and in your Supabase Auth → URL Configuration →
  /// Redirect URLs allowlist. Uses the same scheme as Android by design so
  /// the Supabase project only needs one allowlist entry.
  static const String iosOAuthRedirect = String.fromEnvironment(
    'IOS_OAUTH_REDIRECT',
    defaultValue: 'com.fieldpass.business://login-callback',
  );

  /// Minimum number of seconds between two consecutive OTP requests for the
  /// same phone number on the same device. Prevents accidental spamming and
  /// burns down SMS-bombing attacks via the app UI.
  static const int otpResendCooldownSeconds = 60;

  /// Redirect URL embedded in password-reset emails. When the user clicks the
  /// link they will land here with a recovery token in the URL fragment, and
  /// the app's deep-link handler picks it up and routes to the
  /// "set new password" screen.
  ///
  /// Phase 4 Iter 9 AS-08: previously we relied on the Supabase project's
  /// default Site URL, which silently broke when the deployed app URL
  /// changed. Override per environment via --dart-define=PASSWORD_RESET_REDIRECT.
  static const String passwordResetRedirect = String.fromEnvironment(
    'PASSWORD_RESET_REDIRECT',
    defaultValue: 'com.fieldpass.business://reset-password',
  );
}
