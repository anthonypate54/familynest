import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../services/api_service.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const HomeScreen({super.key, required this.apiService, required this.userId});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final TextEditingController _messageController = TextEditingController();
  final Map<int, String> _userPhotos = {};
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedMediaFile;
  String? _selectedMediaType;
  VideoPlayerController? _videoController;

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadMessages() async {
    try {
      final messages = await widget.apiService.getMessages(widget.userId);
      debugPrint('Received messages: $messages');
      for (var message in messages) {
        debugPrint('Message data: $message');
        final senderId = message['senderId'] as int?;
        debugPrint('SenderId: $senderId');
        if (senderId != null) {
          try {
            final user = await widget.apiService.getUserById(senderId);
            debugPrint('User data for $senderId: $user');
            if (user['photo'] != null) {
              _userPhotos[senderId] = user['photo'];
            }
          } catch (e) {
            debugPrint('Error fetching photo for user $senderId: $e');
          }
        }
      }
      return messages;
    } catch (e) {
      debugPrint('Error loading messages: $e');
      rethrow;
    }
  }

  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia(ImageSource.camera, 'photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia(ImageSource.gallery, 'photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Record a video'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia(ImageSource.camera, 'video');
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Choose video from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia(ImageSource.gallery, 'video');
                },
              ),
              ListTile(
                leading: const Icon(Icons.sd_card),
                title: const Text('Use sample video'),
                onTap: () {
                  Navigator.pop(context);
                  _showSampleVideoDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help finding videos'),
                onTap: () {
                  Navigator.pop(context);
                  _showVideoHelpDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSampleVideoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sample Video Information'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'About the sample_video.mp4 in DCIM:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The sample_video.mp4 file in your DCIM folder is causing an "UnrecognizedInputFormatException"',
                ),
                const Text(
                  'This means the video is in a format the emulator cannot decode.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'What you can do:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  '1. Try taking a photo instead - photos work reliably',
                ),
                const Text('2. Test on a physical device with real videos'),
                const Text(
                  '3. Create a test MP4 using the Camera app directly',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Why this happens:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('• Android emulators have limited codec support'),
                const Text(
                  '• The sample_video.mp4 might use an unsupported codec',
                ),
                const Text(
                  '• This is a common issue in emulators, not in real devices',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                // Try camera for a photo instead
                Navigator.of(context).pop();
                _pickMedia(ImageSource.camera, 'photo');
              },
              child: const Text('Take a Photo Instead'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickMedia(ImageSource source, String type) async {
    try {
      // Set additional options for image/video picker to improve compatibility
      final XFile? pickedFile;
      if (type == 'photo') {
        debugPrint('Attempting to pick image from source: $source');
        pickedFile = await _picker.pickImage(
          source: source,
          maxWidth: 1800,
          maxHeight: 1800,
          imageQuality: 85,
        );
      } else {
        debugPrint('Attempting to pick video from source: $source');
        pickedFile = await _picker.pickVideo(
          source: source,
          maxDuration: const Duration(minutes: 10), // limit video size
        );
      }

      if (pickedFile != null) {
        debugPrint(
          'Media picked successfully: ${pickedFile.path}, type: $type',
        );

        // Verify the file exists
        final file = File(pickedFile.path);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint(
            'File exists at path: ${pickedFile.path}, size: $fileSize bytes',
          );

          // Special handling for 0-byte files (emulator issue)
          if (fileSize == 0 && type == 'video') {
            debugPrint(
              'Special case: 0-byte video file detected (emulator issue)',
            );
            // Try to get stats about the file
            try {
              final stat = await file.stat();
              debugPrint('File stats: ${stat.toString()}');

              // Show dialog asking if they want to try anyway
              bool shouldContinue =
                  await showDialog<bool>(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('Video Size Issue'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'The video file appears to be empty (0 bytes).',
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'This is a common issue with Android emulators.',
                              ),
                              const SizedBox(height: 16),
                              const Text('Do you want to:'),
                              const SizedBox(height: 8),
                              const Text(
                                '1. Try sending it anyway (may not work)',
                              ),
                              const Text('2. Try using a photo instead'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Try Anyway'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context, false);
                                _pickMedia(ImageSource.gallery, 'photo');
                              },
                              child: const Text('Select Photo Instead'),
                            ),
                          ],
                        ),
                  ) ??
                  false;

              if (!shouldContinue) {
                return;
              }
            } catch (e) {
              debugPrint('Error getting file stats: $e');
            }
          }
        } else {
          debugPrint(
            'Warning: File does not exist at path: ${pickedFile.path}',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Selected file could not be accessed. Try again or select a different file.',
              ),
            ),
          );
          return;
        }

        setState(() {
          _selectedMediaFile = pickedFile;
          _selectedMediaType = type;
        });

        if (type == 'video' && !kIsWeb) {
          try {
            _videoController?.dispose();
            debugPrint('Initializing video controller for: ${pickedFile.path}');
            _videoController = VideoPlayerController.file(File(pickedFile.path))
              ..initialize()
                  .then((_) {
                    setState(() {});
                    debugPrint('Video controller initialized successfully');
                    final duration = _videoController!.value.duration;
                    debugPrint('Video duration: $duration');

                    // For emulator/simulator, sometimes the duration can't be determined
                    // but the video might still be valid
                    if (duration.inMilliseconds > 0) {
                      // Auto-play once to confirm it works
                      _videoController?.play();
                      Future.delayed(const Duration(seconds: 1), () {
                        if (_videoController?.value.isPlaying ?? false) {
                          _videoController?.pause();
                        }
                      });
                    } else {
                      debugPrint(
                        'Warning: Video has zero duration, but may still be valid',
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Video duration is zero, but we will try to use it anyway.',
                          ),
                        ),
                      );
                    }
                  })
                  .catchError((error) {
                    debugPrint(
                      'Error in video controller initialization: $error',
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not preview video: $error'),
                      ),
                    );
                  });
          } catch (e) {
            debugPrint('Error initializing video player: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error initializing video: $e')),
            );
          }
        }
      } else {
        debugPrint('No media selected by user');
        if (source == ImageSource.gallery && type == 'video') {
          // Show help dialog automatically when no video was selected
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _showVideoHelpDialog();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking media: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking media: $e'),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Help',
            onPressed: _showVideoHelpDialog,
          ),
        ),
      );
    }
  }

  void _showVideoHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Finding Videos in Emulator'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'To use a video from your emulator:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text('1. Open the "Files" app in your emulator'),
                const Text('2. Look for the DCIM folder (Camera)'),
                const Text(
                  '3. Create a sample video with camera app if needed',
                ),
                const SizedBox(height: 16),
                const Text(
                  'For your specific emulator setup:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  '1. Try using the "Camera" app to record a short video',
                ),
                const Text('2. It will be saved in the DCIM/Camera folder'),
                const Text('3. Return to the app and select from gallery'),
                const SizedBox(height: 16),
                const Text(
                  'If still having issues:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  '1. Try using a physical device instead of emulator',
                ),
                const Text(
                  '2. Emulators sometimes have permission issues with media',
                ),
                const Text(
                  '3. You could also try creating a test image instead',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _postMessage() async {
    if (_messageController.text.isEmpty && _selectedMediaFile == null) return;
    try {
      debugPrint(
        'Attempting to post message with text: ${_messageController.text}',
      );
      if (_selectedMediaFile != null) {
        debugPrint(
          'With media: ${_selectedMediaFile!.path}, type: $_selectedMediaType',
        );

        // Check if the file exists
        final file = File(_selectedMediaFile!.path);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint('File exists and size is: $fileSize bytes');

          // Special warning for 0-byte files (emulator issue)
          if (fileSize == 0 && _selectedMediaType == 'video') {
            debugPrint(
              'Warning: 0-byte video file being sent (emulator issue)',
            );

            bool shouldContinue =
                await showDialog<bool>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('Warning: Empty Video File'),
                        content: const Text(
                          'You are about to send a 0-byte video file, which likely will not work. This is common in emulators. Continue anyway?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Send Anyway'),
                          ),
                        ],
                      ),
                ) ??
                false;

            if (!shouldContinue) {
              return;
            }
          }
        } else {
          debugPrint(
            'File does not exist at path: ${_selectedMediaFile!.path}',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Media file no longer exists. Please select again.',
              ),
            ),
          );
          return;
        }
      }

      await widget.apiService.postMessage(
        widget.userId,
        _messageController.text,
        mediaPath: _selectedMediaFile?.path,
        mediaType: _selectedMediaType,
      );
      debugPrint('Message posted successfully');

      _messageController.clear();
      setState(() {
        _selectedMediaFile = null;
        _selectedMediaType = null;
        _videoController?.dispose();
        _videoController = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message posted successfully!')),
      );
    } catch (e) {
      debugPrint('Error posting message: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error posting message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildMediaPreview() {
    if (_selectedMediaFile == null) return const SizedBox.shrink();

    return Stack(
      children: [
        Container(
          height: 150,
          width: double.infinity,
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[200],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child:
                _selectedMediaType == 'photo'
                    ? kIsWeb
                        ? Image.network(
                          _selectedMediaFile!.path,
                          fit: BoxFit.cover,
                        )
                        : Image.file(
                          File(_selectedMediaFile!.path),
                          fit: BoxFit.cover,
                        )
                    : _videoController?.value.isInitialized ?? false
                    ? AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_videoController!),
                          IconButton(
                            icon: Icon(
                              _videoController!.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                            onPressed: () {
                              setState(() {
                                _videoController!.value.isPlaying
                                    ? _videoController!.pause()
                                    : _videoController!.play();
                              });
                            },
                          ),
                        ],
                      ),
                    )
                    : const Center(child: CircularProgressIndicator()),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: CircleAvatar(
            backgroundColor: Colors.black54,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  _selectedMediaFile = null;
                  _selectedMediaType = null;
                  _videoController?.dispose();
                  _videoController = null;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => ProfileScreen(
                        apiService: widget.apiService,
                        userId: widget.userId,
                        role: null,
                      ),
                ),
              );
            },
            tooltip: 'Go to Profile',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadMessages(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Failed to load messages',
                          style: TextStyle(fontSize: 18, color: Colors.red),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final senderId = message['senderId'] as int?;
                    final photoUrl = message['senderPhoto'] as String?;
                    final mediaType = message['mediaType'];
                    final mediaUrl = message['mediaUrl'];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Profile Photo
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.blue,
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child:
                                        photoUrl != null
                                            ? Image.network(
                                              '${widget.apiService.baseUrl}$photoUrl',
                                              fit: BoxFit.cover,
                                              errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                              ) {
                                                return const Icon(
                                                  Icons.person,
                                                  color: Colors.blue,
                                                );
                                              },
                                            )
                                            : const Icon(
                                              Icons.person,
                                              color: Colors.blue,
                                            ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Message Content
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        message['senderUsername'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (message['content'].isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          message['content'],
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ],
                                      if (mediaUrl != null) ...[
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child:
                                              mediaType == 'photo'
                                                  ? Image.network(
                                                    '${widget.apiService.baseUrl}$mediaUrl',
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: 200,
                                                    errorBuilder: (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      debugPrint(
                                                        'Error loading image: $error',
                                                      );
                                                      return Container(
                                                        width: double.infinity,
                                                        height: 200,
                                                        color: Colors.grey[300],
                                                        child: const Icon(
                                                          Icons.broken_image,
                                                          color: Colors.grey,
                                                          size: 50,
                                                        ),
                                                      );
                                                    },
                                                  )
                                                  : Builder(
                                                    builder: (context) {
                                                      final videoUrl =
                                                          '${widget.apiService.baseUrl}$mediaUrl';
                                                      debugPrint(
                                                        'Loading video from: $videoUrl',
                                                      );
                                                      return GestureDetector(
                                                        onTap: () {
                                                          _playMessageVideo(
                                                            videoUrl,
                                                            context,
                                                          );
                                                        },
                                                        child: Stack(
                                                          alignment:
                                                              Alignment.center,
                                                          children: [
                                                            Container(
                                                              height: 200,
                                                              width:
                                                                  double
                                                                      .infinity,
                                                              color:
                                                                  Colors.black,
                                                              child: const Center(
                                                                child: Text(
                                                                  'Video',
                                                                  style: TextStyle(
                                                                    color:
                                                                        Colors
                                                                            .white,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            const Icon(
                                                              Icons
                                                                  .play_circle_fill,
                                                              size: 50,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        message['timestamp'],
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildMediaPreview(),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _showMediaPicker,
                      tooltip: 'Add Media',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Enter your message',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: _postMessage,
                        tooltip: 'Send Message',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _playMessageVideo(String videoUrl, BuildContext context) {
    debugPrint('Playing video from URL: $videoUrl');

    // Show loading dialog while we check the video
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Preparing video...'),
              ],
            ),
          ),
    );

    final controller = VideoPlayerController.network(videoUrl);

    controller
        .initialize()
        .then((_) {
          // Close loading dialog
          Navigator.of(context).pop();

          // Show the video player dialog
          showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                contentPadding: EdgeInsets.zero,
                content: StatefulBuilder(
                  builder: (context, setState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                controller.value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.blue,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (controller.value.isPlaying) {
                                    controller.pause();
                                  } else {
                                    controller.play();
                                  }
                                });
                              },
                            ),
                            Slider(
                              value:
                                  controller.value.position.inSeconds
                                      .toDouble(),
                              min: 0,
                              max:
                                  controller.value.duration.inSeconds
                                      .toDouble(),
                              onChanged: (value) {
                                setState(() {
                                  controller.seekTo(
                                    Duration(seconds: value.toInt()),
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      controller.pause();
                      controller.dispose();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          );

          // Start playing the video
          controller.play();
        })
        .catchError((error) {
          // Close loading dialog
          Navigator.of(context).pop();

          debugPrint('Error initializing video player: $error');

          // Show error dialog with download option
          showDialog(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Video Error'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Unable to play this video format.'),
                      const SizedBox(height: 16),
                      const Text('Possible solutions:'),
                      const SizedBox(height: 8),
                      const Text('• Download and view in another app'),
                      const Text('• Try on a physical device'),
                      const Text('• This may be an emulator limitation'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        _launchUrl(videoUrl);
                        Navigator.of(context).pop();
                      },
                      child: const Text('Open in Browser'),
                    ),
                  ],
                ),
          );
        });
  }

  void _launchUrl(String url) {
    // Can't directly open URLs without additional packages, so show instructions
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Open in Browser'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Video URL:'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    url,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Copy this URL and open it in your browser.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}
