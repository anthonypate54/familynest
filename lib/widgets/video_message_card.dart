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
          showOptions: true,
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
    _chewieController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: GestureDetector(
        onTap: () {
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
                Chewie(controller: _chewieController!)
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
                  errorWidget:
                      (context, url, error) => _buildDefaultVideoPlaceholder(),
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
