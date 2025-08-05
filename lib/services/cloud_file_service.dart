import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'local_file_service.dart';
import 'google_drive_service.dart';
import 'icloud_service.dart';

/// Represents a file from any source (local, cloud, etc.)
class CloudFile {
  final String id;
  final String name;
  final int size;
  final String? downloadUrl;
  final String? localPath;
  final String mimeType;
  final String provider; // 'local', 'google_drive', 'icloud'

  CloudFile({
    required this.id,
    required this.name,
    required this.size,
    this.downloadUrl,
    this.localPath,
    required this.mimeType,
    required this.provider,
  });

  /// Check if file size is within our limits (25MB like Google Messages)
  bool get isWithinSizeLimit => size <= 25 * 1024 * 1024;

  /// Get file size in MB for display
  double get sizeInMB => size / (1024 * 1024);

  @override
  String toString() {
    return 'CloudFile(name: $name, size: ${sizeInMB.toStringAsFixed(2)}MB, provider: $provider)';
  }
}

/// Main service for handling file selection from multiple sources
class CloudFileService {
  static const int maxFileSizeBytes =
      25 * 1024 * 1024; // 25MB like Google Messages

  // Platform channel for native file access
  static const platform = MethodChannel('com.anthony.familynest/files');

  // Service instances
  final LocalFileService _localFileService = LocalFileService();
  final GoogleDriveService _googleDriveService = GoogleDriveService();
  final ICloudService _icloudService = ICloudService();

  /// Get list of available file providers for current platform
  List<String> getAvailableProviders() {
    final providers = ['local', 'google_drive'];

    // iCloud only available on iOS
    if (Platform.isIOS) {
      providers.add('icloud');
    }

    // Document picker is available on all platforms
    providers.add('document_picker');

    return providers;
  }

  /// Use native Document Picker for immediate file access (like Google Messages)
  /// This is the fast alternative to the slow file_picker package
  /// Works on both iOS and Android
  Future<List<CloudFile>> browseDocuments() async {
    debugPrint('📄 CloudFileService.browseDocuments called');

    try {
      final result = await platform.invokeMethod('browseDocuments');
      debugPrint('📄 Raw document picker result: $result');
      debugPrint('📄 Result type: ${result.runtimeType}');
      if (result is List) {
        debugPrint('📄 Document picker returned: ${result.length} files');
      }

      if (result is List) {
        return result.map<CloudFile>((fileData) {
          final data = Map<String, dynamic>.from(fileData);
          return CloudFile(
            id: data['id'] ?? '',
            name: data['name'] ?? 'Unknown',
            size: data['size'] ?? 0,
            localPath: data['path'],
            mimeType: data['mimeType'] ?? 'application/octet-stream',
            provider: 'document_picker',
          );
        }).toList(); // Don't filter by size here - let UI handle it
      } else {
        debugPrint('📄 Unexpected result type: ${result.runtimeType}');
        return [];
      }
    } catch (e) {
      debugPrint('📄 Error in browseDocuments: $e');
      return [];
    }
  }

  /// Get files from a specific provider
  Future<List<CloudFile>> getFiles({
    required String provider,
    required String type, // 'photo' or 'video'
  }) async {
    debugPrint(
      '🔍 CloudFileService.getFiles called with provider: $provider, type: $type',
    );
    switch (provider) {
      case 'local':
        debugPrint('📱 Routing to local file service');
        return await _getLocalFiles(type);
      case 'google_drive':
        debugPrint('☁️ Routing to Google Drive service');
        return await _getGoogleDriveFiles(type);
      case 'icloud':
        if (Platform.isIOS) {
          return await _getICloudFiles(type);
        }
        throw UnsupportedError('iCloud only available on iOS');
      case 'document_picker':
        return await browseDocuments();
      default:
        throw UnsupportedError('Provider $provider not supported');
    }
  }

  /// Get file path/URL for actual usage (download if needed)
  Future<String?> getFileForUsage(CloudFile file) async {
    switch (file.provider) {
      case 'local':
        return await _localFileService.getFileForUsage(file);
      case 'google_drive':
        return await _downloadGoogleDriveFile(file);
      case 'icloud':
        return await _icloudService.getFileForUsage(file);
      case 'document_picker':
        // Document picker files already have direct access via localPath
        return file.localPath;
      default:
        return null;
    }
  }

  // Private methods - will be implemented via individual services
  Future<List<CloudFile>> _getLocalFiles(String type) async {
    return await _localFileService.getFiles(type);
  }

  Future<List<CloudFile>> _getGoogleDriveFiles(String type) async {
    debugPrint(
      '🔗 CloudFileService._getGoogleDriveFiles calling GoogleDriveService.getFiles',
    );
    return await _googleDriveService.getFiles(type);
  }

  Future<List<CloudFile>> _getICloudFiles(String type) async {
    debugPrint(
      '☁️ CloudFileService._getICloudFiles calling ICloudService.getFiles',
    );
    return await _icloudService.getFiles(type);
  }

  Future<String?> _downloadGoogleDriveFile(CloudFile file) async {
    return await _googleDriveService.downloadFile(file);
  }
}
