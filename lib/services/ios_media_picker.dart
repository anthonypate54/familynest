import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
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
    required String type, // 'photo', 'video', or 'media' (both)
    required Function() onShowPicker, // Callback to re-show picker if needed
  }) async {
    try {
      // For 'media' type, go directly to Files (Google Messages style)
      if (type == 'media') {
        return await _pickFromFiles(context, type, onShowPicker);
      }

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
                    'Select ${type == 'photo'
                        ? 'Photo'
                        : type == 'video'
                        ? 'Video'
                        : 'Media'}',
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
                            : type == 'video'
                            ? Icons.video_library
                            : Icons.perm_media,
                    title:
                        type == 'photo'
                            ? 'Photos'
                            : type == 'video'
                            ? 'Videos'
                            : 'Media',
                    subtitle:
                        type == 'photo'
                            ? 'From your photo library'
                            : type == 'video'
                            ? 'From your video library'
                            : 'Photos and videos from your device',
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

      if (!context.mounted) return null;

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

  // Check permissions
  static Future<bool> _checkPermissions() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      debugPrint('🍎 Photo library permission denied');
      return false;
    }
    return true;
  }

  /// Pick from iOS Photos app using standard ImagePicker
  static Future<File?> _pickFromPhotos(
    BuildContext context,
    String type,
    Function() onShowPicker,
  ) async {
    if (!(await _checkPermissions())) return null;
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
      } else if (type == 'video') {
        pickedFile = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 10),
        );
      } else {
        // type == 'media' - use pickMultipleMedia for unified photo+video selection
        final List<XFile> mediaList = await picker.pickMultipleMedia(
          imageQuality: 85,
          limit: 2, // Minimum allowed limit
        );

        if (mediaList.isNotEmpty) {
          pickedFile = mediaList.first; // Use first selected media
        }
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
        // For media type, determine if it's a photo or video based on file extension
        final String extension = pickedFile.path.toLowerCase();
        final bool isVideo =
            extension.endsWith('.mp4') ||
            extension.endsWith('.mov') ||
            extension.endsWith('.avi') ||
            extension.endsWith('.wmv');

        if (type == 'photo' || (type == 'media' && !isVideo)) {
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
                await _showShareAsLinkDialog(context);
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

      // Check if size limit was exceeded in native code
      final bool sizeLimitExceeded = cloudFileData['sizeLimitExceeded'] == true;

      // Detect actual file type from MIME type
      String actualType = type;
      if (cloudFile.mimeType.startsWith('image/')) {
        actualType = 'photo';
      } else if (cloudFile.mimeType.startsWith('video/')) {
        actualType = 'video';
      }

      // Filter by type if needed
      bool isCorrectType;
      if (type == 'photo') {
        isCorrectType = cloudFile.mimeType.startsWith('image/');
      } else if (type == 'video') {
        isCorrectType = cloudFile.mimeType.startsWith('video/');
      } else {
        // type == 'media' - accept both images and videos
        isCorrectType =
            cloudFile.mimeType.startsWith('image/') ||
            cloudFile.mimeType.startsWith('video/');
      }

      if (!isCorrectType) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Please select a ${type == 'photo'
                    ? 'photo'
                    : type == 'video'
                    ? 'video'
                    : 'photo or video'} file',
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
                await _showShareAsLinkDialog(context);
              }
              onShowPicker();
            }
          }
          return null;
        }
      }

      if (cloudFile.localPath == null || sizeLimitExceeded) {
        if (sizeLimitExceeded) {
          // File was too large - show the large video dialog
          final double fileSizeMB = cloudFile.size / (1024 * 1024);
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
          } else {
            // Video too large - show dialog
            if (context.mounted) {
              final action = await LargeVideoDialog.show(context, fileSizeMB);

              if (action == VideoSizeAction.chooseDifferent) {
                onShowPicker();
              } else if (action == VideoSizeAction.shareAsLink) {
                if (context.mounted) {
                  await _showShareAsLinkDialog(context);
                }
                // Don't call onShowPicker() - just return to message screen
              }
            }
          }
        } else {
          // Actual file access error
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to access selected file'),
                duration: Duration(seconds: 2),
              ),
            );
          }
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
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
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

  /// Shows a simple dialog explaining how to share large videos via link
  static Future<void> _showShareAsLinkDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.link, color: Colors.blue, size: 28),
              SizedBox(width: 8),
              Text('Share as Link'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your video is too large to upload directly.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 16),
              Text(
                'To share it:',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 8),
              Text(
                '1. Copy the sharing link from your cloud storage (Google Drive, Dropbox, etc.)',
              ),
              SizedBox(height: 8),
              Text('2. Paste the link directly in the message text area below'),
              SizedBox(height: 16),
              Text(
                'The link will work for anyone who has access to view the file.',
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }
}
