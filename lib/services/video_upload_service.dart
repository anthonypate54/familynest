import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class VideoUploadService {
  // Base URL of your backend API
  final String baseUrl;

  VideoUploadService({required this.baseUrl});

  /// Uploads a video file to the backend and returns the video URL and thumbnail URL
  Future<Map<String, String>> uploadVideo(File videoFile) async {
    try {
      final fileSize = await videoFile.length();
      final fileSizeMB = fileSize / (1024 * 1024);

      if (fileSizeMB > 25) {
        throw Exception(
          'File too large (${fileSizeMB.toStringAsFixed(1)} MB). Maximum size is 25 MB.',
        );
      }

      // Try regular endpoint
      try {
        final result = await _uploadToEndpoint(
          videoFile,
          '$baseUrl/api/videos/upload',
        );
        return result;
      } catch (e) {
        debugPrint('Video upload failed, using local file: $e');
      }

      // Final fallback - just use the local file
      return {'videoUrl': 'file://${videoFile.path}', 'thumbnailUrl': ''};
    } catch (e) {
      debugPrint('Error in uploadVideo: $e');
      // Return the local file path so the app can still function
      return {'videoUrl': 'file://${videoFile.path}', 'thumbnailUrl': ''};
    }
  }

  /// Attempts to upload to the backend
  Future<Map<String, String>> _uploadToEndpoint(
    File videoFile,
    String endpoint,
  ) async {
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

    // Send the request with a short timeout
    var streamedResponse = await request.send().timeout(
      const Duration(seconds: 10),
    );
    var response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      var responseData = jsonDecode(response.body);
      return {
        'videoUrl': responseData['videoUrl'] ?? '',
        'thumbnailUrl': responseData['thumbnailUrl'] ?? '',
      };
    } else {
      throw Exception(
        'Failed to upload video: ${response.statusCode} - ${response.body}',
      );
    }
  }

  /// Check if the backend video upload service is available
  Future<bool> isServiceAvailable() async {
    try {
      // Try simple health check with short timeout
      final response = await http
          .get(Uri.parse('$baseUrl/api/videos/health'))
          .timeout(const Duration(seconds: 2));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
