import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/owner/providers/turf_provider.dart';
import 'features/owner/providers/slot_provider.dart';
import 'features/owner/providers/booking_provider.dart';
import 'config/supabase_config.dart';
import 'config/theme_provider.dart';
import 'data/services/secure_local_storage.dart';

/// Phase 6 Iter 3: app entrypoint with hardened error handling.
///
/// Fixes applied:
///   * Q1/BUG-01 — error-screen help text uses real string interpolation
///     instead of broken `const` template literals.
///   * Q2/BUG-02 — error fallback `MaterialApp` hides the debug banner and
///     applies a minimal dark-aware theme.
///   * Q3/CRASH-01 — provider construction is wrapped in the same try/catch
///     so any provider that throws on creation also routes to the error UI.
///   * Q4/EDGE-01 — `FlutterError.onError` and `PlatformDispatcher.onError`
///     installed; in release builds they swallow the default red-screen and
///     just log; in debug they keep the standard presentation.
///   * Q5/EDGE-02+CLEAN-01 — entire bootstrap runs inside `runZonedGuarded`
///     so async errors after `runApp` are captured; the error screen shows a
///     friendly message in release and the raw exception only in debug.
void main() {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Phase 6 Iter 3 (Q4/EDGE-01): global widget-build error sink.
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        FlutterError.presentError(details);
      } else {
        debugPrint('[main] FlutterError: ${details.exceptionAsString()}');
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[main] PlatformDispatcher error: $error');
      return true; // mark as handled
    };

    try {
      final config = await SupabaseConfig.resolve();

      if (!config.isConfigured) {
        throw Exception(
          '${SupabaseConfig.validationError(config)}. '
          'Start app with ${SupabaseConfig.runCommandHint}.',
        );
      }

      final projectRef = Uri.parse(config.url).host.split('.').first;
      final sessionStorageKey = 'sb-$projectRef-auth-token';

      await Supabase.initialize(
        url: config.url,
        anonKey: config.anonKey,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          // Ensures the SDK consumes the OAuth code from the deep-link URI
          // (com.fieldpass.business://login-callback?code=...) and exchanges
          // it for a session automatically.
          detectSessionInUri: true,
          // Persist the session in platform-secure storage instead of plain
          // SharedPreferences. Performs a one-time migration of any existing
          // plaintext session on first run after upgrade.
          localStorage:
              SecureLocalStorage(persistSessionKey: sessionStorageKey),
          pkceAsyncStorage: const SecureGotrueAsyncStorage(),
        ),
      );

      // Phase 7 Iter 1 BUG-02: wipe any leftover PKCE code-verifiers from
      // OAuth login attempts that the user abandoned (e.g. closed the app
      // mid Google sign-in). Best-effort, never throws.
      await SecureGotrueAsyncStorage.sweepStalePkceEntries();

      // Phase 6 Iter 3 (Q3/CRASH-01): provider constructors are inside the
      // same try-block so a throwing provider also routes to the error UI.
      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => TurfProvider()),
            ChangeNotifierProvider(create: (_) => SlotProvider()),
            ChangeNotifierProvider(create: (_) => BookingProvider()),
          ],
          child: const TurfApp(),
        ),
      );
    } catch (e, st) {
      debugPrint('[main] startup failure: $e\n$st');
      runApp(_StartupErrorApp(error: e));
    }
  }, (error, stack) {
    // Phase 6 Iter 3 (Q5/EDGE-02): zone-level catch for async errors that
    // escape after runApp has been called.
    debugPrint('[main] uncaught zone error: $error\n$stack');
  });
}

/// Phase 6 Iter 3 (Q1+Q2+Q5): friendly themed fallback shown when bootstrap
/// fails. Hides debug banner; shows raw exception only in debug builds.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorSchemeSeed: const Color(0xFF2E7D32),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    "We couldn't start the app",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    kDebugMode
                        ? error.toString()
                        : 'Something went wrong while starting up. '
                            'Please check your internet connection and '
                            'try opening the app again. If this keeps '
                            'happening, please reinstall or contact support.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text(
                      'Developer hints',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Preferred:\n${SupabaseConfig.runFromFileHint}\n\n'
                      'Direct:\n${SupabaseConfig.runCommandHint}\n\n'
                      'Release build:\n${SupabaseConfig.releaseBuildHint}\n\n'
                      '${SupabaseConfig.restartHint}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
