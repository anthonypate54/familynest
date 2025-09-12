import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../platform/native_file_channel.dart';
import 'cloud_file_service.dart';

/// Service for accessing local device files (Photos on iOS, MediaStore on Android)
class LocalFileService {
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25MB

  /// Get local files from device storage
  /// On iOS: accesses Photos library
  /// On Android: accesses MediaStore (internal/SD card)
  Future<List<CloudFile>> getFiles(String type) async {
    // Request permissions first
    await _requestPermissions(type);

    try {
      // Get file list from native platform
      final rawFiles = await NativeFileChannel.listLocalFiles(type);

      // Convert to CloudFile objects and filter by size
      final cloudFiles =
          rawFiles
              .map((fileData) => _mapToCloudFile(fileData))
              .where((file) => file.isWithinSizeLimit)
              .toList();

      debugPrint('Found ${cloudFiles.length} local $type files under 25MB');
      return cloudFiles;
    } catch (e) {
      debugPrint('$e');
      rethrow;
    }
  }

  /// Get actual file path for usage (downloads from Photos to temp on iOS)
  Future<String?> getFileForUsage(CloudFile file) async {
    if (file.provider != 'local') {
      throw ArgumentError('File is not from local provider');
    }

    try {
      if (Platform.isIOS) {
        // iOS: Download from Photos library to temp directory
        return await NativeFileChannel.getLocalFilePath(file.id);
      } else {
        // Android: MediaStore provides direct file paths
        return file.localPath;
      }
    } catch (e) {
      debugPrint('$e');
      return null;
    }
  }

  /// Request appropriate permissions for file access
  Future<void> _requestPermissions(String type) async {
    if (Platform.isAndroid) {
      // Android 13+ requires specific media permissions
      final permission =
          type == 'photo' ? Permission.photos : Permission.videos;

      final status = await permission.request();
      if (!status.isGranted) {
        throw Exception('Storage permission denied for $type files');
      }
    }
    // iOS permissions handled by native code
  }

  /// Convert raw platform data to CloudFile object
  CloudFile _mapToCloudFile(Map<String, dynamic> fileData) {
    return CloudFile(
      id: fileData['id'] as String,
      name: fileData['name'] as String,
      size: fileData['size'] as int,
      localPath: fileData['path'] as String?,
      mimeType: fileData['mimeType'] as String,
      provider: 'local',
    );
  }
}
