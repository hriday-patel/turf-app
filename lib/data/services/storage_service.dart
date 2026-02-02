import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Supabase Storage Service
/// Handles file uploads for turf images (web-compatible using API proxy)
class StorageService {
  SupabaseClient get _client => Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  static const String _turfBucket = 'turf-images';
  static const String _profileBucket = 'profile-images';
  
  // API base URL for server-side uploads (bypasses CORS)
  static const String _apiBaseUrl = 'https://turf-app-lyart.vercel.app/api';
  
  /// Check if user is authenticated
  bool get isAuthenticated => _client.auth.currentSession != null;

  /// Upload turf image using API proxy (works on web without CORS issues)
  /// Returns the download URL or null if upload fails
  Future<String?> uploadTurfImageBytes({
    required Uint8List imageBytes,
    required String turfId,
    required String imageType,
    String? fileName,
    int retryCount = 3,
  }) async {
    // Check authentication first
    if (!isAuthenticated) {
      debugPrint('Storage upload failed: User not authenticated');
      return null;
    }
    
    final String name = fileName ?? '${_uuid.v4()}.jpg';
    
    // Use API proxy on web, direct upload on mobile
    if (kIsWeb) {
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
  Future<String?> _uploadViaApi({
    required Uint8List imageBytes,
    required String turfId,
    required String fileName,
    int retryCount = 5,
  }) async {
    Exception? lastError;
    
    // Sanitize turfId and fileName to prevent URI errors
    final sanitizedTurfId = _sanitizeForUri(turfId);
    final sanitizedFileName = _sanitizeFileName(fileName);
    
    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        // Convert bytes to base64
        final String base64Image = base64Encode(imageBytes);
        
        final response = await http.post(
          Uri.parse('$_apiBaseUrl/storage/upload-image'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'imageData': base64Image,
            'turfId': sanitizedTurfId,
            'fileName': sanitizedFileName,
            'contentType': 'image/jpeg',
          }),
        ).timeout(const Duration(seconds: 90));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['url'] != null) {
            final url = data['url'] as String;
            // Validate returned URL
            if (_isValidUrl(url)) {
              debugPrint('Image uploaded successfully via API: $url');
              return url;
            } else {
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
          throw Exception(errorMsg);
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        final errorStr = e.toString().toLowerCase();
        debugPrint('API upload attempt $attempt failed: $e');
        
        // Check for retryable errors
        final isRetryableError = errorStr.contains('failed to fetch') ||
            errorStr.contains('network') ||
            errorStr.contains('timeout') ||
            errorStr.contains('connection') ||
            errorStr.contains('socket') ||
            errorStr.contains('clientexception') ||
            errorStr.contains('uri');
        
        if (attempt < retryCount && isRetryableError) {
          // Exponential backoff with jitter
          final delay = Duration(milliseconds: (1000 * attempt) + (attempt * 200));
          await Future.delayed(delay);
          continue;
        } else if (!isRetryableError) {
          // Non-retryable error, break immediately
          break;
        }
      }
    }
    
    debugPrint('Failed to upload image via API after $retryCount attempts: $lastError');
    
    // Fallback to direct upload if API fails
    debugPrint('Attempting fallback to direct Supabase upload...');
    return await _uploadDirect(
      imageBytes: imageBytes,
      turfId: sanitizedTurfId,
      fileName: sanitizedFileName,
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
  
  /// Validate URL format
  static bool _isValidUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }
  
  /// Upload directly to Supabase Storage (for mobile or as fallback)
  Future<String?> _uploadDirect({
    required Uint8List imageBytes,
    required String turfId,
    required String fileName,
    int retryCount = 5,
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
        
        // Validate the URL before returning
        if (_isValidUrl(url)) {
          debugPrint('Image uploaded successfully via direct: $url');
          return url;
        } else {
          throw Exception('Invalid URL generated');
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        final errorStr = e.toString().toLowerCase();
        debugPrint('Direct upload attempt $attempt failed: $e');
        
        // Check for retryable errors
        final isRetryableError = errorStr.contains('failed to fetch') ||
            errorStr.contains('network') ||
            errorStr.contains('timeout') ||
            errorStr.contains('connection') ||
            errorStr.contains('socket') ||
            errorStr.contains('postgres') ||
            errorStr.contains('uri');
        
        if (attempt < retryCount && isRetryableError) {
          // Exponential backoff with jitter
          final delay = Duration(milliseconds: (500 * attempt) + (attempt * 100));
          await Future.delayed(delay);
          continue;
        } else if (!isRetryableError) {
          break;
        }
      }
    }
    
    debugPrint('Failed to upload image directly after $retryCount attempts: $lastError');
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
    
    // Upload images sequentially to avoid overwhelming the server
    for (int i = 0; i < imageBytesList.length; i++) {
      try {
        debugPrint('Uploading image ${i + 1}/${imageBytesList.length}...');
        
        final url = await uploadTurfImageBytes(
          imageBytes: imageBytesList[i],
          turfId: turfId,
          imageType: i == 0 ? 'primary' : 'secondary_$i',
        );
        
        if (url != null) {
          urls.add(url);
          debugPrint('Image ${i + 1} uploaded successfully');
        } else {
          failedCount++;
          debugPrint('Image ${i + 1} failed to upload');
        }
        
        // Small delay between uploads to prevent rate limiting
        if (i < imageBytesList.length - 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        debugPrint('Failed to upload image $i: $e');
        failedCount++;
      }
    }
    
    debugPrint('Upload complete: ${urls.length}/${imageBytesList.length} succeeded');
    
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

  /// Upload owner profile image using bytes
  Future<String> uploadProfileImageBytes({
    required Uint8List imageBytes,
    required String userId,
  }) async {
    try {
      final String fileName = 'profile_${_uuid.v4()}.jpg';
      final String path = 'users/$userId/$fileName';
      
      await _client.storage.from(_profileBucket).uploadBinary(
            path,
            imageBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
            ),
          );
      return _client.storage.from(_profileBucket).getPublicUrl(path);
    } catch (e) {
      throw 'Failed to upload profile image: ${e.toString()}';
    }
  }

  /// Delete image from storage
  Future<void> deleteImage(String bucket, String path) async {
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (e) {
      throw 'Failed to delete image: ${e.toString()}';
    }
  }

  /// Delete turf image by URL
  Future<void> deleteTurfImageByUrl(String imageUrl) async {
    try {
      // Extract path from URL
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      // Path format: /storage/v1/object/public/turf-images/turfs/{turfId}/images/{fileName}
      final bucketIndex = pathSegments.indexOf(_turfBucket);
      if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
        final path = pathSegments.sublist(bucketIndex + 1).join('/');
        await deleteImage(_turfBucket, path);
      }
    } catch (e) {
      throw 'Failed to delete turf image: ${e.toString()}';
    }
  }
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
