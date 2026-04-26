import 'package:flutter_test/flutter_test.dart';
import 'package:fieldpass_business/config/supabase_config.dart';

// A realistically-shaped JWT-like anon key (>= 40 chars, two dots).
const String _validAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlhdCI6MTcwMDAwMDAwMH0.Sig_AbCdEfGhIjKlMnOpQrStUvWxYz1234567890abc';
const String _validAnonKey2 =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlhdCI6MTcwMDAwMDAwMX0.Sig_zYxWvUtSrQpOnMlKjIhGfEdCbA0987654321xyz';

void main() {
  group('SupabaseConfig', () {
    test('resolveFromValues prefers dart-define values', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: 'https://project.supabase.co',
        defineAnonKey: _validAnonKey,
        cachedUrl: 'https://cached.supabase.co',
        cachedAnonKey: _validAnonKey2,
      );

      expect(resolved.url, 'https://project.supabase.co');
      expect(resolved.anonKey, _validAnonKey);
      expect(resolved.source, SupabaseConfigSource.dartDefine);
      expect(resolved.isConfigured, isTrue);
    });

    test('resolveFromValues falls back to cached values', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: '',
        defineAnonKey: '',
        cachedUrl: 'https://cached.supabase.co',
        cachedAnonKey: _validAnonKey,
      );

      expect(resolved.url, 'https://cached.supabase.co');
      expect(resolved.anonKey, _validAnonKey);
      expect(resolved.source, SupabaseConfigSource.cached);
      expect(resolved.isConfigured, isTrue);
    });

    test('resolveFromValues supports mixed source', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: 'https://project.supabase.co',
        defineAnonKey: '',
        cachedUrl: '',
        cachedAnonKey: _validAnonKey,
      );

      expect(resolved.url, 'https://project.supabase.co');
      expect(resolved.anonKey, _validAnonKey);
      expect(resolved.source, SupabaseConfigSource.mixed);
      expect(resolved.isConfigured, isTrue);
    });

    test('resolveFromValues sanitizes wrapped and hidden characters', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: '  "https://project.supabase.co"\u200B  ',
        defineAnonKey: "  '$_validAnonKey'\u200B  ",
        cachedUrl: '',
        cachedAnonKey: '',
      );

      expect(resolved.url, 'https://project.supabase.co');
      expect(resolved.anonKey, _validAnonKey);
      expect(resolved.isConfigured, isTrue);
    });

    test('rejects placeholder example.supabase.co URL', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: 'https://example.supabase.co',
        defineAnonKey: _validAnonKey,
        cachedUrl: '',
        cachedAnonKey: '',
      );

      expect(resolved.url, isEmpty,
          reason: 'placeholder URL must be normalized to empty');
      expect(resolved.isConfigured, isFalse);
    });

    test('rejects literal SUPABASE_URL placeholder token', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: 'SUPABASE_URL',
        defineAnonKey: _validAnonKey,
        cachedUrl: '',
        cachedAnonKey: '',
      );

      expect(resolved.url, isEmpty);
      expect(resolved.isConfigured, isFalse);
    });

    test('rejects placeholder anon key with asdfghjkl pattern', () {
      const placeholderKey =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV4YW1wbGUiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTYyMDAwMDAwMCwiZXhwIjoyMTI1NTY4MDAwfQ.asdfghjkl1234567890';

      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: 'https://project.supabase.co',
        defineAnonKey: placeholderKey,
        cachedUrl: '',
        cachedAnonKey: '',
      );

      expect(resolved.anonKey, isEmpty);
      expect(resolved.isConfigured, isFalse);
    });

    test('rejects literal SUPABASE_ANON_KEY placeholder token', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: 'https://project.supabase.co',
        defineAnonKey: 'SUPABASE_ANON_KEY',
        cachedUrl: '',
        cachedAnonKey: '',
      );

      expect(resolved.anonKey, isEmpty);
      expect(resolved.isConfigured, isFalse);
    });

    test('validationError includes missing keys and helpful guidance', () {
      const unresolved = ResolvedSupabaseConfig(
        url: '',
        anonKey: '',
        source: SupabaseConfigSource.missing,
      );

      final error = SupabaseConfig.validationError(unresolved);
      expect(error, contains('SUPABASE_URL'));
      expect(error, contains('SUPABASE_ANON_KEY'));
      expect(error, contains('source: missing'));
      expect(error, contains('dart_defines.local.json'));
    });

    test('validationError flags placeholder example.supabase.co URL', () {
      const placeholder = ResolvedSupabaseConfig(
        url: 'https://example.supabase.co',
        anonKey: 'SUPABASE_ANON_KEY',
        source: SupabaseConfigSource.dartDefine,
      );

      final error = SupabaseConfig.validationError(placeholder);
      expect(error, contains('SUPABASE_URL'));
      expect(error, contains('SUPABASE_ANON_KEY'));
      expect(error, contains('placeholder'));
    });
  });
}
