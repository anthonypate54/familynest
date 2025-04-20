import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
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
  File? _selectedMedia;
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

  Future<void> _pickMedia(ImageSource source, String type) async {
    try {
      final XFile? pickedFile;
      if (type == 'photo') {
        pickedFile = await _picker.pickImage(source: source);
      } else {
        pickedFile = await _picker.pickVideo(source: source);
      }

      if (pickedFile != null) {
        if (type == 'video') {
          _videoController?.dispose();
          _videoController = VideoPlayerController.file(File(pickedFile.path))
            ..initialize().then((_) {
              setState(() {});
            });
        }
        final filePath = pickedFile.path;
        setState(() {
          _selectedMedia = File(filePath);
          _selectedMediaType = type;
        });
      }
    } catch (e) {
      debugPrint('Error picking media: $e');
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
            ],
          ),
        );
      },
    );
  }

  Future<void> _postMessage() async {
    if (_messageController.text.isEmpty && _selectedMedia == null) return;
    try {
      await widget.apiService.postMessage(
        widget.userId,
        _messageController.text,
        media: _selectedMedia,
        mediaType: _selectedMediaType,
      );
      _messageController.clear();
      setState(() {
        _selectedMedia = null;
        _selectedMediaType = null;
        _videoController?.dispose();
        _videoController = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message posted successfully!')),
      );
    } catch (e) {
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
    if (_selectedMedia == null) return const SizedBox.shrink();

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
                    ? Image.file(_selectedMedia!, fit: BoxFit.cover)
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
                  _selectedMedia = null;
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
                                                  : AspectRatio(
                                                    aspectRatio: 16 / 9,
                                                    child: VideoPlayer(
                                                      VideoPlayerController.network(
                                                          '${widget.apiService.baseUrl}$mediaUrl',
                                                        )
                                                        ..initialize().then((
                                                          _,
                                                        ) {
                                                          setState(() {});
                                                        }),
                                                    ),
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
}
