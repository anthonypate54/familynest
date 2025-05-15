import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final bool isLocalFile;
  final String? baseUrl;

  const VideoPlayerScreen({
    required this.videoUrl,
    this.isLocalFile = false,
    this.baseUrl,
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
        // Handle different URL formats carefully
        String fullVideoUrl;

        if (widget.videoUrl.startsWith('http')) {
          // URL is already absolute
          fullVideoUrl = widget.videoUrl;
          debugPrint('Using absolute URL: $fullVideoUrl');
        } else if (widget.videoUrl.startsWith('/')) {
          // URL is relative path starting with slash, needs base URL
          if (widget.baseUrl != null) {
            fullVideoUrl = '${widget.baseUrl}${widget.videoUrl}';
            debugPrint(
              'Converting relative URL with slash to absolute: $fullVideoUrl',
            );
          } else {
            // If no base URL provided, attempt to create a valid URL
            fullVideoUrl = 'http://localhost${widget.videoUrl}';
            debugPrint(
              '⚠️ No base URL provided for relative path. Using fallback: $fullVideoUrl',
            );
          }
        } else {
          // No leading slash, still needs base URL
          if (widget.baseUrl != null) {
            fullVideoUrl = '${widget.baseUrl}/${widget.videoUrl}';
            debugPrint(
              'Converting relative URL without slash to absolute: $fullVideoUrl',
            );
          } else {
            // If no base URL provided, attempt to create a valid URL
            fullVideoUrl = 'http://localhost/${widget.videoUrl}';
            debugPrint(
              '⚠️ No base URL provided for relative path. Using fallback: $fullVideoUrl',
            );
          }
        }

        // Final check to ensure it has http:// prefix
        if (!fullVideoUrl.startsWith('http')) {
          debugPrint(
            '⚠️ WARNING: URL still doesn\'t start with http: $fullVideoUrl',
          );
          fullVideoUrl =
              'http://' + fullVideoUrl.replaceFirst(RegExp(r'^//'), '');
          debugPrint('Fixed URL: $fullVideoUrl');
        }

        debugPrint(
          '🎥 Initializing video player with network URL: $fullVideoUrl',
        );

        // Try to parse and create the URI
        try {
          final videoUri = Uri.parse(fullVideoUrl);
          debugPrint('Video URI: $videoUri');
          _videoPlayerController = VideoPlayerController.network(fullVideoUrl);
        } catch (e) {
          debugPrint('Error parsing video URL: $e');
          throw Exception('Invalid video URL: $fullVideoUrl');
        }
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
