import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Supabase Storage Service
/// Handles file uploads for turf images
class StorageService {
  SupabaseClient get _client => Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  static const String _turfBucket = 'turf-images';
  static const String _profileBucket = 'profile-images';

  /// Upload turf image
  /// Returns the download URL
  Future<String> uploadTurfImage({
    required File imageFile,
    required String turfId,
    required String imageType,
  }) async {
    try {
      final String fileName = '${_uuid.v4()}.jpg';
      final String path = 'turfs/$turfId/images/$fileName';
      
      await _client.storage.from(_turfBucket).upload(
            path,
            imageFile,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
            ),
          );

      return _client.storage.from(_turfBucket).getPublicUrl(path);
    } catch (e) {
      throw 'Failed to upload image: ${e.toString()}';
    }
  }

  /// Upload multiple turf images
  Future<List<String>> uploadMultipleTurfImages({
    required List<File> imageFiles,
    required String turfId,
  }) async {
    final List<String> urls = [];
    
    for (int i = 0; i < imageFiles.length; i++) {
      final url = await uploadTurfImage(
        imageFile: imageFiles[i],
        turfId: turfId,
        imageType: i == 0 ? 'primary' : 'secondary_$i',
      );
      urls.add(url);
    }
    
    return urls;
  }

  /// Upload owner profile image
  Future<String> uploadProfileImage({
    required File imageFile,
    required String userId,
  }) async {
    try {
      final String fileName = 'profile_${_uuid.v4()}.jpg';
      final String path = 'users/$userId/$fileName';
      
      await _client.storage.from(_profileBucket).upload(
            path,
            imageFile,
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
  Future<void> deleteImage(String imageUrl) async {
    try {
      final uri = Uri.parse(imageUrl);
      final segments = uri.pathSegments;
      final bucketIndex = segments.indexOf('object') + 1;
      if (bucketIndex <= 0 || bucketIndex >= segments.length) return;
      final bucket = segments[bucketIndex];
      final filePath = segments.sublist(bucketIndex + 1).join('/');
      await _client.storage.from(bucket).remove([filePath]);
    } catch (e) {
      print('Failed to delete image: $e');
    }
  }

  /// Delete all images for a turf
  Future<void> deleteTurfImages(String turfId) async {
    try {
      final prefix = 'turfs/$turfId/images';
      final result = await _client.storage.from(_turfBucket).list(path: prefix);
      final paths = result.map((item) => '$prefix/${item.name}').toList();
      if (paths.isNotEmpty) {
        await _client.storage.from(_turfBucket).remove(paths);
      }
    } catch (e) {
      print('Failed to delete turf images: $e');
    }
  }
}
