import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/utils/url_utils.dart';

/// Supabase Storage Service
///
/// Uploads and removes binary assets (turf images, owner profile images)
/// backed by two buckets:
///
///   * `turf-images`    - turf photos, path layout `turfs/<turfId>/images/<file>`
///   * `profile-images` - owner / player avatars, path `users/<userId>/<file>`
///
/// Upload strategy:
///   * On **web** we POST to our own Vercel API (`/api/storage/upload-image`)
///     which runs with the service-role key and performs ownership checks
///     (Bearer token + `turfId` -> `owners` mapping). This avoids CORS and
///     lets us strip client-supplied filenames/content-types server-side.
///   * On **mobile/desktop** we upload directly via the Supabase client
///     and rely on RLS storage policies for authorization.
///
/// Hardening layers in this file (Phase 4 Iter 10 ST-01..ST-11):
///   * [_isRetryableStorageError]  - single shared retry predicate so the
///                                   API path and the direct path stay in
///                                   lock-step. (ST-03)
///   * [_maxImageBytes]            - 8 MB per-image client-side cap so we
///                                   never spend time base64-encoding a
///                                   50 MB selfie before the server rejects
///                                   it. (ST-09)
///   * `kDebugMode`-gated          - every log call is release-stripped to
///     `debugPrint`                  avoid leaking turf IDs / image URLs
///                                   to logcat. (ST-05)
///   * [uploadProfileImageBytes]   - same retry/auth-guard shape as the
///                                   turf upload path. (ST-02)
///   * [deleteTurfImageByUrl]      - REQUIRES the caller to pass `turfId`
///                                   and the parsed path must live under
///                                   `turfs/<turfId>/images/` so a tampered
///                                   DB `image_url` cannot be used to wipe
///                                   another owner's files. (ST-01)
class StorageService {
  SupabaseClient get _client => Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  static const String _profileBucket = 'profile-images';
  static const String _storageBucketValue = String.fromEnvironment(
    'STORAGE_BUCKET',
    defaultValue: 'turf-images',
  );

  /// Phase 4 Iter 10 ST-09: reject anything over 8 MB before we pay the
  /// base64-encoding or network cost.
  static const int _maxImageBytes = 8 * 1024 * 1024;

  // API base URL for server-side uploads (bypasses CORS)
  static const String _defaultApiBaseUrl =
      'https://fieldpass-business.vercel.app/api';

