import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import './compose_message_screen.dart';
import '../config/ui_config.dart';
import '../services/api_service.dart';
import '../services/message_service.dart';
import '../utils/auth_utils.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../utils/video_thumbnail_util.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/message_provider.dart';
import '../dialogs/large_video_dialog.dart';
import '../config/app_config.dart';

class MessageScreen extends StatefulWidget {
  final String userId;
  const MessageScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final ValueNotifier<bool> _isSendButtonEnabled = ValueNotifier(false);
  File? _selectedMediaFile;
  String? _selectedMediaType;
  // Video preview fields for composing
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  File? _selectedVideoThumbnail;
  List<Message> _messages = [];
  bool _isLoading = true;

  // --- Inline video playback for message feed ---
  String? _currentlyPlayingVideoId;

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
    });
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final messages = await apiService.getUserMessages(widget.userId);
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
        Provider.of<MessageProvider>(
          context,
          listen: false,
        ).setMessages(messages);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading messages: $e')));
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
    _loadMessages();
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
                  _pickMedia('photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia('photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Record a video'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia('video');
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Choose video from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia('video');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickMedia(String type) async {
    try {
      FilePickerResult? result;
      if (type == 'photo') {
        result = await FilePicker.platform.pickFiles(type: FileType.image);
      } else {
        result = await FilePicker.platform.pickFiles(type: FileType.video);
      }

      final pickedFile = result?.files.first;

      if (pickedFile != null) {
        debugPrint('🔍 ##Picked file path: ${pickedFile.path}');
        debugPrint('🔍 Picked file name: ${pickedFile.name}');
        debugPrint('🔍 Picked file size: ${pickedFile.size}');

        // Add cloud detection:
        debugPrint('🔍 ###File identifier: ${pickedFile.identifier}');
        debugPrint('🔍 Has path: ${pickedFile.path != null}');
        debugPrint('🔍 Has identifier: ${pickedFile.identifier != null}');

        if (pickedFile.path != null) {
          debugPrint('🔍 ✅ LOCAL FILE detected');
        } else if (pickedFile.identifier != null) {
          debugPrint('🔍 ☁️ CLOUD FILE detected');
        }
      }
      if (!mounted) return;

      if (pickedFile != null) {
        final file = pickedFile;
        if (type == 'video') {
          final int fileSizeBytes = file.size;
          final double fileSizeMB = fileSizeBytes / (1024 * 1024);

          final File tmpfile = File(file.path!);
          final int tmpfileSizeBytes = await tmpfile.length();
          final double tmpfileSizeMB = tmpfileSizeBytes / (1024 * 1024);

          debugPrint(
            '🔍 Tmp file size: ${tmpfileSizeMB}MB, limit: ${AppConfig.maxFileUploadSizeMB}MB',
          );
          if (fileSizeMB > AppConfig.maxFileUploadSizeMB) {
            final action = await LargeVideoDialog.show(context, fileSizeMB);

            if (action == VideoSizeAction.chooseDifferent) {
              // Re-open picker
              _showMediaPicker();
            } else if (action == VideoSizeAction.shareAsLink) {
              // Show instruction and re-open picker for cloud selection
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Upload your video to Google Drive or Dropbox first, then select it from there.',
                  ),
                  duration: Duration(seconds: 4),
                ),
              );
              _showMediaPicker(); // Re-open picker
            }
            return; // Exit early
          } // Dispose previous controllers
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
          _videoController = VideoPlayerController.file(File(file.path!));
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
          _selectedMediaFile = File(file.path!);
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

  Future<void> _postMessage(ApiService apiService) async {
    final text = _messageController.text.trim();
    if (_selectedMediaFile != null) {
      Message newMessage = await apiService.postMessage(
        int.tryParse(widget.userId) ?? 0,
        text,
        mediaPath: _selectedMediaFile!.path,
        mediaType: _selectedMediaType ?? 'photo',
      );
      setState(() {
        _selectedMediaFile = null;
        _selectedMediaType = null;
        _messages.add(newMessage); // Add new message to the list
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0, // Always scroll to the bottom in reverse mode
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else if (text.isNotEmpty) {
      Message newMessage = await apiService.postMessage(
        int.tryParse(widget.userId) ?? 0,
        text,
      );
      setState(() {
        _messages.insert(0, newMessage); // Add new message to the list
      });
    }
    _messageController.clear();
    await _loadMessages(); // Reload messages after posting
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    return Scaffold(
      backgroundColor: UIConfig.useDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        title: const Text('Messages'),
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
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Consumer<MessageProvider>(
                        builder: (context, messageProvider, child) {
                          return MessageService.buildMessageListView(
                            context,
                            messageProvider.messages,
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
                          ); // buildMessageListView
                        },
                      ),
            ),
            if (_selectedMediaFile != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child:
                    _selectedMediaType == 'photo'
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            children: [
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.7,
                                height: 200,
                                child: Image.file(
                                  _selectedMediaFile!,
                                  width:
                                      MediaQuery.of(context).size.width * 0.7,
                                  height: 200,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.black,
                                      size: 18,
                                    ),
                                    padding: EdgeInsets.zero,
                                    splashRadius: 18,
                                    onPressed: () {
                                      setState(() {
                                        _selectedMediaFile = null;
                                        _selectedMediaType = null;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        : _selectedMediaType == 'video'
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            children: [
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.7,
                                height: 200,
                                child:
                                    _chewieController != null
                                        ? Chewie(
                                          key: const ValueKey(
                                            'message-composition-video',
                                          ),
                                          controller: _chewieController!,
                                        )
                                        : _selectedVideoThumbnail != null
                                        ? Image.file(
                                          _selectedVideoThumbnail!,
                                          width:
                                              MediaQuery.of(
                                                context,
                                              ).size.width *
                                              0.7,
                                          height: 200,
                                          fit: BoxFit.cover,
                                        )
                                        : Container(
                                          color: Colors.black,
                                          child: const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.black,
                                      size: 18,
                                    ),
                                    padding: EdgeInsets.zero,
                                    splashRadius: 18,
                                    onPressed: () {
                                      setState(() {
                                        _selectedMediaFile = null;
                                        _selectedMediaType = null;
                                        _videoController?.dispose();
                                        _chewieController?.dispose();
                                        _videoController = null;
                                        _chewieController = null;
                                        _selectedVideoThumbnail = null;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        : const SizedBox.shrink(),
              ),
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
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
                            isEnabled ? () => _postMessage(apiService) : null,
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
