import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final bool isLocalFile;

  const VideoPlayerScreen({
    required this.videoUrl,
    this.isLocalFile = false,
    Key? key,
  }) : super(key: key);

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      if (widget.isLocalFile) {
        final videoPath = widget.videoUrl.replaceFirst('file://', '');
        debugPrint('Initializing video player with local file: $videoPath');
        _videoPlayerController = VideoPlayerController.file(File(videoPath));
      } else {
        debugPrint(
          'Initializing video player with network URL: ${widget.videoUrl}',
        );
        _videoPlayerController = VideoPlayerController.network(widget.videoUrl);
      }

      await _videoPlayerController.initialize();

      final videoAspectRatio = _videoPlayerController.value.aspectRatio;
      debugPrint('Video initialized with aspect ratio: $videoAspectRatio');

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        aspectRatio: videoAspectRatio > 0 ? videoAspectRatio : 16 / 9,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              'Error: $errorMessage',
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
        placeholder: Container(
          color: Colors.black,
          child: const Center(child: CircularProgressIndicator()),
        ),
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.blue,
          handleColor: Colors.blueAccent,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.lightBlue,
        ),
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        showControls: true,
      );

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing video player: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Video Player',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body:
          _errorMessage != null
              ? Center(
                child: Text(
                  'Error playing video: $_errorMessage',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              )
              : _isInitialized
              ? SafeArea(child: Chewie(controller: _chewieController!))
              : const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
    );
  }
}
