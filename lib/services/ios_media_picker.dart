import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../dialogs/large_video_dialog.dart';

class IosPickedFile {
  final String id;
  final String name;
  final int size;
  final String? localPath;
  final String mimeType;
  final String provider;

  IosPickedFile({
    required this.id,
    required this.name,
    required this.size,
    this.localPath,
    required this.mimeType,
    this.provider = 'unknown',
  });
}

class UnifiedMediaPicker {
  static const MethodChannel _channel = MethodChannel(
    'com.anthony.familynest/files',
  );

  /// Show cross-platform media picker with options for Photos app AND Files app
  static Future<File?> pickMedia({
    required BuildContext context,
    required String type, // 'photo' or 'video'
    required Function() onShowPicker, // Callback to re-show picker if needed
  }) async {
    try {
      // Show clean modal bottom sheet
      final source = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).canvasColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Select ${type == 'photo' ? 'Photo' : 'Video'}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildOptionTile(
                    context,
                    icon:
                        type == 'photo'
                            ? Icons.photo_library
                            : Icons.video_library,
                    title: 'Photos',
                    subtitle: 'From your photo library',
                    onTap: () => Navigator.pop(context, 'photos'),
                  ),
                  _buildOptionTile(
                    context,
                    icon: Icons.folder_open,
                    title: 'Files',
                    subtitle: 'From files or cloud storage',
                    onTap: () => Navigator.pop(context, 'files'),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      );

      if (source == null) return null; // User cancelled

      if (source == 'photos') {
        return await _pickFromPhotos(context, type, onShowPicker);
      } else {
        return await _pickFromFiles(context, type, onShowPicker);
      }
    } catch (e) {
      debugPrint('Error in pickMedia: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking media: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }

  /// Pick from iOS Photos app using standard ImagePicker
  static Future<File?> _pickFromPhotos(
    BuildContext context,
    String type,
    Function() onShowPicker,
  ) async {
    try {
      debugPrint('🍎 Picking $type from Photos app using ImagePicker');

      final ImagePicker picker = ImagePicker();
      XFile? pickedFile;

      if (type == 'photo') {
        pickedFile = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );
      } else {
        pickedFile = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 10),
        );
      }

      if (pickedFile == null) return null; // User cancelled

      final File file = File(pickedFile.path);
      final int fileSizeBytes = await file.length();
      final double fileSizeMB = fileSizeBytes / (1024 * 1024);

      debugPrint(
        '🍎 Selected file: ${pickedFile.name}, size: ${fileSizeMB.toStringAsFixed(1)}MB',
      );

      // Check file size
      if (fileSizeMB > AppConfig.maxFileUploadSizeMB) {
        if (type == 'photo') {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Photo too large (${fileSizeMB.toStringAsFixed(1)}MB). Please select a photo under ${AppConfig.maxFileUploadSizeMB}MB.',
                ),
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Choose Another',
                  onPressed: () => onShowPicker(),
                ),
              ),
            );
          }
          return null;
        } else {
          // Large videos - show upload dialog
          if (context.mounted) {
            final action = await LargeVideoDialog.show(context, fileSizeMB);
            if (action == VideoSizeAction.chooseDifferent) {
              onShowPicker();
            } else if (action == VideoSizeAction.shareAsLink) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Upload your video to Google Drive or Dropbox first, then select it from there.',
                    ),
                    duration: Duration(seconds: 4),
                  ),
                );
              }
              onShowPicker();
            }
          }
          return null;
        }
      }

      return file;
    } catch (e) {
      debugPrint('Error picking from Photos: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing Photos: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }

  /// Pick from Files app using UIDocumentPickerViewController
  static Future<File?> _pickFromFiles(
    BuildContext context,
    String type,
    Function() onShowPicker,
  ) async {
    try {
      debugPrint('📁 Picking from Files app');

      final List<dynamic> result = await _channel.invokeMethod(
        'browseDocuments',
      );

      if (result.isEmpty) return null; // User cancelled

      final cloudFileData = result.first;
      final IosPickedFile cloudFile = IosPickedFile(
        id: cloudFileData['id'],
        name: cloudFileData['name'],
        size: cloudFileData['size'],
        localPath: cloudFileData['path'],
        mimeType: cloudFileData['mimeType'],
        provider: 'files',
      );

      // Detect actual file type from MIME type
      String actualType = type;
      if (cloudFile.mimeType.startsWith('image/')) {
        actualType = 'photo';
      } else if (cloudFile.mimeType.startsWith('video/')) {
        actualType = 'video';
      }

      // Filter by type if needed
      bool isCorrectType =
          type == 'photo'
              ? (cloudFile.mimeType.startsWith('image/'))
              : (cloudFile.mimeType.startsWith('video/'));

      if (!isCorrectType) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Please select a ${type == 'photo' ? 'photo' : 'video'} file',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return null;
      }

      // Check file size
      final double fileSizeMB = cloudFile.size / (1024 * 1024);
      if (fileSizeMB > AppConfig.maxFileUploadSizeMB) {
        if (actualType == 'photo') {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Photo too large (${fileSizeMB.toStringAsFixed(1)}MB). Please select a photo under ${AppConfig.maxFileUploadSizeMB}MB.',
                ),
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Choose Another',
                  onPressed: () => onShowPicker(),
                ),
              ),
            );
          }
          return null;
        } else {
          if (context.mounted) {
            final action = await LargeVideoDialog.show(context, fileSizeMB);
            if (action == VideoSizeAction.chooseDifferent) {
              onShowPicker();
            } else if (action == VideoSizeAction.shareAsLink) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Upload your video to Google Drive or Dropbox first, then select it from there.',
                    ),
                    duration: Duration(seconds: 4),
                  ),
                );
              }
              onShowPicker();
            }
          }
          return null;
        }
      }

      if (cloudFile.localPath == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to access selected file'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return null;
      }

      return File(cloudFile.localPath!);
    } catch (e) {
      debugPrint('Error picking from Files: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing Files: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }

  static Widget _buildOptionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Theme.of(context).primaryColor, size: 24),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
      ),
      onTap: onTap,
    );
  }
}
