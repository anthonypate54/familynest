import 'package:flutter/material.dart';
import 'widgets/video_message_card.dart';
import 'services/api_service.dart';

class TestVideoScreen extends StatelessWidget {
  const TestVideoScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Video')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: VideoMessageCard(
            videoUrl:
                'https://familynesngrok.ngrok.io/uploads/videos/1756256100980_33.mp4',
            apiService: ApiService(),
          ),
        ),
      ),
    );
  }
}
