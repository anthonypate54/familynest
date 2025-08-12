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
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();
    if (widget.isCurrentlyPlaying) {
      _initializeVideo();
    }
  }

  @override
  void didUpdateWidget(VideoMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrentlyPlaying != oldWidget.isCurrentlyPlaying) {
      if (widget.isCurrentlyPlaying) {
        _initializeVideo();
      } else {
        _controller?.pause();
        _disposeControllers();
      }
    }
  }

  void _initializeVideo() async {
    if (_isDisposing) return;
    _disposeControllers();

    final String displayUrl =
        widget.videoUrl.startsWith('http')
            ? widget.videoUrl
            : widget.apiService.mediaBaseUrl + widget.videoUrl;

    _controller = VideoPlayerController.networkUrl(Uri.parse(displayUrl));

    try {
      await _controller!.initialize();
      if (mounted && !_isDisposing) {
        _chewieController = ChewieController(
          videoPlayerController: _controller!,
          autoPlay: true,
          looping: false,
          aspectRatio: _controller!.value.aspectRatio,
          showControls: true,
          showOptions: false,
          showControlsOnInitialize: false,
          hideControlsTimer: const Duration(seconds: 3),
          allowFullScreen: true,
          allowMuting: true,
          allowPlaybackSpeedChanging:
              false, // Disable to reduce control bar width
          // Custom controls that handle overflow properly
          customControls: const _CustomMaterialControls(),
          materialProgressColors: ChewieProgressColors(
            playedColor: Colors.blue,
            handleColor: Colors.blueAccent,
            backgroundColor: Colors.grey,
            bufferedColor: Colors.lightBlue,
          ),
        );
      }
    } catch (error) {
      debugPrint('Error initializing video: $error');
    }

    _controller?.addListener(_onVideoError);
  }

  void _onVideoError() {
    if (_controller?.value.hasError == true && mounted && !_isDisposing) {
      debugPrint('Video error: ${_controller!.value.errorDescription}');
    }
  }

  void _disposeControllers() {
    _controller?.removeListener(_onVideoError); // Remove listener first
    _chewieController?.dispose(); // Dispose Chewie first
    _controller?.dispose(); // Then VideoPlayer
    _chewieController = null;
    _controller = null;

    // Reset state if widget is still mounted
    if (mounted && !_isDisposing) {
      setState(() {
        // Reset any local state if needed
      });
    }
  }

  @override
  void dispose() {
    _isDisposing = true; // Set flag before disposal
    _disposeControllers(); // Use centralized disposal
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: GestureDetector(
        onTap: () {
          // Call parent callback first (to manage currentlyPlayingVideoId)
          widget.onTap?.call();

          // Then initialize this video if needed
          if (_controller == null) {
            _initializeVideo();
          }
        },
        child: Container(
          width: double.infinity,
          height: 200,
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_controller != null &&
                  _controller!.value.isInitialized &&
                  _chewieController != null)
                Container(
                  width: double.infinity,
                  height: 200,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: double.infinity,
                      height: 200,
                      child: Chewie(
                        key: ValueKey('playback-${widget.videoUrl}'),
                        controller: _chewieController!,
                      ),
                    ),
                  ),
                )
              else if (widget.thumbnailUrl != null &&
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
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                  errorWidget: (context, url, error) {
                    // Handle fake/corrupted thumbnails gracefully
                    if (error.toString().contains('Invalid image data') ||
                        error.toString().contains('Image file is corrupted') ||
                        error.toString().contains('HttpException') ||
                        url.contains(
                          '15',
                        ) || // catch any suspiciously small file references
                        error.toString().toLowerCase().contains('format')) {
                      // Show user-friendly message for corrupted thumbnails
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Video thumbnail temporarily unavailable',
                              ),
                              duration: Duration(seconds: 2),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      });
                    }
                    // Always return the default placeholder, don't log the error
                    return _buildDefaultVideoPlaceholder();
                  },
                )
              else
                _buildDefaultVideoPlaceholder(),
              if (_controller == null || !_controller!.value.isInitialized)
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultVideoPlaceholder() {
    return Container(
      width: 200,
      height: 200,
      color: Colors.black,
      child: const Center(
        child: Icon(Icons.videocam, color: Colors.white, size: 40),
      ),
    );
  }
}

/// Custom controls widget that properly handles overflow in constrained spaces
class _CustomMaterialControls extends StatefulWidget {
  const _CustomMaterialControls();

  @override
  State<_CustomMaterialControls> createState() =>
      _CustomMaterialControlsState();
}

class _CustomMaterialControlsState extends State<_CustomMaterialControls> {
  ChewieController? _chewieController;
  VideoPlayerController? _videoController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newChewieController = ChewieController.of(context);
    if (newChewieController != _chewieController) {
      _removeListener();
      _chewieController = newChewieController;
      _videoController = _chewieController?.videoPlayerController;
      _addListener();
    }
  }

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }

  void _addListener() {
    _videoController?.addListener(_videoListener);
  }

  void _removeListener() {
    _videoController?.removeListener(_videoListener);
  }

  void _videoListener() {
    if (mounted) {
      setState(() {
        // This will rebuild the widget with updated video state
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chewieController = _chewieController;
    final videoController = _videoController;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black54],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Play/Pause button (fixed width)
          SizedBox(
            width: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                videoController?.value.isPlaying == true
                    ? Icons.pause
                    : Icons.play_arrow,
                color: Colors.white,
                size: 18,
              ),
              onPressed: () {
                if (videoController?.value.isPlaying == true) {
                  videoController?.pause();
                } else {
                  videoController?.play();
                }
              },
            ),
          ),
          // Progress bar (flexible - takes remaining space)
          Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.3, // Example progress
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          // Mute button (fixed width)
          SizedBox(
            width: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                videoController?.value.volume == 0
                    ? Icons.volume_off
                    : Icons.volume_up,
                color: Colors.white,
                size: 18,
              ),
              onPressed: () {
                final currentVolume = videoController?.value.volume ?? 1.0;
                videoController?.setVolume(currentVolume == 0 ? 1.0 : 0.0);
              },
            ),
          ),
          // Fullscreen button (fixed width)
          SizedBox(
            width: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.fullscreen, color: Colors.white, size: 18),
              onPressed: () {
                chewieController?.enterFullScreen();
              },
            ),
          ),
        ],
      ),
    );
  }
}
