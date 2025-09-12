import 'dart:io';
import 'package:flutter/foundation.dart';
import '../platform/native_file_channel.dart';
import 'cloud_file_service.dart';

/// Service for accessing iCloud Drive files (iOS only)
class ICloudService {
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25MB

  /// Get list of iCloud Drive photo or video files
  Future<List<CloudFile>> getFiles(String type) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('iCloud only available on iOS');
    }

    try {
      debugPrint('☁️ Searching iCloud Drive for $type files...');
      final rawFiles = await NativeFileChannel.listICloudFiles(type);
      final cloudFiles =
          rawFiles
              .map((fileData) => _mapToCloudFile(fileData))
              .where((file) => file.isWithinSizeLimit)
              .toList();

      debugPrint('☁️ Found ${cloudFiles.length} iCloud $type files under 25MB');

      // Note: iOS restricts third-party apps to their own iCloud container
      // Main iCloud Drive access requires Document Picker (file selection by user)
      if (cloudFiles.isEmpty) {
        debugPrint(
          'ℹ️ iCloud Drive files require user selection via Document Picker',
        );
      }

      return cloudFiles;
    } catch (e) {
      debugPrint('$e');
      rethrow;
    }
  }

  /// Get actual file path for usage (iCloud files are already local paths)
  Future<String?> getFileForUsage(CloudFile file) async {
    if (file.provider != 'icloud') {
      throw ArgumentError('File is not from iCloud provider');
    }

    try {
      // iCloud files in Documents folder are already accessible via local path
      return file.localPath;
    } catch (e) {
      debugPrint('$e');
      return null;
    }
  }

  CloudFile _mapToCloudFile(Map<String, dynamic> fileData) {
    return CloudFile(
      id: fileData['id'] as String,
      name: fileData['name'] as String,
      size: fileData['size'] as int,
      localPath: fileData['path'] as String?,
      mimeType: fileData['mimeType'] as String,
      provider: 'icloud',
    );
  }
}
