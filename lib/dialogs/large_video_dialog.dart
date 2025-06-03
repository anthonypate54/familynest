import 'package:flutter/material.dart';

enum VideoSizeAction { shareAsLink, chooseDifferent, cancel }

class LargeVideoDialog {
  static Future<VideoSizeAction?> show(
    BuildContext context,
    double sizeMB,
  ) async {
    return showDialog<VideoSizeAction>(
      context: context,
      barrierDismissible: false, // Force user to choose
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Video Too Large'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The selected video is ${sizeMB.toStringAsFixed(1)}MB.',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Videos larger than 20MB cannot be uploaded directly.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              const Text(
                'What would you like to do?',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            // Cancel button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(VideoSizeAction.cancel);
              },
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),

            // Choose different video button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(VideoSizeAction.chooseDifferent);
              },
              child: const Text('Choose Different Video'),
            ),

            // Share as link button (primary action)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop(VideoSizeAction.shareAsLink);
              },
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Share as Link'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
