import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../services/api_service.dart';

class VideoMessageCard extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final ApiService apiService;
  final bool isCurrentlyPlaying;

  const VideoMessageCard({
    Key? key,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.apiService,
    this.isCurrentlyPlaying = false,
  }) : super(key: key);

  @override
  VideoMessageCardState createState() => VideoMessageCardState();
}

class VideoMessageCardState extends State<VideoMessageCard> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  bool _isPlaying = false;
  String? _errorMessage;

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
        _controller?.dispose();
        _chewieController?.dispose();
        _controller = null;
        _chewieController = null;
        setState(() {
          _isPlaying = false;
        });
      }
    }
  }

  void _initializeVideo() async {
    final String displayUrl =
        widget.videoUrl.startsWith('http')
            ? widget.videoUrl
            : widget.apiService.mediaBaseUrl + widget.videoUrl;

    _controller = VideoPlayerController.networkUrl(Uri.parse(displayUrl));

    try {
      await _controller!.initialize();
      if (mounted) {
        _chewieController = ChewieController(
          videoPlayerController: _controller!,
          autoPlay: true,
          looping: false,
          aspectRatio: _controller!.value.aspectRatio,
          showControls: true,
          allowFullScreen: true,
          allowMuting: true,
        );
        setState(() {
          _isPlaying = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load video: $error';
        });
      }
    }

    _controller?.addListener(() {
      if (_controller!.value.hasError && mounted) {
        setState(() {
          _errorMessage = _controller!.value.errorDescription;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return VisibilityDetector(
      key: Key('video-${widget.videoUrl}'),
      onVisibilityChanged: (VisibilityInfo info) {
        // If video becomes less than 50% visible and is playing, pause it
        if (info.visibleFraction < 0.5 && _isPlaying && _controller != null) {
          _controller!.pause();
          debugPrint(
            '📱 Video paused due to scroll (${(info.visibleFraction * 100).toStringAsFixed(1)}% visible)',
          );
        }
        // If video becomes more than 50% visible and should be playing, resume
        else if (info.visibleFraction >= 0.5 &&
            widget.isCurrentlyPlaying &&
            _controller != null &&
            !_controller!.value.isPlaying) {
          _controller!.play();
          debugPrint(
            '📱 Video resumed due to scroll (${(info.visibleFraction * 100).toStringAsFixed(1)}% visible)',
          );
        }
      },
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child:
              _isPlaying && _chewieController != null
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
      ),
    );
  }
}
