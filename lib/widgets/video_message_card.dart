import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
  bool _isInitialized = false;
  bool _isPreloaded = false;

  @override
  void initState() {
    super.initState();
    debugPrint('💾 VideoMessageCard: Viewport-based loading enabled');
  }

  // Called when video enters/exits viewport
  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;

    final visiblePercentage = info.visibleFraction * 100;
    debugPrint('🔍 Video visibility: ${visiblePercentage.toStringAsFixed(1)}%');

    if (visiblePercentage > 80) {
      // Video is more than 80% visible - preload if not already done
      if (!_isPreloaded && !widget.isCurrentlyPlaying) {
        debugPrint(
          '👀 Video entered viewport - preloading for: ${widget.videoUrl}',
        );
        _preloadVideo();
      }
    } else if (visiblePercentage < 10) {
      // Video is barely visible - dispose to save memory
      if (_isPreloaded && !widget.isCurrentlyPlaying) {
        debugPrint('👋 Video left viewport - disposing');
        _disposeControllers();
      }
    }
  }

  @override
  void didUpdateWidget(VideoMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrentlyPlaying != oldWidget.isCurrentlyPlaying) {
      if (widget.isCurrentlyPlaying) {
        debugPrint('🎬 Initializing video player for: ${widget.videoUrl}');
        _initializePlayer();
      } else {
        debugPrint('⏹️ Disposing video player (another video playing)');
        _pauseAndHidePlayer();
      }
    }
  }

  Future<void> _preloadVideo() async {
    // CHECK: Can we safely create another controller?
    if (!VideoControllerManager.canCreateController()) {
      debugPrint(
        '🚫 BLOCKED video creation: ${VideoControllerManager.activeControllerCount} controllers already active [${widget.videoUrl.split('/').last}]',
      );
      return;
    }

    final String videoUrl =
        widget.videoUrl.startsWith('http')
            ? widget.videoUrl
            : widget.apiService.mediaBaseUrl + widget.videoUrl;

    try {
      debugPrint('🎬 CREATING VideoPlayerController for: $videoUrl');

      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      VideoControllerManager.onControllerCreated(videoUrl);

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isPreloaded = true;
        });
        debugPrint(
          '✅ VideoPlayerController CREATED and INITIALIZED for: $videoUrl',
        );
      }
    } catch (e) {
      debugPrint('❌ Error preloading video: $e');
      // If creation failed, don't count it
      if (_controller != null) {
        VideoControllerManager.onControllerDisposed(videoUrl);
      }
    }
  }

  Future<void> _initializePlayer() async {
    // Dispose any existing controller first to ensure fresh initialization
    _chewieController?.dispose();
    _chewieController = null;

    if (!_isPreloaded || _controller == null) {
      // Fallback: preload if not already done
      await _preloadVideo();
    }

    if (_controller != null && mounted) {
      debugPrint('🎬 CREATING ChewieController');
      _chewieController = ChewieController(
        videoPlayerController: _controller!,
        autoPlay: true,
        looping: false,
        aspectRatio: _controller!.value.aspectRatio,
        showControls: true,
        allowFullScreen: true,
        allowMuting: true,
        // Force material controls to avoid iOS cupertino overflow issues
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
    debugPrint('🗑️ DISPOSING controllers for: ${widget.videoUrl}');

    // Dispose in correct order: Chewie first, then VideoPlayer
    if (_chewieController != null) {
      debugPrint('🗑️ Disposing ChewieController');
      _chewieController!.dispose();
      _chewieController = null;
    }

    if (_controller != null) {
      debugPrint('🗑️ Disposing VideoPlayerController');
      _controller!.dispose();
      _controller = null;

      // Track disposal in manager
      final videoUrl =
          widget.videoUrl.startsWith('http')
              ? widget.videoUrl
              : widget.apiService.mediaBaseUrl + widget.videoUrl;
      VideoControllerManager.onControllerDisposed(videoUrl);
    }

    _isInitialized = false;
    _isPreloaded = false;

    debugPrint('✅ DISPOSAL COMPLETE for: ${widget.videoUrl}');
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('video_${widget.videoUrl}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          height: 200,
          constraints: const BoxConstraints(
            minWidth: 280, // Ensure minimum width for video controls
          ),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child:
                _isInitialized && _chewieController != null
                    ? Theme(
                      data: ThemeData(
                        platform:
                            TargetPlatform.android, // Force Material controls
                      ),
                      child: Chewie(controller: _chewieController!),
                    )
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
                        // Play button overlay - only when not playing
                        if (!_isInitialized)
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
      ),
    );
  }
}
