/// URL validation utilities.
///
/// Phase 7 Iter 3 CLEAN-01: extracted to a single source of truth so a
/// future tightening (e.g. https-only) only needs to be made once.
class UrlUtils {
  UrlUtils._();

  /// Returns true if [url] is a non-empty, parseable URL with an http(s)
  /// scheme. Catches `FormatException` from `Uri.parse` on malformed input.
  static bool isValidUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (_) {
      return false;
    }
  }
}
