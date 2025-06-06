import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ShareService {
  /// Share a message with external apps
  static Future<void> shareMessage(
    BuildContext context,
    Map<String, dynamic> message,
    String baseUrl,
  ) async {
    try {
      final messageType = message['mediaType'] as String?;
      final content = message['content'] as String? ?? '';
      final mediaUrl = message['mediaUrl'] as String?;
      final senderName =
          '${message['firstName'] ?? ''} ${message['lastName'] ?? ''}'.trim();

      // Handle different message types
      switch (messageType) {
        case 'photo':
        case 'image':
          await _shareImageMessage(content, mediaUrl, senderName, baseUrl);
          break;

        case 'video':
          await _shareVideoMessage(content, mediaUrl, senderName, baseUrl);
          break;

        case 'cloud_video':
          await _shareExternalVideoMessage(content, mediaUrl, senderName);
          break;

        default:
          // Text message or unknown type
          await _shareTextMessage(content, senderName);
          break;
      }
    } catch (e) {
      debugPrint('Error sharing message: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to share message'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Share a text message
  static Future<void> _shareTextMessage(
    String content,
    String senderName,
  ) async {
    final shareText =
        senderName.isNotEmpty ? '$senderName shared: $content' : content;

    await Share.share(shareText, subject: 'Message from FamilyNest');
  }

  /// Share an image message
  static Future<void> _shareImageMessage(
    String content,
    String? mediaUrl,
    String senderName,
    String baseUrl,
  ) async {
    if (mediaUrl == null) {
      await _shareTextMessage(content, senderName);
      return;
    }

    try {
      // Download the image
      final fullUrl =
          mediaUrl.startsWith('http') ? mediaUrl : '$baseUrl$mediaUrl';
      final response = await http.get(Uri.parse(fullUrl));

      if (response.statusCode == 200) {
        // Save to temporary directory
        final tempDir = await getTemporaryDirectory();
        final fileName = _getFileNameFromUrl(mediaUrl);
        final filePath = '${tempDir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        // Share the image with text
        final shareText =
            content.isNotEmpty
                ? (senderName.isNotEmpty
                    ? '$senderName shared: $content'
                    : content)
                : (senderName.isNotEmpty
                    ? 'Photo from $senderName'
                    : 'Photo from FamilyNest');

        await Share.shareXFiles(
          [XFile(filePath)],
          text: shareText,
          subject: 'Photo from FamilyNest',
        );
      } else {
        // Fallback to text sharing
        await _shareTextMessage(content, senderName);
      }
    } catch (e) {
      debugPrint('Error sharing image: $e');
      // Fallback to text sharing
      await _shareTextMessage(content, senderName);
    }
  }

  /// Share a video message
  static Future<void> _shareVideoMessage(
    String content,
    String? mediaUrl,
    String senderName,
    String baseUrl,
  ) async {
    if (mediaUrl == null) {
      await _shareTextMessage(content, senderName);
      return;
    }

    try {
      final fullUrl =
          mediaUrl.startsWith('http') ? mediaUrl : '$baseUrl$mediaUrl';

      // For videos, we'll share the URL directly since they can be large
      final shareText =
          content.isNotEmpty
              ? (senderName.isNotEmpty
                  ? '$senderName shared: $content\n\nVideo: $fullUrl'
                  : '$content\n\nVideo: $fullUrl')
              : (senderName.isNotEmpty
                  ? 'Video from $senderName: $fullUrl'
                  : 'Video: $fullUrl');

      await Share.share(shareText, subject: 'Video from FamilyNest');
    } catch (e) {
      debugPrint('Error sharing video: $e');
      await _shareTextMessage(content, senderName);
    }
  }

  /// Share an external video message (cloud video)
  static Future<void> _shareExternalVideoMessage(
    String content,
    String? videoUrl,
    String senderName,
  ) async {
    final shareText =
        content.isNotEmpty && videoUrl != null
            ? (senderName.isNotEmpty
                ? '$senderName shared: $content\n\nVideo: $videoUrl'
                : '$content\n\nVideo: $videoUrl')
            : (videoUrl != null
                ? (senderName.isNotEmpty
                    ? 'Video from $senderName: $videoUrl'
                    : 'Video: $videoUrl')
                : content);

    await Share.share(shareText, subject: 'Video from FamilyNest');
  }

  /// Extract filename from URL without using path package
  static String _getFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        return segments.last;
      }
      return 'shared_image.jpg';
    } catch (e) {
      return 'shared_image.jpg';
    }
  }

  static bool isValidVideoUrl(String url) {
    return url.startsWith('https://') && url.length > 10;
  }

  /// Show dialog for users to enter video URL and custom message
  static Future<String?> showVideoUrlDialog(BuildContext context) async {
    final TextEditingController urlController = TextEditingController();
    final TextEditingController messageController = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Share Video Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add a message for your video:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: messageController,
                decoration: const InputDecoration(
                  hintText: 'What would you like to say about this video?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Text(
                'Please paste the shareable link to your video:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  hintText: 'https://drive.google.com/file/d/...',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              const Text(
                'Make sure the link is publicly accessible or shared with your family.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final url = urlController.text.trim();
                final message = messageController.text.trim();
                if (url.isNotEmpty) {
                  Navigator.of(
                    context,
                  ).pop('$message|||$url'); // Use delimiter to pass both
                }
              },
              child: const Text('Share Video'),
            ),
          ],
        );
      },
    );
  }
}
