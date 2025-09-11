import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/custom_video_recorder.dart';
import '../config/app_config.dart';
import '../dialogs/large_video_dialog.dart';

class CameraUtils {
  /// Opens the Google Messages-style camera interface
  /// Returns the captured file path or null if cancelled
  static Future<String?> openCustomCamera(BuildContext context) async {
    try {
      final String? capturedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => const CustomVideoRecorder(),
          fullscreenDialog: true,
        ),
      );

      if (capturedPath != null && context.mounted) {
        // Validate file size for captured videos
        final validatedPath = await _validateFileSize(context, capturedPath);
        return validatedPath;
      }

      return capturedPath;
    } catch (e) {
      debugPrint('Error with custom camera: $e');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing camera: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      return null;
    }
  }

  /// Determines if a file is a video based on its extension
  static String getMediaType(String filePath) {
    String extension = filePath.toLowerCase();
    return extension.endsWith('.mp4') || extension.endsWith('.mov')
        ? 'video'
        : 'photo';
  }

  /// Shows the modernized media picker with single Camera option + gallery
  static void showModernMediaPicker({
    required BuildContext context,
    required VoidCallback onCameraPressed,
    required VoidCallback onGalleryPressed,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  onCameraPressed();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  onGalleryPressed();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Validates file size and shows appropriate dialogs for large files
  /// Returns the file path if valid, null if rejected
  static Future<String?> _validateFileSize(
    BuildContext context,
    String filePath,
  ) async {
    try {
      final file = File(filePath);
      final fileSize = await file.length();
      final fileSizeMB = fileSize / (1024 * 1024);

      debugPrint(
        '📁 File size validation: ${fileSizeMB.toStringAsFixed(1)}MB (limit: ${AppConfig.maxFileUploadSizeMB}MB)',
      );

      if (fileSizeMB > AppConfig.maxFileUploadSizeMB) {
        final String mediaType = getMediaType(filePath);

        if (mediaType == 'photo') {
          // Photos: Show error and reject
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Photo too large (${fileSizeMB.toStringAsFixed(1)}MB). Please take a photo under ${AppConfig.maxFileUploadSizeMB}MB.',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
          // Delete the oversized file
          try {
            await file.delete();
          } catch (e) {
            debugPrint('Could not delete oversized file: $e');
          }
          return null;
        } else {
          // Videos: Show large video dialog with options
          if (context.mounted) {
            final action = await LargeVideoDialog.show(context, fileSizeMB);

            if (action == VideoSizeAction.chooseDifferent || action == null) {
              // Delete the oversized file and return null
              try {
                await file.delete();
              } catch (e) {
                debugPrint('Could not delete oversized file: $e');
              }
              return null;
            } else if (action == VideoSizeAction.shareAsLink) {
              // User wants to share as link - delete file and show instructions
              try {
                await file.delete();
              } catch (e) {
                debugPrint('Could not delete oversized file: $e');
              }

              if (context.mounted) {
                await _showShareAsLinkDialog(context);
              }
              return null;
            }
          }
          return null;
        }
      }

      // File size is acceptable
      return filePath;
    } catch (e) {
      debugPrint('Error validating file size: $e');
      return filePath; // Return original path if validation fails
    }
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
