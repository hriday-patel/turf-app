import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Secure replacement for the Supabase SDK's default
/// SharedPreferencesLocalStorage. Persists the Supabase session JSON in
/// platform-secure storage (Android EncryptedSharedPreferences /
/// iOS Keychain) instead of plain SharedPreferences.
///
/// Performs a one-time migration on initialize() so users already signed
/// in on a previous build are not signed out after upgrade.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy != null && legacy.isNotEmpty) {
        final existing = await _secureStorage.read(key: persistSessionKey);
        if (existing == null || existing.isEmpty) {
          await _secureStorage.write(
            key: persistSessionKey,
            value: legacy,
          );
        }
        await prefs.remove(persistSessionKey);
      }
    } catch (e) {
      // Migration is best-effort. If it fails the user simply has to
      // sign in again on this device; we never want to block app startup.
      if (kDebugMode) {
        debugPrint('SecureLocalStorage migration skipped: $e');
      }
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    final value = await _secureStorage.read(key: persistSessionKey);
    return value != null && value.isNotEmpty;
  }

  @override
  Future<String?> accessToken() => _secureStorage.read(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secureStorage.write(
        key: persistSessionKey,
        value: persistSessionString,
      );

  @override
  Future<void> removePersistedSession() =>
      _secureStorage.delete(key: persistSessionKey);
}

/// Secure replacement for the SDK's default PKCE storage. PKCE
/// code-verifiers are short-lived but they are still credentials that
/// can complete an OAuth login if intercepted, so we keep them out of
/// plain SharedPreferences.
class SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  const SecureGotrueAsyncStorage();

  static const String _prefix = 'sb_pkce_';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  String _scopedKey(String key) => '$_prefix$key';

  @override
  Future<String?> getItem({required String key}) =>
      _secureStorage.read(key: _scopedKey(key));

  @override
  Future<void> setItem({required String key, required String value}) =>
      _secureStorage.write(key: _scopedKey(key), value: value);

  @override
  Future<void> removeItem({required String key}) =>
      _secureStorage.delete(key: _scopedKey(key));
}
