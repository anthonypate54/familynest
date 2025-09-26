import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/video_thumbnail_util.dart';
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
                    color: Colors.black.withOpacity(0.7),
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

          return CustomFullScreenVideoPlayer(
            videoUrl: widget.videoUrl,
            localMediaPath: widget.localMediaPath,
            cachedFile: _cachedVideoFile,
          );
        },
      ),
    );
  }
}

class CustomFullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? localMediaPath;
  final File? cachedFile;

  const CustomFullScreenVideoPlayer({
    super.key,
    required this.videoUrl,
    this.localMediaPath,
    this.cachedFile,
  });

  @override
  State<CustomFullScreenVideoPlayer> createState() =>
      _CustomFullScreenVideoPlayerState();
}

class _CustomFullScreenVideoPlayerState
    extends State<CustomFullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isDisposing = false;
  bool _hasEnded = false;
  String? _errorMessage;

  // For progress tracking
  double _currentPosition = 0.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  
  // Value notifiers for position tracking
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier<Duration>(Duration.zero);

  // For auto-hiding controls
  Timer? _hideControlsTimer;

  // For download/share feedback
  bool _showBubble = false;
  IconData _bubbleIcon = Icons.info;
  String _bubbleMessage = '';
  Color _bubbleColor = Colors.blue;
  Timer? _bubbleTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('[FULLSCREEN] Starting new video player');
    _initializeVideo();

    // Force play immediately and show controls
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_controller.value.isInitialized && mounted) {
        _controller.play();
        setState(() {
          _isPlaying = true;
          _showControls = true; // Show controls
        });
      }
    });
  }

  Future<void> _initializeVideo() async {
    final startTime = DateTime.now();
    debugPrint(
      '⏱️ [FLUTTER] Starting video initialization at ${startTime.millisecondsSinceEpoch}',
    );

    try {
      // Create controller based on source type
      if (widget.cachedFile != null) {
        debugPrint('[FULLSCREEN] Using cached file');
        _controller = VideoPlayerController.file(widget.cachedFile!);
      } else if (widget.localMediaPath != null) {
        debugPrint(
          '[FULLSCREEN] Using local media path: ${widget.localMediaPath}',
        );

        // Check if the local file exists before trying to use it
        final file = File(widget.localMediaPath!);
        
        try {
          // Check file details
          final exists = await file.exists();
          debugPrint('[FULLSCREEN] File exists check: $exists');
          
          if (exists) {
            final stat = await file.stat();
            debugPrint('[FULLSCREEN] File size: ${stat.size}, modified: ${stat.modified}');
            
            // Try to open the file to verify access
            final randomAccess = await file.open(mode: FileMode.read);
            await randomAccess.close();
            debugPrint('[FULLSCREEN] File access check: success');
            
            // Use the file
            _controller = VideoPlayerController.file(file);
          } else {
            // File doesn't exist, fall back to network URL
            debugPrint('[FULLSCREEN] Local file not found at: ${file.path}');
            debugPrint('[FULLSCREEN] Falling back to network URL: ${widget.videoUrl}');
            _controller = VideoPlayerController.network(widget.videoUrl);
          }
        } catch (e) {
          // File access error, fall back to network URL
          debugPrint('[FULLSCREEN] File access error: $e');
          debugPrint('[FULLSCREEN] Falling back to network URL: ${widget.videoUrl}');
          _controller = VideoPlayerController.network(widget.videoUrl);
        }
      } else {
        debugPrint('[FULLSCREEN] Using network URL: ${widget.videoUrl}');
        _controller = VideoPlayerController.network(widget.videoUrl);
      }

      // Add listener for position updates
      _controller.addListener(_videoListener);

      // Initialize and play immediately
      await _controller.initialize();
      _duration = _controller.value.duration;

      // Start playing immediately
      await _controller.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isPlaying = true;
        });
      }

      // Auto-hide controls after 3 seconds
      _startHideControlsTimer();

      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
        '⏱️ [FLUTTER] Total video initialization took: ${totalTime}ms',
      );
    } catch (e) {
      debugPrint('Error initializing video player: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _videoListener() {
    if (!mounted || _isDisposing) return;

    final position = _controller.value.position;
    final duration = _controller.value.duration;

    // Only update if there's a meaningful change
    if ((position.inMilliseconds - _position.inMilliseconds).abs() > 200) {
      setState(() {
        _position = position;
        _currentPosition = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;
      });
      
      // Update value notifiers
      _positionNotifier.value = position;
      _durationNotifier.value = duration;
    }

    // Update playing state if changed
    final isPlaying = _controller.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() {
        _isPlaying = isPlaying;
        if (isPlaying) {
          _startHideControlsTimer();
        } else {
          _hideControlsTimer?.cancel();
          _showControls = true; // Show controls when paused
        }
      });
    }

    // Check if video ended
    if (position.inMilliseconds >= duration.inMilliseconds - 200 && !isPlaying) {
      setState(() {
        _hasEnded = true;
        _showControls = true; // Show controls when ended
      });
    }
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      setState(() {
        _showControls = true;
      });
    } else {
      _controller.play();
      _startHideControlsTimer();
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls && _isPlaying) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _onSliderChanged(double value) {
    final newPosition = Duration(
      milliseconds: (value * _duration.inMilliseconds).round(),
    );
    _controller.seekTo(newPosition);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _handleBackPress() async {
    // Set flag to prevent further updates
    _isDisposing = true;

    try {
      // Cancel timers
      _hideControlsTimer?.cancel();
      _bubbleTimer?.cancel();

      // Pause video if playing
      if (_controller.value.isInitialized && _controller.value.isPlaying) {
        await _controller.pause();
        debugPrint('[FULLSCREEN] Video paused before navigation');
      }

      // Reset position and volume to help release resources
      if (_controller.value.isInitialized) {
        await _controller.seekTo(Duration.zero);
        await _controller.setVolume(0);
        debugPrint('[FULLSCREEN] Video position reset and volume muted');
      }

      // Remove listener
      _controller.removeListener(_videoListener);

      // Dispose controller
      await _controller.dispose();
      debugPrint('[FULLSCREEN] Video controller disposed');

      // Small delay to allow Android to process
      await Future.delayed(const Duration(milliseconds: 50));
    } catch (e) {
      debugPrint('[FULLSCREEN] Error during cleanup: $e');
    }

    // Navigate back
    if (mounted) Navigator.of(context).pop();
  }

  void _showFeedbackBubble({
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
      _controller.pause();
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
        _showFeedbackBubble(
          icon: Icons.error,
          message: 'Storage permission required',
          color: Colors.red,
        );
        if (wasPlaying) {
          _controller.play();
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
        _showFeedbackBubble(
          icon: Icons.check_circle,
          message: '1 video saved to your $locationMessage',
          color: Colors.green,
        );

        // Resume video after delay
        Timer(const Duration(seconds: 3), () {
          if (wasPlaying && mounted) {
            _controller.play();
          }
        });
      }
    } catch (e) {
      _showFeedbackBubble(
        icon: Icons.error,
        message: 'Download failed',
        color: Colors.red,
      );
      if (wasPlaying) {
        _controller.play();
      }
    }
  }

  Future<void> _shareVideo() async {
    // Pause video
    bool wasPlaying = _isPlaying;
    if (_isPlaying) {
      _controller.pause();
    }

    try {
      await Share.share(
        widget.videoUrl,
        subject: 'FamilyNest_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
    } catch (e) {
      _showFeedbackBubble(
        icon: Icons.error,
        message: 'Share failed',
        color: Colors.red,
      );
    }

    // Resume video
    Timer(const Duration(milliseconds: 500), () {
      if (wasPlaying && mounted) {
        _controller.play();
      }
    });
  }

  @override
  void dispose() {
    debugPrint('[FULLSCREEN] Starting video player disposal');

    // Set flag to prevent further frame processing
    bool wasPlaying = _isPlaying;
    _isPlaying = false;

    try {
      // Cancel all timers first
      _hideControlsTimer?.cancel();
      _bubbleTimer?.cancel();

      // IMPORTANT: Pause video BEFORE doing anything else if it's playing
      if (wasPlaying && _controller.value.isInitialized) {
        debugPrint('[FULLSCREEN] Pausing video before disposal');
        _controller.pause();
      }

      // Reset video position to release buffers
      if (_controller.value.isInitialized) {
        debugPrint('[FULLSCREEN] Resetting video position to release buffers');
        _controller.seekTo(Duration.zero);
        _controller.setVolume(0); // Mute to help release audio resources
      }

      // Remove listener before disposal
      _controller.removeListener(_videoListener);

      // Dispose controller
      _controller.dispose();
      debugPrint('[FULLSCREEN] Video controller disposed');

      // Dispose notifiers
      _positionNotifier.dispose();
      _durationNotifier.dispose();

      // Additional memory cleanup when leaving video player
      VideoThumbnailUtil.clearCache();

      // Force a GC if possible (this is a no-op in release mode)
      debugPrint('[FULLSCREEN] Attempting to trigger resource cleanup');
    } catch (e) {
      debugPrint('[FULLSCREEN] Error during disposal: $e');
    }

    debugPrint('[FULLSCREEN] Video player disposal complete');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _handleBackPress();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Video player
            _isInitialized
                ? Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: Stack(
                      children: [
                        // Video
                        VideoPlayer(_controller),

                        // Tap area for toggling controls
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: _toggleControls,
                            behavior: HitTestBehavior.translucent,
                            child: Container(color: Colors.transparent),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                : Center(
                  child:
                      _errorMessage != null
                          ? Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'Error: $_errorMessage',
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          )
                          : const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.blue,
                            ),
                          ),
                ),

            // Controls overlay (conditionally visible)
            if (_isInitialized && _showControls)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.4),
                  child: Stack(
                    children: [
                      // Close button (top left)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 16,
                        left: 16,
                        child: GestureDetector(
                          onTap: () {
                            // Explicitly handle back navigation with proper cleanup
                            if (_controller.value.isInitialized) {
                              // First pause the video if it's playing
                              if (_controller.value.isPlaying) {
                                _controller.pause();
                                debugPrint('[FULLSCREEN] Video paused by close button');
                              }
                              
                              // Reset position to help release buffers
                              _controller.seekTo(Duration.zero);
                              _controller.setVolume(0);
                              debugPrint('[FULLSCREEN] Video position reset by close button');
                            }
                            
                            // Then navigate after a small delay
                            Future.delayed(const Duration(milliseconds: 50), () {
                              if (mounted) Navigator.pop(context);
                            });
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
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

                      // Download and Share buttons (top right)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 16,
                        right: 16,
                        child: Row(
                          children: [
                            // Download button
                            GestureDetector(
                              onTap: _downloadVideo,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.download,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Share button
                            GestureDetector(
                              onTap: _shareVideo,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.share,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Play/pause button (center)
                      Center(
                        child: GestureDetector(
                          onTap: _togglePlayPause,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                      ),

                      // Progress bar and time (bottom)
                      Positioned(
                        bottom: MediaQuery.of(context).padding.bottom + 16,
                        left: 16,
                        right: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Progress slider
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.grey[600],
                                thumbColor: Colors.white,
                                overlayColor: Colors.white.withOpacity(0.3),
                              ),
                              child: Slider(
                                value: _currentPosition.clamp(0.0, 1.0),
                                onChanged: _onSliderChanged,
                              ),
                            ),

                            // Time indicators
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(_position),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(_duration),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Play button overlay when paused or ended
            if (_isInitialized && (!_isPlaying || _hasEnded) && !_showControls)
              Center(
                child: GestureDetector(
                  onTap: () {
                    if (_hasEnded) {
                      _controller.seekTo(Duration.zero);
                      _hasEnded = false;
                    }
                    _togglePlayPause();
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _hasEnded ? Icons.replay : Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),

            // Feedback bubble
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
      ),
    );
  }
}
