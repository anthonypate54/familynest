import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import './compose_message_screen.dart';
import '../config/ui_config.dart';
import '../services/api_service.dart';
import '../services/message_service.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../utils/video_thumbnail_util.dart';

class MessageScreen extends StatefulWidget {
  final String userId;
  const MessageScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  File? _selectedMediaFile;
  String? _selectedMediaType;
  final ImagePicker _picker = ImagePicker();
  // Video preview fields
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  File? _selectedVideoThumbnail;

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
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

  Future<void> _pickMedia(ImageSource source, String type) async {
    try {
      final XFile? pickedFile;
      if (type == 'photo') {
        pickedFile = await _picker.pickImage(
          source: source,
          maxWidth: 1800,
          maxHeight: 1800,
          imageQuality: 85,
        );
      } else {
        pickedFile = await _picker.pickVideo(
          source: source,
          maxDuration: const Duration(minutes: 10),
        );
      }

      if (!mounted) return;

      if (pickedFile != null) {
        final file = pickedFile;
        if (type == 'video') {
          // Dispose previous controllers
          _videoController?.dispose();
          _chewieController?.dispose();
          _videoController = null;
          _chewieController = null;
          _selectedVideoThumbnail = null;

          // Generate thumbnail
          final File? thumbnailFile =
              await VideoThumbnailUtil.generateThumbnail('file://${file.path}');
          _selectedVideoThumbnail = thumbnailFile;

          // Initialize video controller
          _videoController = VideoPlayerController.file(File(file.path));
          await _videoController!.initialize();

          // Initialize Chewie controller
          _chewieController = ChewieController(
            videoPlayerController: _videoController!,
            aspectRatio: _videoController!.value.aspectRatio,
            autoPlay: false,
            looping: false,
            autoInitialize: true,
            showControls: true,
            placeholder:
                thumbnailFile != null
                    ? Image.file(
                      thumbnailFile,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    )
                    : Container(
                      color: Colors.black,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
            materialProgressColors: ChewieProgressColors(
              playedColor: Colors.blue,
              handleColor: Colors.blueAccent,
              backgroundColor: Colors.grey.shade700,
              bufferedColor: Colors.lightBlue.withOpacity(0.5),
            ),
            errorBuilder: (context, errorMessage) {
              return Center(
                child: Text(
                  'Error: $errorMessage',
                  style: const TextStyle(color: Colors.white),
                ),
              );
            },
          );
        }
        setState(() {
          _selectedMediaFile = File(file.path);
          _selectedMediaType = type;
        });
      }
    } catch (e) {
      debugPrint('Error picking media: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking media: $e'),
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  Future<void> _postMessage(ApiService apiService) async {
    final text = _messageController.text.trim();
    if (_selectedMediaFile != null) {
      await apiService.postMessage(
        int.tryParse(widget.userId) ?? 0,
        text,
        mediaPath: _selectedMediaFile!.path,
        mediaType: _selectedMediaType ?? 'photo',
      );
      setState(() {
        _selectedMediaFile = null;
        _selectedMediaType = null;
      });
    } else if (text.isNotEmpty) {
      await apiService.postMessage(int.tryParse(widget.userId) ?? 0, text);
    }
    _messageController.clear();
    setState(() {}); // Refresh messages
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    return Scaffold(
      backgroundColor: UIConfig.useDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.blue,
        elevation: 0,
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() {});
            },
            tooltip: 'Refresh Messages',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              // TODO: Implement logout logic
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Message>>(
              future: apiService.getUserMessages(widget.userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: \\${snapshot.error}'));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No messages found.'));
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });
                return MessageService.buildMessageListView(
                  snapshot.data!,
                  apiService: apiService,
                  scrollController: _scrollController,
                );
              },
            ),
          ),
          if (_selectedMediaFile != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  _selectedMediaType == 'photo'
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          _selectedMediaFile!,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.contain,
                        ),
                      )
                      : (_videoController != null &&
                          _videoController!.value.isInitialized)
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.7,
                          height: 200,
                          color: Colors.black,
                          child:
                              _chewieController != null &&
                                      _videoController != null &&
                                      _videoController!.value.isInitialized
                                  ? FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: _videoController!.value.size.width,
                                      height:
                                          _videoController!.value.size.height,
                                      child: Chewie(
                                        controller: _chewieController!,
                                      ),
                                    ),
                                  )
                                  : const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                        ),
                      )
                      : _selectedVideoThumbnail != null
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          _selectedVideoThumbnail!,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.contain,
                        ),
                      )
                      : Container(
                        width: 100,
                        height: 100,
                        color: Colors.black12,
                        child: const Center(
                          child: Icon(
                            Icons.videocam,
                            size: 40,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _selectedMediaFile = null;
                        _selectedMediaType = null;
                        _selectedVideoThumbnail = null;
                        _videoController?.dispose();
                        _videoController = null;
                        _chewieController?.dispose();
                        _chewieController = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
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
                    onPressed: () async {
                      await _postMessage(apiService);
                    },
                    tooltip: 'Send Message',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
