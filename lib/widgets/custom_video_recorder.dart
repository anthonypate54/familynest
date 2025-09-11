import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';

class CustomVideoRecorder extends StatefulWidget {
  final String? initialMode; // 'photo' or 'video'

  const CustomVideoRecorder({super.key, this.initialMode});

  @override
  State<CustomVideoRecorder> createState() => _CustomVideoRecorderState();
}

class _CustomVideoRecorderState extends State<CustomVideoRecorder>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  VideoPlayerController? _videoController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIdx = 0;
  FlashMode _flashMode = FlashMode.off;
  double _zoomLevel = 1.0;

  bool _isRecording = false;
  bool _showPreview = false;
  String _captureMode = 'video'; // 'photo' or 'video'

  int _secondsRecorded = 0;
  Timer? _recordingTimer;

  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  String? _videoPath;

  static const int _maxRecordingSeconds = 20; // Google Messages style

  Widget _buildCaptureButton() {
    if (_captureMode == 'photo' || (_captureMode == 'video' && !_isRecording)) {
      // Waiting state (same for photo and video)
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    } else {
      // Recording state
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }
  }

  // Clean icon drawer function
  Widget videoIconDraw(String state) {
    debugPrint('DEBUG: videoIconDraw called with state: $state');
    switch (state) {
      case 'photo_ready':
      case 'video_waiting':
        // Universal waiting icon: Black circle with white border and white inner circle
        const double outerSize = 64;
        const double borderWidth = 3;
        const double padding = 6;
        const double innerSize = outerSize - (2 * borderWidth) - (2 * padding);

        return Container(
          width: outerSize,
          height: outerSize,
          decoration: BoxDecoration(
            color: Colors.black,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: borderWidth),
          ),
          child: Center(
            child: Container(
              width: innerSize,
              height: innerSize,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );

      case 'video_recording':
        // Red circle with transparent border, white square inside
        // Progress spinner will be handled separately in the Stack
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );

      default:
        return Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: Colors.grey,
            shape: BoxShape.circle,
          ),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _captureMode = widget.initialMode ?? 'photo'; // Default to photo mode
    _initializeCamera();

    // Allow all orientations for proper video recording metadata
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Initialize progress animation controller
    _progressController = AnimationController(
      duration: const Duration(seconds: _maxRecordingSeconds),
      vsync: this,
    );
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_progressController);
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('No cameras available');
        return;
      }

      // Start with back camera (usually index 0)
      _selectedCameraIdx = 0;
      await _initializeCameraController();
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _initializeCameraController() async {
    try {
      await _cameraController?.dispose();

      _cameraController = CameraController(
        _cameras[_selectedCameraIdx],
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error initializing camera controller: $e');
    }
  }

  Future<void> _startRecording() async {
    debugPrint('DEBUG: _startRecording called');
    debugPrint('DEBUG: _cameraController null? ${_cameraController == null}');
    debugPrint(
      'DEBUG: camera initialized? ${_cameraController?.value.isInitialized}',
    );

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      debugPrint('DEBUG: Camera not ready, returning');
      return;
    }

    try {
      debugPrint('DEBUG: About to start video recording');

      // Try reinitializing camera if recording fails
      if (!_cameraController!.value.isRecordingVideo) {
        debugPrint('DEBUG: Reinitializing camera before recording');
        await _initializeCameraController();
        await Future.delayed(const Duration(milliseconds: 500)); // Give it time
      }

      await _cameraController!.startVideoRecording();

      setState(() {
        _isRecording = true;
        _secondsRecorded = 0;
      });

      // Start progress animation
      _progressController.forward();

      // Start timer
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _secondsRecorded++;
        });

        // Auto-stop at max duration (Google Messages behavior)
        if (_secondsRecorded >= _maxRecordingSeconds) {
          _stopRecording();
        }
      });
    } catch (e) {
      debugPrint('Error starting recording: $e');
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_cameraController == null || !_isRecording) return;

    try {
      final video = await _cameraController!.stopVideoRecording();
      _recordingTimer?.cancel();
      _progressController.stop();

      setState(() {
        _isRecording = false;
        _videoPath = video.path;
        _showPreview = true;
      });

      // Initialize video player for preview (skip on emulator if it fails)
      try {
        _videoController = VideoPlayerController.file(File(video.path));
        await _videoController!.initialize();

        setState(() {
          _showPreview = true;
        });
      } catch (videoError) {
        debugPrint('Video player error (emulator limitation): $videoError');
        // On emulator, skip preview and go straight to send option
        setState(() {
          _showPreview = true; // Still show controls, just no video preview
        });
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      // Reset recording state on error
      setState(() {
        _isRecording = false;
        _secondsRecorded = 0;
      });
      _progressController.reset();
    }
  }

  void _deleteRecording() {
    if (_videoPath != null && _videoPath!.isNotEmpty) {
      try {
        File(_videoPath!).deleteSync();
      } catch (e) {
        debugPrint('Error deleting video file: $e');
      }
    }

    _videoController?.dispose();
    _videoController = null;

    setState(() {
      _showPreview = false;
      _videoPath = null;
      _secondsRecorded = 0;
    });

    _progressController.reset();
  }

  void _sendVideo() {
    if (_videoPath != null) {
      // Return the video path to the parent
      Navigator.of(context).pop(_videoPath);
    }
  }

  void _cancelRecording() {
    if (_isRecording) {
      _stopRecording();
    }
    if (_videoPath != null && _videoPath!.isNotEmpty) {
      try {
        File(_videoPath!).deleteSync();
      } catch (e) {
        debugPrint('Error deleting video file: $e');
      }
    }
    Navigator.of(context).pop();
  }

  Future<void> _takePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final XFile photo = await _cameraController!.takePicture();

      setState(() {
        _videoPath = photo.path; // Reuse the path variable for simplicity
        _showPreview = true;
      });

      debugPrint('📸 Photo taken: ${photo.path}');
    } catch (e) {
      debugPrint('Error taking photo: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    setState(() {
      _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
    });

    await _initializeCameraController();
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _flashMode =
          _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    });

    await _cameraController!.setFlashMode(_flashMode);
  }

  Future<void> _setZoom(double zoom) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _zoomLevel = zoom;
    });

    await _cameraController!.setZoomLevel(zoom);
  }

  Widget _buildZoomButton(String label, double zoom) {
    bool isSelected = _zoomLevel == zoom;
    return GestureDetector(
      onTap: () => _setZoom(zoom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _progressController.dispose();
    _cameraController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview or video preview
          Positioned.fill(
            child:
                _showPreview && _videoController != null
                    ? VideoPlayer(_videoController!)
                    : CameraPreview(_cameraController!),
          ),

          // Play/pause button overlay for video preview
          if (_showPreview && _videoController != null)
            Positioned.fill(
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_videoController!.value.isPlaying) {
                        _videoController!.pause();
                      } else {
                        _videoController!.play();
                      }
                    });
                  },
                  child: AnimatedOpacity(
                    opacity: _videoController!.value.isPlaying ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.black,
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
                ),
              ),
            ),

          // Top controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: GestureDetector(
              onTap: _cancelRecording,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),

          // Zoom controls (center, like Google Messages)
          if (!_isRecording && !_showPreview)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildZoomButton('0.5', 0.5),
                      const SizedBox(width: 4),
                      _buildZoomButton('1.0', 1.0),
                      const SizedBox(width: 4),
                      _buildZoomButton('2.0', 2.0),
                    ],
                  ),
                ),
              ),
            ),

          // Flash toggle button
          if (!_isRecording && !_showPreview)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              child: GestureDetector(
                onTap: _toggleFlash,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _flashMode == FlashMode.off
                        ? Icons.flash_off
                        : Icons.flash_on,
                    color:
                        _flashMode == FlashMode.off
                            ? Colors.white
                            : Colors.yellow,
                    size: 24,
                  ),
                ),
              ),
            ),

          // Recording timer (only show during recording)
          if (_isRecording)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '00:${_secondsRecorded.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 40,
            left: 0,
            right: 0,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    if (_showPreview) {
      // Preview mode: trash and send buttons
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Trash button
          GestureDetector(
            onTap: _deleteRecording,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete, color: Colors.white, size: 32),
            ),
          ),

          // Send button
          GestureDetector(
            onTap: _sendVideo,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 32),
            ),
          ),
        ],
      );
    } else {
      // Google Messages style bottom layout
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main control row with filters, capture, selfie
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Filters button (left)
              GestureDetector(
                onTap: () {
                  // TODO: Implement filters
                  debugPrint('Filters tapped');
                },
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),

              // Capture button (center)
              GestureDetector(
                onTap:
                    _isRecording
                        ? _stopRecording
                        : (_captureMode == 'photo'
                            ? _takePhoto
                            : _startRecording),
                child: Container(
                  width: 80,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Progress circle (only show during recording)
                      if (_isRecording)
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: AnimatedBuilder(
                            animation: _progressAnimation,
                            builder: (context, child) {
                              return CircularProgressIndicator(
                                value: _progressAnimation.value,
                                strokeWidth: 4,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.red,
                                ),
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.3,
                                ),
                              );
                            },
                          ),
                        ),

                      // Capture button - inline to avoid function call issues
                      _buildCaptureButton(),
                    ],
                  ),
                ),
              ),

              // Selfie/Camera flip button (right)
              GestureDetector(
                onTap: _cameras.length > 1 ? _switchCamera : null,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.flip_camera_ios,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Photo/Video toggle (bottom, like Google Messages)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            // Move the container so selected option is under capture button
            transform: Matrix4.translationValues(
              _captureMode == 'photo'
                  ? 50.0
                  : -50.0, // Fine-tuned position - photo right, video left
              0.0,
              0.0,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _captureMode = 'photo'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _captureMode == 'photo'
                                ? Colors.white
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Photo',
                        style: TextStyle(
                          color:
                              _captureMode == 'photo'
                                  ? Colors.black
                                  : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _captureMode = 'video'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _captureMode == 'video'
                                ? Colors.white
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Video',
                        style: TextStyle(
                          color:
                              _captureMode == 'video'
                                  ? Colors.black
                                  : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
  }
}
