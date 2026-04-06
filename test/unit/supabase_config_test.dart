import 'package:flutter_test/flutter_test.dart';
import 'package:turf_app/config/supabase_config.dart';

void main() {
  group('SupabaseConfig', () {
    test('resolveFromValues prefers dart-define values', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: 'https://project.supabase.co',
        defineAnonKey: 'ey.test.token',
        cachedUrl: 'https://cached.supabase.co',
        cachedAnonKey: 'cached.token.value',
      );

      expect(resolved.url, 'https://project.supabase.co');
      expect(resolved.anonKey, 'ey.test.token');
      expect(resolved.source, SupabaseConfigSource.dartDefine);
      expect(resolved.isConfigured, isTrue);
    });

    test('resolveFromValues falls back to cached values', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: '',
        defineAnonKey: '',
        cachedUrl: 'https://cached.supabase.co',
        cachedAnonKey: 'cached.token.value',
      );

      expect(resolved.url, 'https://cached.supabase.co');
      expect(resolved.anonKey, 'cached.token.value');
      expect(resolved.source, SupabaseConfigSource.cached);
      expect(resolved.isConfigured, isTrue);
    });

    test('resolveFromValues supports mixed source', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: 'https://project.supabase.co',
        defineAnonKey: '',
        cachedUrl: '',
        cachedAnonKey: 'cached.token.value',
      );

      expect(resolved.url, 'https://project.supabase.co');
      expect(resolved.anonKey, 'cached.token.value');
      expect(resolved.source, SupabaseConfigSource.mixed);
      expect(resolved.isConfigured, isTrue);
    });

    test('resolveFromValues sanitizes wrapped and hidden characters', () {
      final resolved = SupabaseConfig.resolveFromValues(
        defineUrl: '  "https://project.supabase.co"\u200B  ',
        defineAnonKey: "  'anon.key.value'\u200B  ",
        cachedUrl: '',
        cachedAnonKey: '',
      );

      expect(resolved.url, 'https://project.supabase.co');
      expect(resolved.anonKey, 'anon.key.value');
      expect(resolved.isConfigured, isTrue);
    });

    test('validationError includes missing keys and source', () {
      const unresolved = ResolvedSupabaseConfig(
        url: '',
        anonKey: '',
        source: SupabaseConfigSource.missing,
      );

      final error = SupabaseConfig.validationError(unresolved);
      expect(error, contains('SUPABASE_URL'));
      expect(error, contains('SUPABASE_ANON_KEY'));
      expect(error, contains('source: missing'));
    });
  });
}
