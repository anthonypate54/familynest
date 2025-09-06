import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../utils/video_controller_manager.dart';

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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  // Called when video enters/exits viewport
  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;

    // Only dispose when video is completely out of view
    if (info.visibleFraction == 0 && _controller != null) {
      // Video is no longer visible - dispose controller
      _disposeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    if (_isLoading) return; // Prevent multiple initializations

    setState(() {
      _isLoading = true;
    });

    try {
      final String videoUrl =
          widget.videoUrl.startsWith('http')
              ? widget.videoUrl
              : widget.apiService.mediaBaseUrl + widget.videoUrl;

      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _chewieController = ChewieController(
            videoPlayerController: _controller!,
            autoPlay: true, // Auto-play when initialized
            autoInitialize: false,
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
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error initializing video: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _disposeVideo();
    }
  }

  void _disposeVideo() {
    _controller?.pause();
    _controller?.dispose();
    _chewieController?.dispose();
    if (mounted) {
      setState(() {
        _controller = null;
        _chewieController = null;
        _isLoading = false;
      });
    }
  }

  void _playVideo() async {
    if (_isLoading) return; // Don't allow multiple taps while loading

    // Dispose any existing videos first via global manager
    if (mounted) {
      final videoManager = Provider.of<VideoControllerManager>(
        context,
        listen: false,
      );
      videoManager.stopAllVideos();
    }

    // Initialize and play this video
    await _initializeVideo();
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('video_${widget.videoUrl}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: _playVideo,
        child:
            _chewieController != null
                ? Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Theme(
                      data: ThemeData(
                        platform:
                            TargetPlatform.android, // Force Material controls
                      ),
                      child: Chewie(controller: _chewieController!),
                    ),
                  ),
                )
                : Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Stack(
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
                      const Center(
                        child: Icon(
                          Icons.play_circle_outline,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}
