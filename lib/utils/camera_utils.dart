import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/custom_video_recorder.dart';

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
}
