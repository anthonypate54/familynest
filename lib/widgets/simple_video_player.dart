import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/video_thumbnail_util.dart';
import '../utils/video_controller_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class SimpleVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? localMediaPath;
  final String? thumbnailUrl;
  final double height;
  final bool autoPlay;

  const SimpleVideoPlayer({
    super.key,
    required this.videoUrl,
    this.localMediaPath,
    this.thumbnailUrl,
    this.height = 250,
    this.autoPlay = false,
  });

  @override
  State<SimpleVideoPlayer> createState() => _SimpleVideoPlayerState();
}

class _SimpleVideoPlayerState extends State<SimpleVideoPlayer> {
  File? _cachedVideoFile;

  @override
  void initState() {
    super.initState();
    _preloadVideo(); // Start downloading immediately
  }

  Future<void> _preloadVideo() async {
    try {
      final response = await http.get(Uri.parse(widget.videoUrl));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = 'cached_${widget.videoUrl.hashCode}.mp4';
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);
        if (mounted) {
          setState(() {
            _cachedVideoFile = file;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to preload video: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Thumbnail background
            if (widget.thumbnailUrl != null)
              CachedNetworkImage(
                imageUrl: widget.thumbnailUrl!,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                placeholder:
                    (context, url) => Container(
                      color: Colors.grey[300],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                errorWidget:
                    (context, url, error) => Container(
                      color: Colors.grey[300],
                      child: const Center(child: Icon(Icons.error)),
                    ),
              ),

            // Play button overlay
            Center(
              child: GestureDetector(
                onTap: _openFullScreenPlayer,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullScreenPlayer() {
    final tapTime = DateTime.now();
    debugPrint(
      '⏱️ [FLUTTER] User tapped video at ${tapTime.millisecondsSinceEpoch}',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          final buildTime = DateTime.now();
          debugPrint(
            '⏱️ [FLUTTER] Building FullScreenVideoPlayer at ${buildTime.millisecondsSinceEpoch}',
          );
          debugPrint(
            '⏱️ [FLUTTER] Navigation took: ${buildTime.difference(tapTime).inMilliseconds}ms',
          );

          return FullScreenVideoPlayer(
            videoUrl: widget.videoUrl,
            localMediaPath: widget.localMediaPath,
            thumbnailUrl: widget.thumbnailUrl,
            cachedFile: _cachedVideoFile, // Pass cached file if available
          );
        },
      ),
    );
  }
}

class FullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? localMediaPath;
  final String? thumbnailUrl;
  final File? cachedFile;

  const FullScreenVideoPlayer({
    super.key,
    required this.videoUrl,
    this.localMediaPath,
    this.thumbnailUrl,
    this.cachedFile,
  });

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _hasEnded = false;
  Timer? _hideControlsTimer;
  Timer? _progressTimer;

  // Use ValueNotifier for progress updates to avoid rebuilding entire widget
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(
    Duration.zero,
  );
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(
    Duration.zero,
  );

  // Download/Share state
  bool _showBubble = false;
  IconData _bubbleIcon = Icons.download;
  String _bubbleMessage = '';
  Color _bubbleColor = Colors.blue;
  Timer? _bubbleTimer;

  @override
  void initState() {
    super.initState();
    // Proactive memory cleanup before opening new video
    VideoThumbnailUtil.clearCache();

    debugPrint('[FULLSCREEN] Starting new video player');
    _initializeVideo();
  }

  @override
  void dispose() {
    debugPrint('[FULLSCREEN] Starting video player disposal');

    // Cancel all timers first
    _hideControlsTimer?.cancel();
    _progressTimer?.cancel();
    _bubbleTimer?.cancel();

    // Remove listener before disposal
    _controller?.removeListener(_videoListener);

    // Don't dispose controllers here - they're managed by VideoControllerManager
    _chewieController = null;
    _controller = null;

    // Dispose notifiers
    _positionNotifier.dispose();
    _durationNotifier.dispose();

    // Additional memory cleanup when leaving video player
    VideoThumbnailUtil.clearCache();

    debugPrint('[FULLSCREEN] Video player disposal complete');

    super.dispose();
  }

  Future<void> _initializeVideo() async {
    final startTime = DateTime.now();
    debugPrint(
      '⏱️ [FLUTTER] Starting video initialization at ${startTime.millisecondsSinceEpoch}',
    );

    try {
      final controllerManager = VideoControllerManager();

      final initializeStart = DateTime.now();
      _controller = await controllerManager.getController(
        widget.videoUrl,
        localPath: widget.localMediaPath,
      );
      final initializeEnd = DateTime.now();
      debugPrint(
        '⏱️ [FLUTTER] Controller.initialize() took: ${initializeEnd.difference(initializeStart).inMilliseconds}ms',
      );

      if (_controller == null) {
        debugPrint('[FULLSCREEN] Failed to create video controller');
        return;
      }

      final chewieStart = DateTime.now();
      _chewieController = controllerManager.createChewieController(
        _controller!,
      );
      final chewieEnd = DateTime.now();
      debugPrint(
        '⏱️ [FLUTTER] Chewie creation took: ${chewieEnd.difference(chewieStart).inMilliseconds}ms',
      );

      _controller!.addListener(_videoListener);
      setState(() {
        _isInitialized = true;
      });

      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
        '⏱️ [FLUTTER] Total video initialization took: ${totalTime}ms',
      );
    } catch (e) {
      debugPrint('$e');
    }
  }

  void _videoListener() {
    if (_controller != null && mounted) {
      final bool isPlaying = _controller!.value.isPlaying;
      final bool hasEnded =
          _controller!.value.position >= _controller!.value.duration;

      if (isPlaying != _isPlaying || hasEnded != _hasEnded) {
        setState(() {
          _isPlaying = isPlaying;
          _hasEnded = hasEnded;
          if (hasEnded) {
            _showControls = true;
          }
        });
      }
    }
  }

  void _playPause() {
    if (_controller != null && _controller!.value.isInitialized) {
      if (_isPlaying) {
        _controller!.pause();
      } else {
        // Check if we're at the very end (within 100ms)
        final position = _controller!.value.position;
        final duration = _controller!.value.duration;
        final isAtEnd =
            position.inMilliseconds >= (duration.inMilliseconds - 100);

        if (isAtEnd) {
          // For ended videos, seek to beginning first
          _controller!.seekTo(Duration.zero).then((_) {
            _controller!.play();
          });
        } else {
          _controller!.play();
        }
      }
    }
  }

  void _showControlsTemporarily() {
    setState(() {
      _showControls = true;
    });
    _startHideControlsTimer();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showDownloadBubble({
    required IconData icon,
    required String message,
    required Color color,
    int duration = 3000,
  }) {
    setState(() {
      _showBubble = true;
      _bubbleIcon = icon;
      _bubbleMessage = message;
      _bubbleColor = color;
    });

    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(Duration(milliseconds: duration), () {
      if (mounted) {
        setState(() {
          _showBubble = false;
        });
      }
    });
  }

  Future<void> _downloadVideo() async {
    // Pause video
    bool wasPlaying = _isPlaying;
    if (_isPlaying) {
      _controller!.pause();
    }

    try {
      // Request permissions
      late PermissionStatus permission;
      if (Platform.isAndroid) {
        if (await Permission.manageExternalStorage.isGranted) {
          permission = PermissionStatus.granted;
        } else {
          permission = await Permission.manageExternalStorage.request();
          if (permission != PermissionStatus.granted) {
            permission = await Permission.storage.request();
          }
        }
      } else {
        permission = PermissionStatus.granted;
      }

      if (permission != PermissionStatus.granted) {
        _showDownloadBubble(
          icon: Icons.error,
          message: 'Storage permission required',
          color: Colors.red,
        );
        if (wasPlaying) {
          _controller!.play();
        }
        return;
      }

      // Download video
      final response = await http
          .get(Uri.parse(widget.videoUrl))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        // Get download directory
        Directory downloadDir;
        if (Platform.isAndroid) {
          downloadDir = Directory('/storage/emulated/0/Download/FamilyNest');
        } else {
          final appDir = await getApplicationDocumentsDirectory();
          downloadDir = Directory('${appDir.path}/FamilyNest');
        }

        if (!downloadDir.existsSync()) {
          downloadDir.createSync(recursive: true);
        }

        // Save file
        final fileName =
            'FamilyNest_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final file = File('${downloadDir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);

        // Show success
        final locationMessage =
            Platform.isAndroid
                ? 'Saved to Downloads/FamilyNest'
                : 'Saved to FamilyNest folder';
        _showDownloadBubble(
          icon: Icons.check_circle,
          message: '1 video saved to your $locationMessage',
          color: Colors.green,
        );

        // Resume video after delay
        Timer(const Duration(seconds: 3), () {
          if (wasPlaying && mounted) {
            _controller!.play();
          }
        });
      }
    } catch (e) {
      _showDownloadBubble(
        icon: Icons.error,
        message: 'Download failed',
        color: Colors.red,
      );
      if (wasPlaying) {
        _controller!.play();
      }
    }
  }

  Future<void> _shareVideo() async {
    // Pause video
    bool wasPlaying = _isPlaying;
    if (_isPlaying) {
      _controller!.pause();
    }

    try {
      await Share.share(
        widget.videoUrl,
        subject: 'FamilyNest_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
    } catch (e) {
      _showDownloadBubble(
        icon: Icons.error,
        message: 'Share failed',
        color: Colors.red,
      );
    }

    // Resume video
    Timer(const Duration(milliseconds: 500), () {
      if (wasPlaying && mounted) {
        _controller!.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main video area
          Center(
            child: GestureDetector(
              onTap: () {
                if (_isInitialized) {
                  if (_isPlaying) {
                    _showControlsTemporarily();
                  } else {
                    _playPause();
                  }
                }
              },
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black,
                child:
                    _isInitialized && _chewieController != null
                        ? AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: Chewie(controller: _chewieController!),
                        )
                        : Stack(
                          children: [
                            // Show thumbnail as background while loading
                            if (widget.thumbnailUrl != null)
                              CachedNetworkImage(
                                imageUrl: widget.thumbnailUrl!,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                placeholder:
                                    (context, url) => Container(
                                      color: Colors.black,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                errorWidget:
                                    (context, url, error) => Container(
                                      color: Colors.black,
                                      child: const Center(
                                        child: Icon(
                                          Icons.video_library,
                                          color: Colors.white,
                                          size: 48,
                                        ),
                                      ),
                                    ),
                              )
                            else
                              Container(
                                color: Colors.black,
                                child: const Center(
                                  child: Icon(
                                    Icons.video_library,
                                    color: Colors.white,
                                    size: 48,
                                  ),
                                ),
                              ),

                            // Loading overlay with play icon
                            Container(
                              color: Colors.black.withValues(alpha: 0.3),
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Loading video...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
              ),
            ),
          ),

          // Controls overlay
          if (_isInitialized && (_showControls || !_isPlaying || _hasEnded))
            Stack(
              children: [
                // Close button (top-left)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),

                // Play/Pause button (center)
                Center(
                  child: GestureDetector(
                    onTap: _playPause,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        !_isPlaying ? Icons.play_arrow : Icons.pause,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                ),

                // Bottom controls
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Download and Share buttons
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _downloadVideo,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.download,
                                  color: Colors.black,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: _shareVideo,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.share,
                                  color: Colors.black,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Progress bar with time markers - using built-in VideoProgressIndicator
                        Row(
                          children: [
                            Text(
                              _formatDuration(_controller!.value.position),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: VideoProgressIndicator(
                                _controller!,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: Colors.white,
                                  bufferedColor: Colors.white54,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDuration(_controller!.value.duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

          // Download bubble
          if (_showBubble)
            Positioned(
              bottom: 60,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _bubbleColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_bubbleIcon, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _bubbleMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
