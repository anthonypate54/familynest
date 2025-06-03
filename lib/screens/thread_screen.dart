import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/message_provider.dart';
import '../models/message.dart';
import './compose_message_screen.dart';
import '../config/ui_config.dart';
import '../services/api_service.dart';
import '../services/message_service.dart';
import '../utils/auth_utils.dart';
import 'dart:io';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../utils/video_thumbnail_util.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ThreadScreen extends StatefulWidget {
  final int userId;
  final Map<String, dynamic> message; // Add this

  const ThreadScreen({
    Key? key,
    required this.userId,
    required this.message, // Add this
  }) : super(key: key);

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final ValueNotifier<bool> _isSendButtonEnabled = ValueNotifier(false);
  File? _selectedMediaFile;
  String? _selectedMediaType;
  final ImagePicker _picker = ImagePicker();
  // Video preview fields for composing
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  File? _selectedVideoThumbnail;
  List<Message> _comments = [];
  bool _isLoading = true;

  // --- Inline video playback for message feed ---
  String? _currentlyPlayingVideoId;

  Future<void> _loadComments() async {
    setState(() {
      _isLoading = true;
    });
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final comments = await apiService.getComments(
        widget.message['id'].toString(),
      );
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading comments: $e')));
      }
    }
  }

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
  void initState() {
    super.initState();
    _messageController.addListener(() {
      _isSendButtonEnabled.value = _messageController.text.trim().isNotEmpty;
    });
    _loadComments();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    _isSendButtonEnabled.dispose();
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  /// Handle logout action
  void _logout() async {
    await AuthUtils.showLogoutConfirmation(
      context,
      Provider.of<ApiService>(context, listen: false),
    );
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

  void _scrollToBottomIfNeeded() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, // For reverse: true, this is the bottom
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _postComment(ApiService apiService) async {
    final text = _messageController.text.trim();
    if (_selectedMediaFile != null) {
      Message newMessage = await apiService.postComment(
        int.parse(widget.userId.toString()),
        int.parse(widget.message['id'].toString()),
        text,
        mediaPath: _selectedMediaFile!.path,
        mediaType: _selectedMediaType ?? 'photo',
      );
      if (!mounted) return;
      setState(() {
        _selectedMediaFile = null;
        _selectedMediaType = null;
        _comments.add(newMessage); // Add new message to the list
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0, // Always scroll to the bottom in reverse mode
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }); // Update comment count after successful post
      Provider.of<MessageProvider>(
        context,
        listen: false,
      ).incrementCommentCount(newMessage.parentMessageId.toString());
    } else if (text.isNotEmpty) {
      Message newMessage = await apiService.postComment(
        widget.userId,
        int.parse(widget.message['id']),
        text,
      );
      if (!mounted) return;
      setState(() {
        _comments.insert(0, newMessage); // Add new message to the list
      });
      // Update comment count after successful post
      Provider.of<MessageProvider>(
        context,
        listen: false,
      ).incrementCommentCount(newMessage.parentMessageId.toString());
    }
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final parentMessage = Message.fromJson(widget.message);
    return Scaffold(
      backgroundColor: UIConfig.useDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        title: const Text('Comments'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            onPressed: () {
              setState(() {});
            },
            tooltip: 'Refresh Messages',
          ),
          IconButton(
            icon: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: GradientBackground(
        child: Column(
          children: [
            // The scrollable area with sticky parent and comments
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ParentMessageHeaderDelegate(
                      hasMedia:
                          parentMessage.mediaUrl != null &&
                          parentMessage.mediaUrl!.isNotEmpty,
                      child: MessageCard(
                        message: parentMessage,
                        apiService: apiService,
                        currentUserId: widget.userId.toString(),
                        timeText: MessageService.formatTime(
                          context,
                          parentMessage.createdAt,
                        ),
                        dayText: MessageService.getShortDayName(
                          parentMessage.createdAt,
                        ),
                        shouldShowDateSeparator: false,
                        dateSeparatorText: null,
                        onTap: (msg) {},
                        onThreadTap: null,
                        currentlyPlayingVideoId: null,
                        suppressDateSeparator: true,
                        showCommentIcon: false,
                        parentId: widget.message['parentMessageId'].toString(),
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: true,
                    child:
                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : MessageService.buildMessageListView(
                              context,
                              _comments,
                              apiService: apiService,
                              scrollController: _scrollController,
                              currentUserId: widget.userId.toString(),
                              onTap: (message) {
                                if (message.mediaType == 'video') {
                                  setState(() {
                                    _currentlyPlayingVideoId = message.id;
                                  });
                                }
                              },
                              currentlyPlayingVideoId: _currentlyPlayingVideoId,
                              isThreadView: true,
                            ),
                  ),
                ],
              ),
            ),
            // Media preview (if any)
            if (_selectedMediaFile != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child:
                    _selectedMediaType == 'photo'
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            _selectedMediaFile!,
                            width: MediaQuery.of(context).size.width * 0.7,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        )
                        : _selectedMediaType == 'video'
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: MediaQuery.of(context).size.width * 0.7,
                            height: 200,
                            constraints: const BoxConstraints(
                              maxHeight: 200,
                              minHeight: 200,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 200,
                                minHeight: 200,
                              ),
                              child: ClipRect(
                                child:
                                    _chewieController != null
                                        ? Chewie(
                                          key: const ValueKey(
                                            'thread-composition-video',
                                          ),
                                          controller: _chewieController!,
                                        )
                                        : const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                              ),
                            ),
                          ),
                        )
                        : const SizedBox.shrink(),
              ),
            // Input bar
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _showMediaPicker,
                    tooltip: 'Attach Media',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _isSendButtonEnabled,
                    builder: (context, isEnabled, child) {
                      return IconButton(
                        icon: const Icon(Icons.send),
                        onPressed:
                            isEnabled ? () => _postComment(apiService) : null,
                        tooltip: 'Send Message',
                        color:
                            isEnabled
                                ? Theme.of(context).primaryColor
                                : Colors.grey,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentMessageHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final bool hasMedia;
  _ParentMessageHeaderDelegate({required this.child, this.hasMedia = false});

  @override
  double get minExtent {
    return hasMedia ? 200 : 100;
  }

  @override
  double get maxExtent {
    return hasMedia ? 280 : 120;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Calculate the progress of shrinking (0.0 = fully expanded, 1.0 = fully shrunk)
    final double shrinkProgress = shrinkOffset / (maxExtent - minExtent);
    final double clampedProgress = shrinkProgress.clamp(0.0, 1.0);

    // Interpolate the current height
    final double currentHeight =
        maxExtent - (shrinkOffset.clamp(0.0, maxExtent - minExtent));

    return SizedBox(height: currentHeight, child: child);
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    if (oldDelegate is _ParentMessageHeaderDelegate) {
      return hasMedia != oldDelegate.hasMedia;
    }
    return true;
  }
}
