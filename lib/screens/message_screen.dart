import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: type == 'photo' ? FileType.image : FileType.video,
        allowMultiple: false,
        withData: false, // Don't download large cloud files to memory
      );

      if (!mounted) return;

      if (result != null) {
        PlatformFile file = result.files.first;

        // Debug output
        debugPrint('🔍 Picked file path: ${file.path}');
        debugPrint('🔍 Picked file name: ${file.name}');
        debugPrint('🔍 Picked file size: ${file.size}');
        debugPrint('🔍 File identifier: ${file.identifier}');

        // Determine file source
        bool isCloudFile =
            file.identifier != null &&
            file.identifier!.startsWith('content://') &&
            !file.identifier!.contains('com.android.providers.media.documents');

        if (isCloudFile) {
          debugPrint('🔍 ☁️ CLOUD FILE detected (cached)');
        } else {
          debugPrint('🔍 ✅ LOCAL FILE detected');
        }

        if (type == 'video') {
          final int fileSizeBytes = file.size;
          final double fileSizeMB = fileSizeBytes / (1024 * 1024);
          debugPrint(
            '🔍 File size: ${fileSizeMB}MB, limit: ${AppConfig.maxFileUploadSizeMB}MB',
          );

          if (fileSizeMB > AppConfig.maxFileUploadSizeMB) {
            // LARGE FILE - different handling based on source
            if (isCloudFile) {
              // LARGE CLOUD FILE (cached) - handle as external video
              debugPrint('🔍 Large cloud file - handling as external video');
              await _processExternalVideo(File(file.path!));
            } else {
              // LARGE LOCAL FILE - show upload dialog
              debugPrint('🔍 Large local file - showing upload dialog');
              final action = await LargeVideoDialog.show(context, fileSizeMB);

              if (action == VideoSizeAction.chooseDifferent) {
                _showMediaPicker();
              } else if (action == VideoSizeAction.shareAsLink) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Upload your video to Google Drive or Dropbox first, then select it from there.',
                    ),
                    duration: Duration(seconds: 4),
                  ),
                );
                _showMediaPicker();
              }
            }
            return; // Exit early for large files
          }
        }

        // SMALL FILE (any source) - process normally
        debugPrint('🔍 Small file - processing normally');
        await _processLocalFile(File(file.path!), type);
      }
    } catch (e) {
      if (e is PlatformException && e.code == 'unknown_path') {
        // VERY LARGE CLOUD FILE - couldn't cache
        debugPrint('🔍 Very large cloud file - showing URL input dialog');
        await _handleVeryLargeCloudFile(type);
      } else {
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
  }

  Future<void> _processLocalFile(File file, String type) async {
    // Dispose previous controllers
    _videoController?.dispose();
    _chewieController?.dispose();
    _videoController = null;
    _chewieController = null;
    _selectedVideoThumbnail = null;

    if (type == 'video') {
      // Generate thumbnail
      final File? thumbnailFile = await VideoThumbnailUtil.generateThumbnail(
        'file://${file.path}',
      );
      _selectedVideoThumbnail = thumbnailFile;

      // Initialize video controller
      _videoController = VideoPlayerController.file(file);
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
      _selectedMediaFile = file;
      _selectedMediaType = type;
    });
  }

  Future<void> _processExternalVideo(File file) async {
    // LARGE CLOUD FILE (cached) - we have cached file + cloud URI
    try {
      // Generate thumbnail from cached file
      final File? thumbnailFile = await VideoThumbnailUtil.generateThumbnail(
        'file://${file.path!}',
      );

      if (thumbnailFile != null) {
        debugPrint('🔍 Generated thumbnail for external video');

        // Show URL input dialog
        final String? dialogResult = await _showVideoUrlDialog();

        if (dialogResult != null && dialogResult.trim().isNotEmpty) {
          // Parse the result - format is "message|||url"
          final parts = dialogResult.split('|||');
          final userMessage = parts.length > 0 ? parts[0].trim() : '';
          final userUrl = parts.length > 1 ? parts[1].trim() : '';

          if (_isValidVideoUrl(userUrl)) {
            debugPrint('🔍 Valid URL provided: $userUrl');
            debugPrint('🔍 User message: $userMessage');

            // Post the external video message with thumbnail
            try {
              final apiService = Provider.of<ApiService>(
                context,
                listen: false,
              );

              Message newMessage = await apiService.postMessage(
                int.tryParse(widget.userId) ?? 0,
                userMessage.isNotEmpty
                    ? userMessage
                    : 'Shared external video', // Use user message or fallback
                mediaPath: thumbnailFile.path, // Thumbnail file path
                mediaType: 'image', // Thumbnail is an image
                videoUrl: userUrl, // External video URL
              );

              // Add to local message list and refresh
              setState(() {
                _messages.insert(0, newMessage);
              });
              await _loadMessages(); // Reload messages to get updated data

              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('External video posted successfully!'),
                  duration: Duration(seconds: 3),
                  backgroundColor: Colors.green,
                ),
              );

              // Scroll to bottom
              _scrollToBottomIfNeeded();
            } catch (e) {
              debugPrint('Error posting external video message: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error posting external video: $e'),
                  duration: const Duration(seconds: 3),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Please enter a valid video URL (must start with https://)',
                ),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          debugPrint('🔍 User cancelled URL input');
        }
      } else {
        debugPrint('🔍 Failed to generate thumbnail');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate thumbnail for external video'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error processing external video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing external video: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<String?> _showVideoUrlDialog() async {
    final TextEditingController urlController = TextEditingController();
    final TextEditingController messageController = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Share Video Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add a message for your video:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: messageController,
                decoration: const InputDecoration(
                  hintText: 'What would you like to say about this video?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Text(
                'Please paste the shareable link to your video:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  hintText: 'https://drive.google.com/file/d/...',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              const Text(
                'Make sure the link is publicly accessible or shared with your family.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final url = urlController.text.trim();
                final message = messageController.text.trim();
                if (url.isNotEmpty) {
                  Navigator.of(
                    context,
                  ).pop('$message|||$url'); // Use delimiter to pass both
                }
              },
              child: const Text('Share Video'),
            ),
          ],
        );
      },
    );
  }

  bool _isValidVideoUrl(String url) {
    return url.startsWith('https://') && url.length > 10;
  }

  Future<void> _handleVeryLargeCloudFile(String type) async {
    // VERY LARGE CLOUD FILE - no cached file available, need user URL
    if (type == 'video') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Video too large to cache. You can still share it using a direct link.',
          ),
          duration: Duration(seconds: 3),
        ),
      );

      // Show URL input dialog for very large cloud files
      final String? dialogResult = await _showVideoUrlDialog();

      if (dialogResult != null && dialogResult.trim().isNotEmpty) {
        // Parse the result - format is "message|||url"
        final parts = dialogResult.split('|||');
        final userMessage = parts.length > 0 ? parts[0].trim() : '';
        final userUrl = parts.length > 1 ? parts[1].trim() : '';

        if (_isValidVideoUrl(userUrl)) {
          debugPrint('🔍 Very large file - Valid URL provided: $userUrl');
          debugPrint('🔍 Very large file - User message: $userMessage');

          // Post the external video message without thumbnail (very large file)
          try {
            final apiService = Provider.of<ApiService>(context, listen: false);

            Message newMessage = await apiService.postMessage(
              int.tryParse(widget.userId) ?? 0,
              userMessage.isNotEmpty ? userMessage : 'Shared external video',
              videoUrl: userUrl, // External video URL, no thumbnail file
            );

            // Add to local message list and refresh
            setState(() {
              _messages.insert(0, newMessage);
            });
            await _loadMessages(); // Reload messages to get updated data

            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('External video posted successfully!'),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.green,
              ),
            );

            // Scroll to bottom
            _scrollToBottomIfNeeded();
          } catch (e) {
            debugPrint('Error posting very large external video: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error posting external video: $e'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please enter a valid video URL (must start with https://)',
              ),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        debugPrint('🔍 User cancelled very large file URL input');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo too large to process.'),
          duration: Duration(seconds: 3),
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