  static const String _apiBaseUrlDefine = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultApiBaseUrl,
  );

  static String get _apiBaseUrl {
    final raw = _apiBaseUrlDefine.trim();
    if (raw.isEmpty || raw == 'API_BASE_URL') {
      return _defaultApiBaseUrl;
    }
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static String get _turfBucket {
    final raw = _storageBucketValue.trim();
    if (raw.isEmpty || raw == 'STORAGE_BUCKET') {
      return 'turf-images';
    }

    // Some deployments pass a full storage URL in STORAGE_BUCKET.
    // Fall back to the expected bucket name in that case.
    if (raw.contains('://') || raw.contains('/')) {
      return 'turf-images';
    }

    return raw;
  }

  /// Check if user is authenticated
  bool get isAuthenticated => _client.auth.currentSession != null;

  /// Phase 4 Iter 10 ST-03: shared retry predicate for both upload paths.
  /// The [api] flag widens the matched error set for HTTP-layer failures
  /// (fetch/clientexception) that are irrelevant to direct SDK uploads,
  /// and vice-versa for `postgres` errors.
  static bool _isRetryableStorageError(Object e, {required bool api}) {
    final s = e.toString().toLowerCase();
    if (s.contains('network') ||
        s.contains('timeout') ||
        s.contains('connection') ||
        s.contains('socket') ||
        s.contains('uri')) {
      return true;
    }
    if (api &&
        (s.contains('failed to fetch') || s.contains('clientexception'))) {
      return true;
    }
    if (!api && s.contains('postgres')) {
      return true;
    }
    return false;
  }

  /// Upload turf image using API proxy (works on web without CORS issues)
  /// Returns the download URL or null if upload fails.
  ///
  /// Phase 4 Iter 10 ST-04: `imageType` parameter removed - the API proxy
  /// ignores client-supplied metadata and the direct path never consumed
  /// it. Caller passes size-capped bytes; turfId is UUID-validated.
  Future<String?> uploadTurfImageBytes({
    required Uint8List imageBytes,
    required String turfId,
    String? fileName,
    int retryCount = 3,
  }) async {
    if (!isAuthenticated) {
      if (kDebugMode) {
        debugPrint('Storage upload failed: User not authenticated');
      }
      return null;
    }

    // Phase 4 Iter 10 ST-09: size cap.
    if (imageBytes.length > _maxImageBytes) {
      if (kDebugMode) {
        debugPrint(
          'Storage upload rejected: ${imageBytes.length} bytes exceeds '
          '${_maxImageBytes ~/ (1024 * 1024)} MB cap',
        );
      }
      return null;
    }

    // Phase 4 Iter 10 ST-11: defense-in-depth UUID shape check. Server
    // still performs its own validation; this just avoids wasted round-trips.
    if (!_looksLikeUuid(turfId)) {
      if (kDebugMode) {
        debugPrint('Storage upload rejected: turfId is not a UUID: $turfId');
      }
      return null;
    }

    final String name = fileName ?? '${_uuid.v4()}.jpg';

    // Use API proxy on web, direct upload on mobile
    if (kIsWeb && _apiBaseUrl.isNotEmpty) {
      return await _uploadViaApi(
        imageBytes: imageBytes,
        turfId: turfId,
        fileName: name,
        retryCount: retryCount,
      );
    } else {
      return await _uploadDirect(
        imageBytes: imageBytes,
        turfId: turfId,
        fileName: name,
        retryCount: retryCount,
      );
    }
  }

  /// Upload via API proxy (for web - avoids CORS)
  ///
  /// Phase 7 Iter 2 BUG-01: default retry count tightened from 5 to 3 and
  /// per-attempt HTTP timeout from 90s to 45s. Worst-case wall time on a
  /// flaky network dropped from ~7.5 minutes to ~2.5 minutes so the user
  /// sees the failure (and can retry manually) before assuming the app
  /// has frozen.
  Future<String?> _uploadViaApi({
    required Uint8List imageBytes,
    required String turfId,
    required String fileName,
    int retryCount = 3,
  }) async {
    Exception? lastError;

    // Sanitize turfId for URI use. fileName is ignored by the server;
    // we only need its sanitized form for the direct-upload fallback.
    final sanitizedTurfId = _sanitizeForUri(turfId);

    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        // Server requires a valid Supabase Bearer token (S1) and verifies
        // ownership of `turfId` before accepting the upload (S2).
        final accessToken = _client.auth.currentSession?.accessToken;
        if (accessToken == null || accessToken.isEmpty) {
          if (kDebugMode) {
            debugPrint('API upload aborted: no active Supabase session');
          }
          return null;
        }

        // Convert bytes to base64
        final String base64Image = base64Encode(imageBytes);

        final response = await http
            .post(
              Uri.parse('$_apiBaseUrl/storage/upload-image'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $accessToken',
              },
              body: jsonEncode({
                // Server ignores client-supplied fileName/contentType (S3, S4)
                // and generates its own. We still send turfId and the base64
                // image; everything else is determined server-side.
                'imageData': base64Image,
                'turfId': sanitizedTurfId,
              }),
            )
            .timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['url'] != null) {
            final url = data['url'] as String;
            if (_isValidUrl(url)) {
              if (kDebugMode) {
                debugPrint('Image uploaded successfully via API');
              }
              return url;
            } else {
              // Phase 7 Iter 2 EDGE-02: server reported success but the
              // URL is unparseable. Best-effort delete the orphan so we
              // don't leak storage. Wrapped in try/catch because the URL
              // might be too malformed to parse a path out of.
              try {
                await deleteTurfImageByUrl(url, turfId: turfId);
              } catch (cleanupErr) {
                if (kDebugMode) {
                  debugPrint(
                    'Orphan cleanup after invalid URL failed: $cleanupErr',
                  );
                }
              }
              throw Exception('Invalid URL returned from server');
            }
          } else {
            throw Exception(data['error'] ?? 'Upload failed');
          }
        } else {
          String errorMsg = 'HTTP ${response.statusCode}';
          try {
            final errorData = jsonDecode(response.body);
            errorMsg = errorData['error'] ?? errorMsg;
          } catch (_) {}
          // Phase 4 Iter 10 ST-06: 4xx/5xx are authoritative server
          // responses, not transient network failures. Do NOT fall back
          // to direct upload on them - the server already said "no".
          throw _NonRetryableUploadException(
            errorMsg,
            statusCode: response.statusCode,
          );
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (kDebugMode) {
          debugPrint('API upload attempt $attempt failed: $e');
        }

        // Non-retryable HTTP responses abort immediately and skip fallback.
        if (e is _NonRetryableUploadException) {
          return null;
        }

        final retryable = _isRetryableStorageError(e, api: true);
        if (attempt < retryCount && retryable) {
          final delay =
              Duration(milliseconds: (1000 * attempt) + (attempt * 200));
          await Future.delayed(delay);
          continue;
        } else if (!retryable) {
          break;
        }
      }
    }

    if (kDebugMode) {
      debugPrint(
        'Failed to upload image via API after $retryCount attempts: $lastError',
      );
    }

    // Phase 4 Iter 10 ST-06: on web the direct-upload fallback hits the
    // same CORS wall that motivated the API proxy; skip it. On other
    // platforms _uploadViaApi shouldn't even run, but guard anyway.
    if (kIsWeb) {
      return null;
    }
    if (kDebugMode) {
      debugPrint('Attempting fallback to direct Supabase upload...');
    }
    return await _uploadDirect(
      imageBytes: imageBytes,
      turfId: sanitizedTurfId,
      fileName: _sanitizeFileName(fileName),
      retryCount: 3,
    );
  }

  /// Sanitize string for use in URI paths
  String _sanitizeForUri(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '_');
  }

  /// Sanitize file name
  String _sanitizeFileName(String fileName) {
    // Remove invalid characters and ensure extension
    String sanitized = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.\s]'), '_');
    if (!sanitized.toLowerCase().endsWith('.jpg') &&
        !sanitized.toLowerCase().endsWith('.jpeg') &&
        !sanitized.toLowerCase().endsWith('.png')) {
      sanitized = '$sanitized.jpg';
    }
    return sanitized;
  }

  /// Validate URL format. Phase 7 Iter 3 CLEAN-01: delegated to
  /// [UrlUtils.isValidUrl] so storage_service and database_service share a
  /// single source of truth.
  static bool _isValidUrl(String url) => UrlUtils.isValidUrl(url);

  /// Phase 4 Iter 10 ST-11: cheap UUID v4/v5 shape check. Not a full
  /// validator - RFC 4122 variants and version digits are loose on
  /// purpose (we only want to stop obviously-bogus ids).
  static final RegExp _uuidRegExp = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static bool _looksLikeUuid(String s) => _uuidRegExp.hasMatch(s);

  /// Upload directly to Supabase Storage (for mobile or as fallback)
  ///
  /// Phase 7 Iter 2 BUG-01: default retry count tightened from 5 to 3 to
  /// keep the worst-case retry budget aligned with the API path.
  Future<String?> _uploadDirect({
    required Uint8List imageBytes,
    required String turfId,
    required String fileName,
    int retryCount = 3,
  }) async {
    Exception? lastError;

    // Ensure sanitized values
    final sanitizedTurfId = _sanitizeForUri(turfId);
    final sanitizedFileName = _sanitizeFileName(fileName);

    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        final String path = 'turfs/$sanitizedTurfId/images/$sanitizedFileName';

        await _client.storage.from(_turfBucket).uploadBinary(
              path,
              imageBytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );

        final url = _client.storage.from(_turfBucket).getPublicUrl(path);

        if (_isValidUrl(url)) {
          if (kDebugMode) {
            debugPrint('Image uploaded successfully via direct');
          }
          return url;
        } else {
          // Phase 7 Iter 2 EDGE-02: upload landed but generated URL is
          // unusable. Best-effort delete by known path so the bucket
          // doesn't accumulate orphaned blobs over time.
          try {
            await _client.storage.from(_turfBucket).remove([path]);
          } catch (cleanupErr) {
            if (kDebugMode) {
              debugPrint(
                  'Orphan cleanup after invalid URL failed: $cleanupErr');
            }
          }
          throw Exception('Invalid URL generated');
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (kDebugMode) {
          debugPrint('Direct upload attempt $attempt failed: $e');
        }

        final retryable = _isRetryableStorageError(e, api: false);
        if (attempt < retryCount && retryable) {
          final delay =
              Duration(milliseconds: (500 * attempt) + (attempt * 100));
          await Future.delayed(delay);
          continue;
        } else if (!retryable) {
          break;
        }
      }
    }

    if (kDebugMode) {
      debugPrint(
        'Failed to upload image directly after $retryCount attempts: $lastError',
      );
    }
    return null;
  }

  /// Upload multiple turf images using bytes
  /// Returns list of successfully uploaded URLs (may be empty if all fail)
  /// Also returns a flag indicating if there were failures
  Future<ImageUploadResult> uploadMultipleTurfImageBytesWithStatus({
    required List<Uint8List> imageBytesList,
    required String turfId,
  }) async {
    final List<String> urls = [];
    int failedCount = 0;

    // Phase 4 Iter 10 ST-08: removed the 300ms inter-upload delay. Supabase
    // storage and our Vercel proxy both handle serial uploads without
    // client-side pacing; the loop itself is already sequential.
    for (int i = 0; i < imageBytesList.length; i++) {
      try {
        if (kDebugMode) {
          debugPrint('Uploading image ${i + 1}/${imageBytesList.length}...');
        }

        final url = await uploadTurfImageBytes(
          imageBytes: imageBytesList[i],
          turfId: turfId,
        );

        if (url != null) {
          urls.add(url);
          if (kDebugMode) {
            debugPrint('Image ${i + 1} uploaded successfully');
          }
        } else {
          failedCount++;
          if (kDebugMode) {
            debugPrint('Image ${i + 1} failed to upload');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to upload image $i: $e');
        }
        failedCount++;
      }
    }

    if (kDebugMode) {
      debugPrint(
        'Upload complete: ${urls.length}/${imageBytesList.length} succeeded',
      );
    }

    return ImageUploadResult(
      urls: urls,
      successCount: urls.length,
      failedCount: failedCount,
      totalAttempted: imageBytesList.length,
    );
  }

  /// Upload multiple turf images using bytes
  /// Returns list of successfully uploaded URLs (may be empty if all fail)
  Future<List<String>> uploadMultipleTurfImageBytes({
    required List<Uint8List> imageBytesList,
    required String turfId,
  }) async {
    final result = await uploadMultipleTurfImageBytesWithStatus(
      imageBytesList: imageBytesList,
      turfId: turfId,
    );
    return result.urls;
  }

  /// Upload owner profile image using bytes.
  ///
  /// Phase 4 Iter 10 ST-02: now has the same auth guard, size cap and
  /// retry loop as [uploadTurfImageBytes] to avoid single-blip failures.
  /// Throws a human-readable string on terminal failure (preserved for
  /// call-site compatibility with `.catchError`).
  Future<String> uploadProfileImageBytes({
    required Uint8List imageBytes,
    required String userId,
    int retryCount = 3,
  }) async {
    // Phase 7 Iter 2 EDGE-01: profile uploads go straight to Supabase
    // (no Vercel proxy yet), which fails on web due to browser CORS.
    // Surface a clear, actionable error instead of silently spinning.
    if (kIsWeb) {
      throw 'Profile picture upload is not supported on web yet \u2014 '
          'please use the mobile app to change your profile photo.';
    }
    if (!isAuthenticated) {
      throw 'Failed to upload profile image: user not authenticated';
    }
    if (imageBytes.length > _maxImageBytes) {
      throw 'Failed to upload profile image: exceeds '
          '${_maxImageBytes ~/ (1024 * 1024)} MB cap';
    }
    if (!_looksLikeUuid(userId)) {
      throw 'Failed to upload profile image: invalid user id';
    }

    final String fileName = 'profile_${_uuid.v4()}.jpg';
    final String path = 'users/$userId/$fileName';

    Object? lastError;
    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        await _client.storage.from(_profileBucket).uploadBinary(
              path,
              imageBytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        return _client.storage.from(_profileBucket).getPublicUrl(path);
      } catch (e) {
        lastError = e;
        if (kDebugMode) {
          debugPrint('Profile upload attempt $attempt failed: $e');
        }
        if (attempt < retryCount && _isRetryableStorageError(e, api: false)) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        break;
      }
    }
    throw 'Failed to upload profile image: ${lastError ?? 'unknown error'}';
  }

  /// Delete image from storage
  Future<void> deleteImage(String bucket, String path) async {
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (e) {
      throw 'Failed to delete image: ${e.toString()}';
    }
  }

  /// Delete turf image by URL.
  ///
  /// Phase 4 Iter 10 ST-01: `turfId` is now REQUIRED. The URL is parsed,
  /// and the derived storage path MUST live under `turfs/<turfId>/images/`
  /// or the delete is refused. This stops a tampered DB `image_url` (or a
  /// URL belonging to another owner's turf) from being used as a
  /// cross-tenant delete primitive. RLS storage policies provide the
  /// server-side counterpart; this is the client-side belt.
  Future<void> deleteTurfImageByUrl(
    String imageUrl, {
    required String turfId,
  }) async {
    if (!_looksLikeUuid(turfId)) {
      throw 'Failed to delete turf image: invalid turfId';
    }
    try {
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      // Path format: /storage/v1/object/public/turf-images/turfs/{turfId}/images/{fileName}
      final bucketIndex = pathSegments.indexOf(_turfBucket);
      if (bucketIndex == -1 || bucketIndex >= pathSegments.length - 1) {
        throw 'URL does not reference the turf-images bucket';
      }
      final path = pathSegments.sublist(bucketIndex + 1).join('/');
      final expectedPrefix = 'turfs/${_sanitizeForUri(turfId)}/images/';
      if (!path.startsWith(expectedPrefix)) {
        throw 'URL does not belong to turf $turfId';
      }
      await deleteImage(_turfBucket, path);
    } catch (e) {
      throw 'Failed to delete turf image: ${e.toString()}';
    }
  }
}

/// Marker exception: authoritative HTTP 4xx/5xx response that should
/// NOT trigger retries or direct-upload fallback. (Phase 4 Iter 10 ST-06)
class _NonRetryableUploadException implements Exception {
  final String message;
  final int statusCode;
  _NonRetryableUploadException(this.message, {required this.statusCode});
  @override
  String toString() => 'UploadError($statusCode): $message';
}

/// Result class for image uploads
class ImageUploadResult {
  final List<String> urls;
  final int successCount;
  final int failedCount;
  final int totalAttempted;

  ImageUploadResult({
    required this.urls,
    required this.successCount,
    required this.failedCount,
    required this.totalAttempted,
  });

  bool get allSucceeded => failedCount == 0;
  bool get allFailed => successCount == 0 && totalAttempted > 0;
  bool get someSucceeded => successCount > 0;
}
