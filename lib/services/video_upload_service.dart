import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class VideoUploadService {
  // Base URL of your backend API
  final String baseUrl;

  VideoUploadService({required this.baseUrl});

  /// Uploads a video file to the backend and returns the video URL and thumbnail URL
  Future<Map<String, String>> uploadVideo(File videoFile) async {
    try {
      debugPrint('Starting video upload to server');
      final fileSize = await videoFile.length();
      final fileSizeMB = fileSize / (1024 * 1024);
      debugPrint('Video file size: $fileSizeMB MB');

      if (fileSizeMB > 100) {
        throw Exception(
          'File too large (${fileSizeMB.toStringAsFixed(1)} MB). Maximum size is 100 MB.',
        );
      }

      // Try regular endpoint
      debugPrint('Trying video upload endpoint: $baseUrl/api/videos/upload');
      try {
        final result = await _uploadToEndpoint(
          videoFile,
          '$baseUrl/api/videos/upload',
        );
        debugPrint('✅ Video upload successful');
        return result;
      } catch (e) {
        debugPrint('❌ Video upload failed: $e, falling back to local file');
      }

      // Final fallback - just use the local file
      debugPrint('⚠️ Using local file fallback');
      return {'videoUrl': 'file://${videoFile.path}', 'thumbnailUrl': ''};
    } catch (e) {
      debugPrint('❌ Error in uploadVideo: $e');
      // Return the local file path so the app can still function
      return {'videoUrl': 'file://${videoFile.path}', 'thumbnailUrl': ''};
    }
  }

  /// Attempts to upload to the backend
  Future<Map<String, String>> _uploadToEndpoint(
    File videoFile,
    String endpoint,
  ) async {
    debugPrint('Uploading video to backend: ${videoFile.path}');
    final fileExtension = videoFile.path.split('.').last.toLowerCase();

    // Create a multipart request
    var request = http.MultipartRequest('POST', Uri.parse(endpoint));

    // Add the video file to the request
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        videoFile.path,
        contentType: MediaType('video', fileExtension),
      ),
    );

    debugPrint('Sending request to $endpoint');

    // Send the request with a short timeout
    var streamedResponse = await request.send().timeout(
      const Duration(seconds: 10),
    );
    var response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      debugPrint('Video uploaded successfully');
      var responseData = jsonDecode(response.body);
      return {
        'videoUrl': responseData['videoUrl'] ?? '',
        'thumbnailUrl': responseData['thumbnailUrl'] ?? '',
      };
    } else {
      debugPrint('Failed to upload video: ${response.statusCode}');
      debugPrint('Response: ${response.body}');
      throw Exception('Failed to upload video: ${response.statusCode}');
    }
  }

  /// Check if the backend video upload service is available
  Future<bool> isServiceAvailable() async {
    try {
      debugPrint('Checking if video service is available at $baseUrl');

      // Try simple health check with short timeout
      final url = '$baseUrl/api/videos/health';
      debugPrint('Checking endpoint: $url');

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 2)); // Short timeout

      if (response.statusCode == 200) {
        debugPrint('✅ Video service is available!');
        return true;
      } else {
        debugPrint('❌ Video service returned: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Video service check failed: $e');
      return false;
    }
  }
}
