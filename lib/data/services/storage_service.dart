import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Supabase Storage Service
/// Handles file uploads for turf images (web-compatible using bytes)
class StorageService {
  SupabaseClient get _client => Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  static const String _turfBucket = 'turf-images';
  static const String _profileBucket = 'profile-images';
  
  /// Check if user is authenticated
  bool get isAuthenticated => _client.auth.currentSession != null;

  /// Upload turf image using bytes (web compatible)
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
    
    Exception? lastError;
    
    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        final String name = fileName ?? '${_uuid.v4()}.jpg';
        final String path = 'turfs/$turfId/images/$name';
        
        // For web, we need to handle CORS issues
        await _client.storage.from(_turfBucket).uploadBinary(
              path,
              imageBytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true, // Allow overwriting if file exists
              ),
            );

        return _client.storage.from(_turfBucket).getPublicUrl(path);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('Image upload attempt $attempt failed: $e');
        
        // Check if it's a CORS/network error - these might not be recoverable on web
        final errorStr = e.toString().toLowerCase();
        final isCorsOrNetworkError = errorStr.contains('failed to fetch') || 
            errorStr.contains('cors') ||
            errorStr.contains('network') ||
            errorStr.contains('clientexception');
        
        if (isCorsOrNetworkError && kIsWeb) {
          // On web with persistent CORS issues, wait longer between retries
          if (attempt < retryCount) {
            await Future.delayed(Duration(milliseconds: 2000 * attempt));
          }
        } else {
          // For other errors, shorter delay
          if (attempt < retryCount) {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }
    }
    
    debugPrint('Failed to upload image after $retryCount attempts: ${lastError?.toString()}');
    return null; // Return null instead of throwing
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
    
    for (int i = 0; i < imageBytesList.length; i++) {
      try {
        final url = await uploadTurfImageBytes(
          imageBytes: imageBytesList[i],
          turfId: turfId,
          imageType: i == 0 ? 'primary' : 'secondary_$i',
        );
        if (url != null) {
          urls.add(url);
        } else {
          failedCount++;
        }
      } catch (e) {
        debugPrint('Failed to upload image $i: $e');
        failedCount++;
      }
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
