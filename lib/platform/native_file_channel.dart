import 'package:flutter/services.dart';
import 'dart:io';

/// Platform channel for communicating with native iOS/Android file access code
class NativeFileChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.anthony.familynest/files',
  );

  /// List local files (Photos on iOS, MediaStore on Android)
  /// Returns list of maps with file metadata
  static Future<List<Map<String, dynamic>>> listLocalFiles(String type) async {
    try {
      final result = await _channel.invokeMethod('listLocalFiles', {
        'type': type,
      });
      return List<Map<String, dynamic>>.from(
        result.map((item) => Map<String, dynamic>.from(item)),
      );
    } on PlatformException catch (e) {
      throw Exception('Failed to list local files: ${e.message}');
    }
  }

  /// Get actual file path for a local file (iOS only - downloads from Photos to temp)
  static Future<String> getLocalFilePath(String id) async {
    try {
      final result = await _channel.invokeMethod('getLocalFilePath', {
        'id': id,
      });
      return result as String;
    } on PlatformException catch (e) {
      throw Exception('Failed to get local file path: ${e.message}');
    }
  }

  /// List iCloud files (iOS only)
  static Future<List<Map<String, dynamic>>> listICloudFiles(String type) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('iCloud only available on iOS');
    }

    try {
      final result = await _channel.invokeMethod('listICloudFiles', {
        'type': type,
      });
      return List<Map<String, dynamic>>.from(
        result.map((item) => Map<String, dynamic>.from(item)),
      );
    } on PlatformException catch (e) {
      throw Exception('Failed to list iCloud files: ${e.message}');
    }
  }
}
