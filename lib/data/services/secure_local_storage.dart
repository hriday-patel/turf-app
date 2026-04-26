import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Phase 4 Iter 11 SL-05: shared secure-storage options for all three
/// storage classes in this file. Android uses EncryptedSharedPreferences
/// (AES-256 via AndroidX Security Crypto) and resets corrupted storage on
/// Android Keystore verification failures. iOS uses `first_unlock`
/// accessibility rather than `first_unlock_this_device` deliberately:
/// (SL-08) sessions should survive normal device lock/unlock cycles so
/// the user isn't forced to re-authenticate after every screen lock.
/// The value is still protected by the device passcode at rest and is
/// evicted on factory reset.
const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
  ),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

/// Secure replacement for the Supabase SDK's default
/// SharedPreferencesLocalStorage. Persists the Supabase session JSON in
/// platform-secure storage (Android EncryptedSharedPreferences /
/// iOS Keychain) instead of plain SharedPreferences.
///
/// Performs a one-time migration on [initialize] so users already signed
/// in on a previous build are not signed out after upgrade.
///
/// Phase 4 Iter 11 SL-09: the migration is one-way. Once a session has
/// been promoted from SharedPreferences to secure storage the legacy
/// plaintext copy is wiped; there is no rollback path. A user
/// downgrading to a pre-secure-storage build will simply have to sign in
/// again on this device.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({required this.persistSessionKey}) {
    // Phase 7 Iter 1 BUG-01: replaces the previous debug-only `assert`
    // with a runtime check so this guardrail also fires in release
    // builds, and use `trim().isEmpty` so all whitespace variants
    // (tabs, newlines, multiple spaces) are caught - not just '' / ' '.
    if (persistSessionKey.trim().isEmpty) {
      throw ArgumentError.value(
        persistSessionKey,
        'persistSessionKey',
        'must be a non-empty, non-whitespace string',
      );
    }
  }

  final String persistSessionKey;

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
        } else if (kDebugMode) {
          // Phase 7 Iter 1 EDGE-01: both legacy plaintext and secure
          // vault contain a session. We continue to trust the vault
          // (source of truth), but log the collision so it's visible
          // during testing if it ever happens.
          debugPrint(
            'SecureLocalStorage: migration collision - both legacy and '
            'secure storage have a session for "$persistSessionKey". '
            'Keeping secure-vault copy and discarding legacy.',
          );
        }
        // Phase 4 Iter 11 SL-02: the secure write above has already
        // succeeded (or was unnecessary). If removing the plaintext copy
        // fails we MUST NOT propagate - the app would then refuse to
        // start forever. Log in debug and move on; a retry will happen
        // on the next launch.
        try {
          await prefs.remove(persistSessionKey);
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              'SecureLocalStorage: failed to wipe legacy plaintext session: $e',
            );
          }
        }
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
    // Phase 4 Iter 11 SL-04: containsKey is cheaper than read() since it
    // avoids deserializing the session JSON just to check presence.
    try {
      return await _secureStorage.containsKey(key: persistSessionKey);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureLocalStorage.hasAccessToken failed: $e');
      }
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _secureStorage.read(key: persistSessionKey);
    } catch (e) {
      // Phase 4 Iter 11 SL-07: surface Keychain/Keystore errors in debug.
      if (kDebugMode) {
        debugPrint('SecureLocalStorage.accessToken failed: $e');
      }
      return null;
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _secureStorage.write(
        key: persistSessionKey,
        value: persistSessionString,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureLocalStorage.persistSession failed: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _secureStorage.delete(key: persistSessionKey);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureLocalStorage.removePersistedSession failed: $e');
      }
      rethrow;
    }
  }
}

/// Secure replacement for the SDK's default PKCE storage. PKCE
/// code-verifiers are short-lived but they are still credentials that
/// can complete an OAuth login if intercepted, so we keep them out of
/// plain SharedPreferences.
///
/// Phase 4 Iter 11 SL-03/SL-06: stale PKCE verifiers accumulate when a
/// login is abandoned. [sweepStalePkceEntries] is a best-effort cleanup
/// that can be called from app startup; it silently tolerates any
/// Keychain/Keystore failure.
class SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  const SecureGotrueAsyncStorage();

  /// Phase 4 Iter 11 SL-10: exposed for diagnostics / tests so consumers
  /// can reason about the Keychain namespace this class owns.
  static const String keyPrefix = 'sb_pkce_';

  String _scopedKey(String key) => '$keyPrefix$key';

  @override
  Future<String?> getItem({required String key}) async {
    try {
      return await _secureStorage.read(key: _scopedKey(key));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureGotrueAsyncStorage.getItem failed: $e');
      }
      return null;
    }
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    try {
      await _secureStorage.write(key: _scopedKey(key), value: value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureGotrueAsyncStorage.setItem failed: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> removeItem({required String key}) async {
    try {
      await _secureStorage.delete(key: _scopedKey(key));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureGotrueAsyncStorage.removeItem failed: $e');
      }
      rethrow;
    }
  }

  /// Best-effort sweep of every entry under [keyPrefix]. Safe to call
  /// from app startup; silently ignores Keychain/Keystore errors.
  ///
  /// This is intentionally coarse - any in-flight OAuth login started
  /// before app restart will lose its verifier and have to be retried,
  /// which is preferable to leaving dozens of stale credentials lying
  /// around indefinitely.
  static Future<void> sweepStalePkceEntries() async {
    try {
      final all = await _secureStorage.readAll();
      final staleKeys = all.keys.where((k) => k.startsWith(keyPrefix)).toList();
      for (final key in staleKeys) {
        try {
          await _secureStorage.delete(key: key);
        } catch (_) {
          // swallow - best-effort
        }
      }
      if (kDebugMode && staleKeys.isNotEmpty) {
        debugPrint(
          'SecureGotrueAsyncStorage: swept ${staleKeys.length} stale PKCE entries',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureGotrueAsyncStorage.sweep failed: $e');
      }
    }
  }
}
