import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SupabaseConfigSource {
  dartDefine,
  mixed,
  cached,
  missing,
}

class ResolvedSupabaseConfig {
  final String url;
  final String anonKey;
  final SupabaseConfigSource source;

  const ResolvedSupabaseConfig({
    required this.url,
    required this.anonKey,
    required this.source,
  });

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

class SupabaseConfig {
  static const String _urlDefine = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'SUPABASE_URL',
  );
  static const String _anonKeyDefine = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'SUPABASE_ANON_KEY',
  );

  // Backward-compatible aliases to reduce startup breakages.
  static const String _urlAliasDefine = String.fromEnvironment(
    'SUPABASE_PROJECT_URL',
    defaultValue: 'SUPABASE_PROJECT_URL',
  );
  static const String _anonKeyAliasDefine = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'SUPABASE_PUBLISHABLE_KEY',
  );

  static const String _cachedUrlKey = 'runtime.supabase.url';
  static const String _cachedAnonKey = 'runtime.supabase.anon_key';

  static const String runCommandHint =
      "flutter run --dart-define='SUPABASE_URL=<SUPABASE_URL>' --dart-define='SUPABASE_ANON_KEY=<SUPABASE_ANON_KEY>'";

  static const String runFromFileHint =
      'flutter run --dart-define-from-file=dart_defines.local.json';

  static const String releaseBuildHint =
      'flutter build appbundle --release --dart-define-from-file=dart_defines.local.json';

  static const String restartHint =
      'Dart-define changes require stopping all existing flutter run sessions and launching again.';

  static String _sanitize(String value) {
    final trimmed =
        value.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();
    if (trimmed.length >= 2 &&
        ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
            (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  static String _normalizeDefine(String raw, String placeholder) {
    final sanitized = _sanitize(raw);
    if (sanitized.isEmpty || sanitized == placeholder) {
      return '';
    }
    return sanitized;
  }

  static String _firstNonEmpty(List<String> candidates) {
    for (final value in candidates) {
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  @visibleForTesting
  static ResolvedSupabaseConfig resolveFromValues({
    required String defineUrl,
    required String defineAnonKey,
    required String cachedUrl,
    required String cachedAnonKey,
  }) {
    final normalizedDefineUrl = _sanitize(defineUrl);
    final normalizedDefineAnon = _sanitize(defineAnonKey);
    final normalizedCachedUrl = _sanitize(cachedUrl);
    final normalizedCachedAnon = _sanitize(cachedAnonKey);

    final hasDefineUrl = normalizedDefineUrl.isNotEmpty;
    final hasDefineAnon = normalizedDefineAnon.isNotEmpty;
    final hasCachedUrl = normalizedCachedUrl.isNotEmpty;
    final hasCachedAnon = normalizedCachedAnon.isNotEmpty;

    final resolvedUrl =
        hasDefineUrl ? normalizedDefineUrl : normalizedCachedUrl;
    final resolvedAnon =
        hasDefineAnon ? normalizedDefineAnon : normalizedCachedAnon;

    final hasAnyDefine = hasDefineUrl || hasDefineAnon;
    final hasAnyCached = hasCachedUrl || hasCachedAnon;

    final SupabaseConfigSource source;
    if (hasDefineUrl && hasDefineAnon) {
      source = SupabaseConfigSource.dartDefine;
    } else if (hasAnyDefine) {
      source = SupabaseConfigSource.mixed;
    } else if (hasAnyCached) {
      source = SupabaseConfigSource.cached;
    } else {
      source = SupabaseConfigSource.missing;
    }

    return ResolvedSupabaseConfig(
      url: resolvedUrl,
      anonKey: resolvedAnon,
      source: source,
    );
  }

  static Future<ResolvedSupabaseConfig> resolve() async {
    final defineUrl = _firstNonEmpty([
      _normalizeDefine(_urlDefine, 'SUPABASE_URL'),
      _normalizeDefine(_urlAliasDefine, 'SUPABASE_PROJECT_URL'),
    ]);
    final defineAnonKey = _firstNonEmpty([
      _normalizeDefine(_anonKeyDefine, 'SUPABASE_ANON_KEY'),
      _normalizeDefine(_anonKeyAliasDefine, 'SUPABASE_PUBLISHABLE_KEY'),
    ]);

    String cachedUrl = '';
    String cachedAnonKey = '';

    try {
      final prefs = await SharedPreferences.getInstance();
      cachedUrl = _sanitize(prefs.getString(_cachedUrlKey) ?? '');
      cachedAnonKey = _sanitize(prefs.getString(_cachedAnonKey) ?? '');

      if (defineUrl.isNotEmpty && defineAnonKey.isNotEmpty) {
        await prefs.setString(_cachedUrlKey, defineUrl);
        await prefs.setString(_cachedAnonKey, defineAnonKey);
      }
    } catch (_) {
      // Fallback to dart-defines only when local persistence is unavailable.
    }

    return resolveFromValues(
      defineUrl: defineUrl,
      defineAnonKey: defineAnonKey,
      cachedUrl: cachedUrl,
      cachedAnonKey: cachedAnonKey,
    );
  }

  static String validationError(ResolvedSupabaseConfig config) {
    final missing = <String>[];
    if (config.url.isEmpty) {
      missing.add('SUPABASE_URL');
    }
    if (config.anonKey.isEmpty) {
      missing.add('SUPABASE_ANON_KEY');
    }
    if (missing.isEmpty) {
      return '';
    }
    return 'Missing required runtime config: ${missing.join(', ')} (source: ${config.source.name})';
  }
}
