import 'package:flutter/material.dart';
import '../config/ui_config.dart';

class ComposeMessageScreen extends StatelessWidget {
  const ComposeMessageScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UIConfig.useDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: UIConfig.useDarkMode ? Colors.black : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // TODO: Handle post action
            },
            child: const Text(
              'Post',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade200,
                  radius: 24,
                  backgroundImage: null, // TODO: Use user photo if available
                  child: const Text(
                    'U',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    maxLines: null,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: const InputDecoration(
                      hintText: "What's happening?",
                      hintStyle: TextStyle(color: Colors.white54, fontSize: 18),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Placeholder for media options row
            const Row(
              children: <Widget>[
                Icon(Icons.public, color: Colors.blue, size: 18),
                SizedBox(width: 8),
                Text(
                  'Everyone can reply',
                  style: TextStyle(color: Colors.blue, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.text_fields, color: Colors.blue),
                SizedBox(width: 16),
                Icon(Icons.image_outlined, color: Colors.blue),
                SizedBox(width: 16),
                Icon(Icons.gif_box_outlined, color: Colors.blue),
                SizedBox(width: 16),
                Icon(Icons.poll_outlined, color: Colors.blue),
                SizedBox(width: 16),
                Icon(Icons.location_on_outlined, color: Colors.blue),
                SizedBox(width: 16),
                Icon(Icons.add_circle_outline, color: Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
