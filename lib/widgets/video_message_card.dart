import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/api_service.dart';

class VideoMessageCard extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final ApiService apiService;
  final bool isCurrentlyPlaying;
  final VoidCallback? onTap;

  const VideoMessageCard({
    Key? key,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.apiService,
    this.isCurrentlyPlaying = false,
    this.onTap,
  }) : super(key: key);

  @override
  VideoMessageCardState createState() => VideoMessageCardState();
}

class VideoMessageCardState extends State<VideoMessageCard> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _isPreloaded = false;

  @override
  void initState() {
    super.initState();
    // Pre-load the video controller for faster playback
    _preloadVideo();
  }

  @override
  void didUpdateWidget(VideoMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrentlyPlaying != oldWidget.isCurrentlyPlaying) {
      if (widget.isCurrentlyPlaying) {
        _initializePlayer();
      } else {
        _pauseAndHidePlayer();
      }
    }
  }

  Future<void> _preloadVideo() async {
    final String videoUrl =
        widget.videoUrl.startsWith('http')
            ? widget.videoUrl
            : widget.apiService.mediaBaseUrl + widget.videoUrl;

    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isPreloaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error preloading video: $e');
    }
  }

  Future<void> _initializePlayer() async {
    if (!_isPreloaded || _controller == null) {
      // Fallback: preload if not already done
      await _preloadVideo();
    }

    if (_controller != null && mounted) {
      _chewieController = ChewieController(
        videoPlayerController: _controller!,
        autoPlay: true,
        looping: false,
        aspectRatio: _controller!.value.aspectRatio,
        showControls: true,
        allowFullScreen: true,
        allowMuting: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.blue,
          handleColor: Colors.blueAccent,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.lightBlue,
        ),
      );

      setState(() {
        _isInitialized = true;
      });
    }
  }

  void _pauseAndHidePlayer() {
    _controller?.pause();
    _chewieController?.dispose();
    _chewieController = null;
    setState(() {
      _isInitialized = false;
    });
  }

  void _disposeControllers() {
    _controller?.dispose();
    _chewieController?.dispose();
    _controller = null;
    _chewieController = null;
    _isInitialized = false;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child:
            _isInitialized && _chewieController != null
                ? Chewie(controller: _chewieController!)
                : Stack(
                  alignment: Alignment.center,
                  children: [
                    // Show thumbnail if available
                    if (widget.thumbnailUrl != null &&
                        widget.thumbnailUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl:
                            widget.thumbnailUrl!.startsWith('http')
                                ? widget.thumbnailUrl!
                                : widget.apiService.mediaBaseUrl +
                                    widget.thumbnailUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder:
                            (context, url) => Container(
                              color: Colors.black54,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                        errorWidget:
                            (context, url, error) => Container(
                              color: Colors.black54,
                              child: const Icon(
                                Icons.play_circle_outline,
                                color: Colors.white,
                                size: 50,
                              ),
                            ),
                      )
                    else
                      Container(
                        color: Colors.black54,
                        child: const Icon(
                          Icons.play_circle_outline,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                    // Play button overlay
                    if (!_isInitialized)
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(12),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                  ],
                ),
      ),
    );
  }
}
