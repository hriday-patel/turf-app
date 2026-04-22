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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final config = await SupabaseConfig.resolve();

    if (!config.isConfigured) {
      throw Exception(
        '${SupabaseConfig.validationError(config)}. Start app with ${SupabaseConfig.runCommandHint}.',
      );
    }

    // Initialize Supabase
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
        localStorage: SecureLocalStorage(persistSessionKey: sessionStorageKey),
        pkceAsyncStorage: const SecureGotrueAsyncStorage(),
      ),
    );

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
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Supabase Initialization Failed',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Please provide SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define.\n\nPreferred:\n${SupabaseConfig.runFromFileHint}\n\nDirect:\n${SupabaseConfig.runCommandHint}\n\nRelease build:\n${SupabaseConfig.releaseBuildHint}\n\n${SupabaseConfig.restartHint}',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
