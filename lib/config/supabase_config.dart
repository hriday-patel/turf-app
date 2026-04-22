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

  bool get isConfigured => SupabaseConfig.isResolvedConfigUsable(this);
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

  // Tokens that indicate a placeholder/template value rather than real credentials.
  // If any of these appear in a SUPABASE_URL we treat the URL as not configured
  // so the app surfaces a clear error instead of launching OAuth against a
  // non-existent project (e.g. https://example.supabase.co/auth/v1/authorize...).
  static const List<String> _placeholderUrlFragments = <String>[
    'example.supabase.co',
    'your-project.supabase.co',
    'your_project.supabase.co',
    'project-ref.supabase.co',
    'projectref.supabase.co',
    'xxxx.supabase.co',
    'xxxxx.supabase.co',
    'changeme.supabase.co',
    'supabase_url',
    'supabase_project_url',
  ];

  // Tokens that indicate a placeholder/template anon key.
  static const List<String> _placeholderAnonFragments = <String>[
    'supabase_anon_key',
    'supabase_publishable_key',
    'asdfghjkl1234567890',
    'your-anon-key',
    'your_anon_key',
    'changeme',
  ];

  static bool _isValidSupabaseUrl(String value) {
    if (value.isEmpty) return false;
    final lower = value.toLowerCase();
    for (final frag in _placeholderUrlFragments) {
      if (lower.contains(frag)) return false;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    return true;
  }

  static bool _isValidAnonKey(String value) {
    if (value.isEmpty) return false;
    final lower = value.toLowerCase();
    for (final frag in _placeholderAnonFragments) {
      if (lower.contains(frag)) return false;
    }
    // Real Supabase anon keys are JWTs (>= 100 chars typically) with two dots.
    if (value.length < 40) return false;
    return true;
  }

  @visibleForTesting
  static bool isResolvedConfigUsable(ResolvedSupabaseConfig config) {
    return _isValidSupabaseUrl(config.url) && _isValidAnonKey(config.anonKey);
  }

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

  static String _normalizeRuntimeUrl(String raw) {
    final sanitized = _sanitize(raw);
    if (!_isValidSupabaseUrl(sanitized)) return '';
    return sanitized;
  }

  static String _normalizeRuntimeAnonKey(String raw) {
    final sanitized = _sanitize(raw);
    if (!_isValidAnonKey(sanitized)) return '';
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
    final normalizedDefineUrl = _normalizeRuntimeUrl(defineUrl);
    final normalizedDefineAnon = _normalizeRuntimeAnonKey(defineAnonKey);
    final normalizedCachedUrl = _normalizeRuntimeUrl(cachedUrl);
    final normalizedCachedAnon = _normalizeRuntimeAnonKey(cachedAnonKey);

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
    if (!_isValidSupabaseUrl(config.url)) {
      missing.add('SUPABASE_URL');
    }
    if (!_isValidAnonKey(config.anonKey)) {
      missing.add('SUPABASE_ANON_KEY');
    }
    if (missing.isEmpty) {
      return '';
    }
    return 'Missing or placeholder runtime config: ${missing.join(', ')} '
        '(source: ${config.source.name}). '
        'Edit dart_defines.local.json with your real Supabase project URL and anon key '
        '(values like https://example.supabase.co are rejected).';
  }
}
